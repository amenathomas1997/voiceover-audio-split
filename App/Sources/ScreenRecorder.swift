// ScreenRecorder.swift — a one-key screen recorder, for demos and for showing how to do
// something with VoiceOver: start, and later stop, with the same command. It records the
// main screen with the Mac's sound (VoiceOver included) and, if chosen, your microphone,
// into a movie in Movies, VoiceOver Audio Split Recordings. No window to open, nothing to
// set up. Recording uses screen recording permission (macOS 15 or later), and the
// microphone's if it's included. Nothing is sent anywhere.

import AppKit
import ScreenCaptureKit

@MainActor
final class ScreenRecorder: ObservableObject {
    static let shared = ScreenRecorder()

    @Published private(set) var isRecording = false
    private var session: AnyObject?
    private var starting = false

    /// Movies, VoiceOver Audio Split Recordings, in the user's real home folder (the
    /// app's own container has a Movies folder of its own, which nobody would find).
    nonisolated static var folder: URL {
        let home = getpwuid(getuid()).flatMap { String(validatingCString: $0.pointee.pw_dir) } ?? NSHomeDirectory()
        return URL(fileURLWithPath: home).appendingPathComponent("Movies", isDirectory: true)
            .appendingPathComponent("VoiceOver Audio Split Recordings", isDirectory: true)
    }

    /// "Recording 2026-10-28 at 09.15.32.mov".
    nonisolated static func fileName(at date: Date) -> String {
        let format = DateFormatter()
        format.locale = Locale(identifier: "en_US_POSIX")
        format.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        return "Recording \(format.string(from: date)).mov"
    }

    func toggle() { isRecording ? stop() : start() }

    func start() {
        guard !isRecording, !starting else { return }
        guard #available(macOS 15.0, *) else {
            return Announcer.say(String(localized: "Recording the screen needs macOS 15 or later."))
        }
        starting = true
        Task {
            defer { starting = false }
            do {
                try FileManager.default.createDirectory(at: Self.folder, withIntermediateDirectories: true)
                let url = Self.folder.appendingPathComponent(Self.fileName(at: Date()))
                let recording = try await RecordingSession.start(to: url, microphone: Preferences.shared.recordMicrophone) { saved in
                    Task { @MainActor in ScreenRecorder.shared.finished(saved) }
                }
                session = recording
                isRecording = true
                log("Screen recording started.")
                Tones.play(.status)
                Announcer.say(String(localized: "Recording. Use the same command again to stop."))
            } catch let failure as RecordingFailure {
                log("Screen recording couldn't start: \(failure.message)")
                Announcer.say(failure.message)
            } catch {
                log("Screen recording couldn't start: \(error.localizedDescription)")
                Announcer.say(String(localized: "Recording couldn't start. Allow VoiceOver Audio Split in System Settings, Privacy and Security, Screen and System Audio Recording, then try again."))
            }
        }
    }

    func stop() {
        guard isRecording else { return }
        if #available(macOS 15.0, *), let recording = session as? RecordingSession {
            Task { await recording.stop() }
        }
    }

    func openFolder() {
        try? FileManager.default.createDirectory(at: Self.folder, withIntermediateDirectories: true)
        NSWorkspace.shared.open(Self.folder)
    }

    private func finished(_ saved: Result<URL, Error>) {
        session = nil
        isRecording = false
        switch saved {
        case .success(let url):
            log("Screen recording saved.")
            Tones.play(.device)
            Announcer.say(String(localized: "Recording saved as \(url.deletingPathExtension().lastPathComponent), in Movies, VoiceOver Audio Split Recordings."))
        case .failure(let error):
            log("Screen recording failed: \(error.localizedDescription)")
            Announcer.say(String(localized: "The recording stopped with a problem, and may not have been saved."))
        }
    }
}

struct RecordingFailure: Error { let message: String }

@available(macOS 15.0, *)
private final class RecordingSession: NSObject, SCStreamDelegate, SCRecordingOutputDelegate {
    private var stream: SCStream?
    private var output: SCRecordingOutput?
    private let url: URL
    private let done: (Result<URL, Error>) -> Void
    private var reported = false

    private init(url: URL, done: @escaping (Result<URL, Error>) -> Void) {
        self.url = url
        self.done = done
    }

    static func start(to url: URL, microphone: Bool, done: @escaping (Result<URL, Error>) -> Void) async throws -> RecordingSession {
        let content: SCShareableContent
        do {
            content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        } catch {
            throw RecordingFailure(message: String(localized: "Recording the screen needs permission. Allow VoiceOver Audio Split in System Settings, Privacy and Security, Screen and System Audio Recording."))
        }
        guard let display = content.displays.first(where: { $0.displayID == CGMainDisplayID() }) ?? content.displays.first else {
            throw RecordingFailure(message: String(localized: "No screen found."))
        }
        let scale = await MainActor.run {
            NSScreen.screens.first { ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == display.displayID }?
                .backingScaleFactor ?? 2
        }
        let configuration = SCStreamConfiguration()
        configuration.width = Int(CGFloat(display.width) * scale)
        configuration.height = Int(CGFloat(display.height) * scale)
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: 30)
        configuration.showsCursor = true
        configuration.capturesAudio = true
        configuration.sampleRate = 48000
        configuration.channelCount = 2
        configuration.captureMicrophone = microphone
        let filter = SCContentFilter(display: display, excludingApplications: [], exceptingWindows: [])
        let recordingConfiguration = SCRecordingOutputConfiguration()
        recordingConfiguration.outputURL = url
        recordingConfiguration.outputFileType = .mov
        recordingConfiguration.videoCodecType = .h264

        // The session is the stream's and the output's delegate, and keeps both alive.
        let session = RecordingSession(url: url, done: done)
        let stream = SCStream(filter: filter, configuration: configuration, delegate: session)
        let output = SCRecordingOutput(configuration: recordingConfiguration, delegate: session)
        session.stream = stream
        session.output = output
        try stream.addRecordingOutput(output)
        try await stream.startCapture()
        return session
    }

    func stop() async {
        do {
            try await stream?.stopCapture()
        } catch {
            report(.failure(error))
        }
    }

    private func report(_ result: Result<URL, Error>) {
        guard !reported else { return }
        reported = true
        done(result)
    }

    func recordingOutputDidFinishRecording(_ recordingOutput: SCRecordingOutput) { report(.success(url)) }
    func recordingOutput(_ recordingOutput: SCRecordingOutput, didFailWithError error: any Error) { report(.failure(error)) }
    func stream(_ stream: SCStream, didStopWithError error: any Error) { report(.failure(error)) }
}
