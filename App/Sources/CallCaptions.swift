// CallCaptions.swift — live captions of what the other people in a call say: the
// call apps' sound (Zoom, Teams, FaceTime and the others in Settings) is captured with
// its own process tap, which doesn't change what you hear, and recognized on the Mac.
// Captions show in a large-print strip at the bottom of the screen, and "Read the last
// caption" speaks the newest one. Nothing is recorded or sent; the transcript is kept
// in memory until captions are turned off, and can be copied.

import AppKit
import AVFoundation
import CoreAudio
import Speech
import SwiftUI
import os

@MainActor
final class CallCaptions: ObservableObject {
    static let shared = CallCaptions()

    @Published private(set) var isRunning = false
    /// Finished lines, oldest first.
    @Published private(set) var lines: [String] = []
    /// What's being said now, still being recognized.
    @Published private(set) var partial = ""

    private var recognizer: SFSpeechRecognizer?
    private let currentRequest = OSAllocatedUnfairLock<SFSpeechAudioBufferRecognitionRequest?>(initialState: nil)
    private var task: SFSpeechRecognitionTask?
    private var restartTimer: Timer?
    private var watchTimer: Timer?
    private var tap = AudioObjectID(kAudioObjectUnknown)
    private var aggregate = AudioObjectID(kAudioObjectUnknown)
    private var ioProc: AudioDeviceIOProcID?
    private var tapped: Set<AudioObjectID> = []
    private var panel: NSPanel?
    private let queue = DispatchQueue(label: "VoiceOverAudioSplit.call-captions", qos: .userInteractive)
    private static let maxLines = 200

    func toggle() { isRunning ? stop() : start() }

    func start() {
        guard !isRunning else { return }
        SFSpeechRecognizer.requestAuthorization { status in
            DispatchQueue.main.async {
                guard status == .authorized else {
                    return Announcer.say(String(localized: "Call captions need Speech Recognition. Allow VoiceOver Audio Split in System Settings, Privacy and Security, Speech Recognition."))
                }
                self.begin()
            }
        }
    }

    private func begin() {
        let candidates = [SFSpeechRecognizer(locale: Locale.current), SFSpeechRecognizer(locale: Locale(identifier: "en-US"))]
        guard let recognizer = candidates.compactMap({ $0 }).first(where: \.supportsOnDeviceRecognition) else {
            return Announcer.say(String(localized: "Call captions aren't available: this Mac can't recognize speech on the device."))
        }
        self.recognizer = recognizer
        isRunning = true
        lines = []
        partial = ""
        showPanel()
        Tones.play(.status)
        Announcer.say(String(localized: "Call captions on. They appear when someone in the call speaks."))
        // Call apps start and stop their sound processes: check every few seconds.
        watchTimer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { _ in
            MainActor.assumeIsolated { CallCaptions.shared.capture() }
        }
        capture()
        listen()
    }

    func stop() {
        guard isRunning else { return }
        watchTimer?.invalidate()
        watchTimer = nil
        restartTimer?.invalidate()
        restartTimer = nil
        task?.cancel()
        task = nil
        currentRequest.withLock { $0 = nil }
        teardown()
        panel?.orderOut(nil)
        panel = nil
        isRunning = false
        Announcer.say(String(localized: "Call captions off."))
    }

    /// Speaks the newest caption.
    func readLast() {
        let last = partial.isEmpty ? lines.last : partial
        guard let last else {
            return Announcer.say(isRunning ? String(localized: "No captions yet.") : String(localized: "Call captions are off."))
        }
        Announcer.say(last)
    }

    /// Copies everything captioned since captions were turned on.
    func copyTranscript() {
        let text = (lines + (partial.isEmpty ? [] : [partial])).joined(separator: "\n")
        guard !text.isEmpty else { return Announcer.say(String(localized: "No captions yet.")) }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        Announcer.say(String(localized: "Call transcript copied."))
    }

    // MARK: Capturing call sound

