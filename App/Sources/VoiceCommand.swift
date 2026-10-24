// VoiceCommand.swift — say "Launch VoiceOver training" anywhere on the Mac to open
// VoiceOver Lessons. Off until turned on in Settings or the setup guide.
// Listening is done on the Mac (on-device speech recognition): nothing is recorded,
// saved or sent. It uses the Mac's built-in microphone, because using AirPods' or
// another Bluetooth headset's microphone would drop their sound to low quality; with
// only a Bluetooth microphone, it waits until another one is available.

import AppKit
import AVFoundation
import CoreAudio
import Speech

final class VoiceCommand {
    static let shared = VoiceCommand()

    private var engine: AVAudioEngine?
    private var recognizer: SFSpeechRecognizer?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var restartTimer: Timer?
    private var lastHeard = Date.distantPast
    private(set) var isListening = false
    private var wanted = false

    /// Starts or stops listening to match the setting.
    func update(enabled: Bool) {
        guard enabled != wanted else { return }
        wanted = enabled
        enabled ? requestThenStart() : stop()
    }

    private func requestThenStart() {
        SFSpeechRecognizer.requestAuthorization { status in
            DispatchQueue.main.async {
                guard self.wanted else { return }
                guard status == .authorized else {
                    return Announcer.say(String(localized: "Voice command needs Speech Recognition. Allow VoiceOver Audio Split in System Settings, Privacy and Security, Speech Recognition."))
                }
                AVCaptureDevice.requestAccess(for: .audio) { granted in
                    DispatchQueue.main.async {
                        guard self.wanted else { return }
                        granted ? self.start() : Announcer.say(String(localized: "Voice command needs the microphone. Allow VoiceOver Audio Split in System Settings, Privacy and Security, Microphone."))
                    }
                }
            }
        }
    }

    private func start() {
        guard !isListening else { return }
        // On-device only: the language of the Mac if it can, otherwise English.
        let candidates = [SFSpeechRecognizer(locale: Locale.current), SFSpeechRecognizer(locale: Locale(identifier: "en-US"))]
        guard let recognizer = candidates.compactMap({ $0 }).first(where: \.supportsOnDeviceRecognition) else {
            return Announcer.say(String(localized: "Voice command isn't available: this Mac can't recognize speech on the device."))
        }
        guard let microphone = Self.builtInMicrophone() else {
            log("Voice command: no built-in microphone; not listening, to keep Bluetooth headsets at full quality.")
            return Announcer.say(String(localized: "Voice command waits for a built-in or wired microphone, so your Bluetooth headphones keep their full sound quality."))
        }
        let engine = AVAudioEngine()
        var device = microphone
        if let unit = engine.inputNode.audioUnit {
            AudioUnitSetProperty(unit, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0,
                                 &device, UInt32(MemoryLayout<AudioDeviceID>.size))
        }
        let format = engine.inputNode.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else { return }
        engine.inputNode.installTap(onBus: 0, bufferSize: 2048, format: format) { [weak self] buffer, _ in
            self?.request?.append(buffer)
        }
        do {
            try engine.start()
        } catch {
            engine.inputNode.removeTap(onBus: 0)
            return log("Voice command: microphone couldn't start: \(error)")
        }
        self.engine = engine
        self.recognizer = recognizer
        isListening = true
        log("Voice command: listening on the device.")
        listen()
        // A recognition task can only run for a minute or so; start a fresh one regularly.
        restartTimer = Timer.scheduledTimer(withTimeInterval: 50, repeats: true) { [weak self] _ in self?.listen() }
    }

    /// A new recognition task, replacing the last one.
    private func listen() {
        guard isListening, let recognizer else { return }
        task?.cancel()
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.requiresOnDeviceRecognition = true
        request.shouldReportPartialResults = true
        request.taskHint = .search
        self.request = request
        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let self else { return }
            if let text = result?.bestTranscription.formattedString, Self.isLaunchCommand(text) {
                DispatchQueue.main.async { self.heard() }
            }
            if error != nil || result?.isFinal == true {
                // Ended (silence, a limit or an error): carry on listening.
                // (A task replaced by a newer one also ends here; leave that one be.)
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) { if self.isListening && self.request === request { self.listen() } }
            }
        }
    }

    private func heard() {
        // One phrase is heard several times as it's recognized; act once.
        guard Date().timeIntervalSince(lastHeard) > 5 else { return }
        lastHeard = Date()
        Tones.play(.status)
        NSApp.activate()
        (NSApp.delegate as? AppDelegate)?.showLessons()
        // Start afresh, so the same words aren't heard again.
        listen()
    }

    func stop() {
        restartTimer?.invalidate()
        restartTimer = nil
        task?.cancel()
        task = nil
        request = nil
        engine?.inputNode.removeTap(onBus: 0)
        engine?.stop()
        engine = nil
        isListening = false
    }

    /// "Launch VoiceOver training", or the same in the Mac's language. VoiceOver plus a
    /// word for training or lessons is enough, so it still works if a word is misheard.
    static func isLaunchCommand(_ text: String) -> Bool {
        let words = text.lowercased().folding(options: .diacriticInsensitive, locale: nil)
            .replacingOccurrences(of: "-", with: " ")
        let squeezed = words.replacingOccurrences(of: " ", with: "")
        let saysVoiceOver = squeezed.contains("voiceover")
        let training = ["training", "trainer", "lesson", "lessons", "tutorial",
                        "entrenamiento", "lecciones", "formation", "lecons", "entrainement", "schulung", "lektionen", "ubung"]
        return saysVoiceOver && training.contains { words.contains($0) }
    }

    /// The Mac's built-in (or a wired USB) microphone, but never a Bluetooth one.
    static func builtInMicrophone() -> AudioDeviceID? {
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDevices, mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size) == noErr else { return nil }
        var devices = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &devices) == noErr else { return nil }
        let inputs = devices.filter { channelCount($0, scope: kAudioObjectPropertyScopeInput) > 0 }
        func transport(_ device: AudioDeviceID) -> UInt32 { readValue(device, kAudioDevicePropertyTransportType, default: UInt32(0)) }
        return inputs.first { transport($0) == kAudioDeviceTransportTypeBuiltIn }
            ?? inputs.first { transport($0) == kAudioDeviceTransportTypeUSB }
    }
}
