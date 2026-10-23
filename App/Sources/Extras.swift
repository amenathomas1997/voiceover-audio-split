// Extras.swift — smaller tools NVDA users rely on:
//   * Beeps mode: while VoiceOver is silenced, a short beep each time it would
//     have spoken, so changes are noticed without speech
//   * Clipboard announcements: hear what was just copied
//   * Audio mouse: a tone that follows the pointer (pitch for up and down,
//     left and right in the ears), for drawing, maps and finding things
//   * Translate: on-device translation of the clipboard or the item under the
//     VoiceOver cursor (Apple's Translation framework, macOS 15 or later)

import AppKit
import AVFoundation
import SwiftUI
import Translation

// MARK: - Beeps mode

enum BeepMode {
    private static var timer: Timer?
    private static var wasSpeaking = false

    /// Runs only while VoiceOver is silenced and beeps are on.
    static func update(active: Bool) {
        if active && timer == nil {
            Mixer.speechActivity = false
            timer = Timer.scheduledTimer(withTimeInterval: 0.15, repeats: true) { _ in
                let speaking = Mixer.speechActivity
                Mixer.speechActivity = false
                if speaking && !wasSpeaking { Tones.play(.beep) }
                wasSpeaking = speaking
            }
        } else if !active {
            timer?.invalidate()
            timer = nil
        }
    }
}

// MARK: - Clipboard announcements

enum ClipboardWatcher {
    private static var timer: Timer?
    private static var lastCount = NSPasteboard.general.changeCount

    static func update(enabled: Bool) {
        if enabled && timer == nil {
            lastCount = NSPasteboard.general.changeCount
            timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { _ in
                let count = NSPasteboard.general.changeCount
                guard count != lastCount else { return }
                lastCount = count
                let description = Clipboard.describe()
                Announcer.say("Copied: " + (description.count > 120 ? String(description.prefix(120)) + "…" : description))
            }
        } else if !enabled {
            timer?.invalidate()
            timer = nil
        }
    }
}

// MARK: - Audio mouse

enum AudioMouse {
    private static let engine = AVAudioEngine()
    private static var monitors: [Any] = []
    // Read by the audio thread.
    nonisolated(unsafe) private static var frequency: Double = 440
    nonisolated(unsafe) private static var pan: Double = 0
    nonisolated(unsafe) private static var targetLevel: Double = 0
    nonisolated(unsafe) private static var level: Double = 0
    nonisolated(unsafe) private static var phase: Double = 0
    private static var fadeWork: DispatchWorkItem?

    static var isOn: Bool { !monitors.isEmpty }

    static func toggle() {
        isOn ? stop() : start()
    }

    private static func start() {
        let source = AVAudioSourceNode { _, _, frameCount, bufferList in
            let buffers = UnsafeMutableAudioBufferListPointer(bufferList)
            let step = 2 * Double.pi * frequency / 44100
            for frame in 0..<Int(frameCount) {
                // Glide the volume, so the tone fades in and out without clicks.
                level += (targetLevel - level) * 0.002
                let sample = sin(phase) * level
                phase += step
                if phase > 2 * Double.pi { phase -= 2 * Double.pi }
                let left = Float(sample * min(1, 1 - pan)), right = Float(sample * min(1, 1 + pan))
                if buffers.count >= 2 {
                    buffers[0].mData?.assumingMemoryBound(to: Float.self)[frame] = left
                    buffers[1].mData?.assumingMemoryBound(to: Float.self)[frame] = right
                }
            }
            return noErr
        }
        let format = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 2)!
        engine.attach(source)
        engine.connect(source, to: engine.mainMixerNode, format: format)
        do { try engine.start() } catch { return Announcer.say("Audio mouse couldn't start") }
        let handler: (NSEvent) -> Void = { _ in moved() }
        if let global = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged], handler: handler) {
            monitors.append(global)
        }
        if let local = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged], handler: {
            handler($0)
            return $0
        }) {
            monitors.append(local)
        }
        Announcer.say("Audio mouse on. Higher means nearer the top of the screen; left and right follow your ears.")
    }

    private static func stop() {
        monitors.forEach(NSEvent.removeMonitor)
        monitors.removeAll()
        engine.stop()
        for node in engine.attachedNodes where node is AVAudioSourceNode { engine.detach(node) }
        Announcer.say("Audio mouse off")
    }

    private static func moved() {
        let point = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(point) } ?? NSScreen.main
        guard let frame = screen?.frame else { return }
        let position = tone(x: (point.x - frame.minX) / frame.width, y: (point.y - frame.minY) / frame.height)
        frequency = position.frequency
        pan = position.pan
        targetLevel = 0.1
        // Fade out half a second after the pointer stops.
        fadeWork?.cancel()
        let work = DispatchWorkItem { targetLevel = 0 }
        fadeWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: work)
    }

    /// Bottom of the screen 200 Hz, top 1600 Hz (evenly spaced in pitch); left -1 to right 1.
    static func tone(x: Double, y: Double) -> (frequency: Double, pan: Double) {
        let clampedY = min(max(y, 0), 1), clampedX = min(max(x, 0), 1)
        return (200 * pow(8, clampedY), clampedX * 2 - 1)
    }
}