    /// The audio processes of the call apps set in Settings.
    static func callProcesses(prefixes: [String]) -> Set<AudioObjectID> {
        let callPIDs = Set(NSWorkspace.shared.runningApplications.filter { app in
            prefixes.contains { app.bundleIdentifier?.hasPrefix($0) == true }
        }.map(\.processIdentifier))
        var testPIDs = Set<pid_t>()
        #if DEBUG
        // Self-check: caption a test process given by its process ID.
        testPIDs = Set((ProcessInfo.processInfo.environment["VOAS_CAPTION_PIDS"] ?? "").split(separator: ",").compactMap { pid_t($0) })
        #endif
        return Set(audioProcesses().filter { process in
            testPIDs.contains(process.pid) || (!isSpeechProcess(process) && process.pid != getpid()
                && prefixes.contains { belongs(process, to: $0, appPIDs: callPIDs) })
        }.map(\.object))
    }

    /// Taps the call apps' sound, again whenever their processes change.
    private func capture() {
        guard isRunning else { return }
        let processes = Self.callProcesses(prefixes: Preferences.shared.callApps.map(\.bundleID))
        guard processes != tapped else { return }
        teardown()
        tapped = processes
        guard !processes.isEmpty else { return }
        do {
            try build(processes)
            log("Call captions: listening to \(processes.count) call process(es).")
        } catch {
            log("Call captions: couldn't capture call sound: \(error)")
            teardown()
            tapped = processes // Don't retry the same set every few seconds.
            Announcer.say(String(localized: "Call captions couldn't hear the call. Allow VoiceOver Audio Split in System Settings, Privacy and Security, Screen and System Audio Recording."))
        }
    }

    private func build(_ processes: Set<AudioObjectID>) throws {
        let description = CATapDescription(stereoMixdownOfProcesses: Array(processes))
        description.name = "VOAudioSplit call captions"
        description.isPrivate = true
        // Only listening: what you hear doesn't change.
        description.muteBehavior = .unmuted
        try check(AudioHardwareCreateProcessTap(description, &tap), "create captions tap")
        guard let outputUID = readString(defaultOutputDevice(), kAudioDevicePropertyDeviceUID) else {
            throw SplitError("no output device")
        }
        let aggregateDescription: [String: Any] = [
            kAudioAggregateDeviceNameKey: "VOAudioSplit captions",
            kAudioAggregateDeviceUIDKey: "VOAudioSplit-captions-\(UUID().uuidString)",
            kAudioAggregateDeviceMainSubDeviceKey: outputUID,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceSubDeviceListKey: [[kAudioSubDeviceUIDKey: outputUID]],
            kAudioAggregateDeviceTapListKey: [[kAudioSubTapUIDKey: description.uuid.uuidString, kAudioSubTapDriftCompensationKey: true]],
        ]
        try check(AudioHardwareCreateAggregateDevice(aggregateDescription as CFDictionary, &aggregate), "create captions device")
        let rate = readValue(aggregate, kAudioDevicePropertyNominalSampleRate, default: Float64(48000))
        guard let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: rate, channels: 1, interleaved: false) else {
            throw SplitError("no audio format")
        }
        let current = currentRequest
        try check(AudioDeviceCreateIOProcIDWithBlock(&ioProc, aggregate, queue) { _, input, _, output, _ in
            // Leave the speakers alone: this device only listens.
            for buffer in UnsafeMutableAudioBufferListPointer(output) {
                if let data = buffer.mData { memset(data, 0, Int(buffer.mDataByteSize)) }
            }
            let inputs = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: input))
            guard let tapBuffer = inputs.last, let data = tapBuffer.mData,
                  let request = current.withLock({ $0 }) else { return }
            let channels = max(Int(tapBuffer.mNumberChannels), 1)
            let frames = Int(tapBuffer.mDataByteSize) / MemoryLayout<Float>.size / channels
            guard frames > 0, let pcm = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frames)),
                  let mono = pcm.floatChannelData?[0] else { return }
            let samples = data.assumingMemoryBound(to: Float.self)
            for frame in 0..<frames {
                var sum: Float = 0
                for channel in 0..<channels { sum += samples[frame * channels + channel] }
                mono[frame] = sum / Float(channels)
            }
            pcm.frameLength = AVAudioFrameCount(frames)
            request.append(pcm)
        }, "create captions IO proc")
        try check(AudioDeviceStart(aggregate, ioProc), "start captions")
    }

    private func teardown() {
        if aggregate != kAudioObjectUnknown {
            if let ioProc {
                AudioDeviceStop(aggregate, ioProc)
                AudioDeviceDestroyIOProcID(aggregate, ioProc)
            }
            AudioHardwareDestroyAggregateDevice(aggregate)
        }
        if tap != kAudioObjectUnknown { AudioHardwareDestroyProcessTap(tap) }
        ioProc = nil
        aggregate = AudioObjectID(kAudioObjectUnknown)
        tap = AudioObjectID(kAudioObjectUnknown)
        tapped = []
    }

    // MARK: Recognizing

    /// A new recognition task; a task runs for about a minute, so it's replaced before then.
    private func listen() {
        guard isRunning, let recognizer else { return }
        task?.cancel()
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.requiresOnDeviceRecognition = true
        request.shouldReportPartialResults = true
        request.addsPunctuation = true
        currentRequest.withLock { $0 = request }
        restartTimer?.invalidate()
        restartTimer = Timer.scheduledTimer(withTimeInterval: 50, repeats: false) { _ in
            MainActor.assumeIsolated { CallCaptions.shared.finishLine(); CallCaptions.shared.listen() }
        }
        task = recognizer.recognitionTask(with: request) { result, error in
            let text = result?.bestTranscription.formattedString
            let final = result?.isFinal == true
            DispatchQueue.main.async {
                let captions = CallCaptions.shared
                guard captions.isRunning, captions.currentRequest.withLock({ $0 }) === request else { return }
                if let text { captions.partial = text }
                if final || error != nil {
                    captions.finishLine()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        if captions.isRunning, captions.currentRequest.withLock({ $0 }) === request { captions.listen() }
                    }
                }
            }
        }
    }

    private func finishLine() {
        let line = partial.trimmingCharacters(in: .whitespacesAndNewlines)
        partial = ""
        guard !line.isEmpty else { return }
        lines = Array((lines + [line]).suffix(Self.maxLines))
    }

    // MARK: Showing

    private func showPanel() {
        guard panel == nil, let screen = NSScreen.main else { return }
        let width = screen.visibleFrame.width * 0.9
        // Above the VoiceOver captions strip, if that's on too.
        let frame = NSRect(x: screen.visibleFrame.midX - width / 2, y: screen.visibleFrame.minY + 280, width: width, height: 220)
        let panel = overlayWindow(frame)
        panel.contentView = NSHostingView(rootView: CallCaptionView())
        panel.orderFrontRegardless()
        self.panel = panel
    }
}

private struct CallCaptionView: View {
    @ObservedObject var captions = CallCaptions.shared
    @ObservedObject var preferences = Preferences.shared

    var body: some View {
        VStack {
            Spacer(minLength: 0)
            Text(captions.partial.isEmpty ? (captions.lines.last ?? String(localized: "Call captions are on")) : captions.partial)
                .font(.system(size: CGFloat(preferences.captionSize), weight: .semibold))
                .foregroundStyle(preferences.readingTheme.foreground)
                .lineLimit(3)
                .truncationMode(.head)
                .minimumScaleFactor(0.5)
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity)
                .background(preferences.readingTheme.background.opacity(0.92), in: RoundedRectangle(cornerRadius: 16))
                .accessibilityLabel(String(localized: "Call captions"))
                .accessibilityValue(captions.lines.last ?? "")
        }
    }
}