// MARK: - Translate

enum TranslateLanguages {
    /// Languages offered as targets, by code.
    static let all: [(code: String, name: String)] = [
        ("en", "English"), ("es", "Spanish"), ("fr", "French"), ("de", "German"), ("it", "Italian"),
        ("pt", "Portuguese"), ("nl", "Dutch"), ("pl", "Polish"), ("ru", "Russian"), ("uk", "Ukrainian"),
        ("tr", "Turkish"), ("ar", "Arabic"), ("hi", "Hindi"), ("zh-Hans", "Chinese, Simplified"),
        ("zh-Hant", "Chinese, Traditional"), ("ja", "Japanese"), ("ko", "Korean"), ("th", "Thai"),
        ("vi", "Vietnamese"), ("id", "Indonesian"),
    ]
}

final class TranslateModel: ObservableObject {
    static let shared = TranslateModel()

    @Published var source = ""
    @Published var result = ""
    /// Bumped to ask the view to run a translation.
    @Published var request = 0

    func loadClipboard() {
        source = NSPasteboard.general.string(forType: .string) ?? ""
        if source.isEmpty { Announcer.say("The clipboard has no text") }
    }

    func loadVoiceOverItem() {
        DispatchQueue.global().async {
            let text = VoiceOverText.itemUnderCursor() ?? ""
            DispatchQueue.main.async {
                self.source = text
                if text.isEmpty { Announcer.say("Nothing under the VoiceOver cursor to translate") } else { self.translate() }
            }
        }
    }

    func translate() {
        guard !source.isEmpty else { return }
        request += 1
    }
}

struct TranslateView: View {
    var body: some View {
        if #available(macOS 15, *) {
            TranslateContent()
        } else {
            Text("Translation needs macOS 15 or later.")
                .padding()
                .frame(width: 400, height: 120)
        }
    }
}

@available(macOS 15, *)
private struct TranslateContent: View {
    @ObservedObject var model = TranslateModel.shared
    @ObservedObject var preferences = Preferences.shared
    @State private var configuration: TranslationSession.Configuration?

    var body: some View {
        Form {
            Picker("Translate into", selection: $preferences.translateTarget) {
                ForEach(TranslateLanguages.all, id: \.code) { Text($0.name).tag($0.code) }
            }
            Section("Text to translate") {
                TextField("Text", text: $model.source, axis: .vertical)
                HStack {
                    Button("Use Clipboard") { model.loadClipboard() }
                    Button("Use Item Under VoiceOver Cursor") { model.loadVoiceOverItem() }
                    Button("Translate") { model.translate() }
                        .keyboardShortcut(.defaultAction)
                        .disabled(model.source.isEmpty)
                }
            }
            if !model.result.isEmpty {
                Section("Translation") {
                    Text(model.result).textSelection(.enabled)
                    Button("Copy Translation") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(model.result, forType: .string)
                        Announcer.say("Copied")
                    }
                }
            }
            Text("Translation runs on your Mac. The first time you use a language, your Mac may ask to download it.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
        .frame(width: 560, height: 480)
        .onChange(of: model.request) {
            // A new configuration (or invalidating the same one) runs the translation task again.
            let target = Locale.Language(identifier: preferences.translateTarget)
            if configuration?.target == target { configuration?.invalidate() }
            else { configuration = TranslationSession.Configuration(source: nil, target: target) }
        }
        .translationTask(configuration) { session in
            let text = model.source
            do {
                let response = try await session.translate(text)
                await MainActor.run {
                    model.result = response.targetText
                    Announcer.say(response.targetText)
                }
            } catch {
                await MainActor.run { Announcer.say("Couldn't translate that. The language may need to be downloaded first.") }
            }
        }
    }
}
