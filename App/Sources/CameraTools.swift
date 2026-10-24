// CameraTools.swift — two camera aids familiar from phone apps:
//   * Color identifier: hold something up to the camera and hear its color
//   * Light detector: a tone that rises with the amount of light the camera sees
// Mac cameras adjust exposure and white balance automatically, which would hide
// real changes, so they are locked once the picture has settled, where the
// camera allows it. Results are a close guide, not a measurement.

import AVFoundation

/// Which camera to use: an iPhone through Continuity Camera when one is nearby
/// (much better for reading mail and labels), unless turned off in Settings.
enum CameraChoice {
    static func preferred() -> AVCaptureDevice? {
        let devices = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.continuityCamera, .builtInWideAngleCamera, .external],
            mediaType: .video, position: .unspecified).devices
        if Preferences.shared.preferIPhoneCamera,
           let phone = devices.first(where: { $0.deviceType == .continuityCamera }) {
            return phone
        }
        return devices.first { $0.deviceType != .continuityCamera } ?? devices.first
    }
}

/// Delivers camera frames to a handler until stopped. Start, stop and the frame
/// handler all go through the camera's own queue, in order, so a quick stop after a
/// start always leaves the camera off.
final class CameraFeed: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    private let queue = DispatchQueue(label: "VoiceOverAudioSplit.camera-feed")
    // Main thread only.
    private var session: AVCaptureSession?
    /// Waiting for the camera permission answer.
    private var asking = false
    private var noPicture: DispatchWorkItem?
    // Camera queue only.
    private var device: AVCaptureDevice?
    private var frames = 0
    private var handler: ((CVPixelBuffer) -> Void)?
    private var firstFrame: (() -> Void)?

    /// Also true while the permission question is open, so a second press doesn't start twice.
    var isRunning: Bool { session != nil || asking }

    /// Calls `handler` on a background queue with each frame, after the camera has settled.
    /// `started` runs on the main thread when the first picture arrives. If none comes
    /// within 10 seconds, the feed stops and `failed` says so.
    func start(preset: AVCaptureSession.Preset = .medium, _ handler: @escaping (CVPixelBuffer) -> Void,
               started: (() -> Void)? = nil, failed: @escaping (String) -> Void) {
        guard !isRunning else { return }
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: break
        case .notDetermined:
            asking = true
            AVCaptureDevice.requestAccess(for: .video) { granted in
                DispatchQueue.main.async {
                    // Stopped while the question was open: don't start afterwards.
                    guard self.asking else { return }
                    self.asking = false
                    granted ? self.start(preset: preset, handler, started: started, failed: failed)
                            : failed(String(localized: "Camera access was not allowed"))
                }
            }
            return
        default:
            return failed(String(localized: "Camera access is off. Turn on VoiceOver Audio Split in System Settings, Privacy and Security, Camera."))
        }
        guard let camera = CameraChoice.preferred(),
              let input = try? AVCaptureDeviceInput(device: camera) else { return failed(String(localized: "No camera found")) }
        let session = AVCaptureSession()
        session.sessionPreset = session.canSetSessionPreset(preset) ? preset : .medium
        let output = AVCaptureVideoDataOutput()
        output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        output.alwaysDiscardsLateVideoFrames = true
        output.setSampleBufferDelegate(self, queue: queue)
        guard session.canAddInput(input), session.canAddOutput(output) else { return failed(String(localized: "The camera is busy")) }
        session.addInput(input)
        session.addOutput(output)
        self.session = session
        let watchdog = DispatchWorkItem { [weak self] in
            guard let self, self.session === session else { return }
            self.stop()
            failed(String(localized: "The camera isn't sending a picture. Check that it's connected and not in use, then try again."))
        }
        noPicture = watchdog
        DispatchQueue.main.asyncAfter(deadline: .now() + 10, execute: watchdog)
        queue.async {
            self.frames = 0
            self.device = camera
            self.handler = handler
            self.firstFrame = {
                watchdog.cancel()
                started?()
            }
            session.startRunning()
        }
    }

    func stop() {
        asking = false
        noPicture?.cancel()
        guard let session else { return }
        self.session = nil
        queue.async {
            self.handler = nil
            self.firstFrame = nil
            self.unlockAdjustments()
            session.stopRunning()
        }
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        frames += 1
        if frames == 1, let firstFrame {
            self.firstFrame = nil
            DispatchQueue.main.async(execute: firstFrame)
        }
        // Let the camera settle for about a second, then hold exposure and color steady.
        if frames == 30 { lockAdjustments() }
        guard frames > 30, let pixels = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        handler?(pixels)
    }

    /// Back to automatic exposure and color, so the next camera tool gets a normal picture.
    private func unlockAdjustments() {
        guard let device, (try? device.lockForConfiguration()) != nil else { return }
        if device.isExposureModeSupported(.continuousAutoExposure) { device.exposureMode = .continuousAutoExposure }
        if device.isWhiteBalanceModeSupported(.continuousAutoWhiteBalance) { device.whiteBalanceMode = .continuousAutoWhiteBalance }
        device.unlockForConfiguration()
        self.device = nil
    }

    private func lockAdjustments() {
        guard let device, (try? device.lockForConfiguration()) != nil else { return }
        if device.isExposureModeSupported(.locked) { device.exposureMode = .locked }
        if device.isWhiteBalanceModeSupported(.locked) { device.whiteBalanceMode = .locked }
        device.unlockForConfiguration()
    }

    /// Average red, green and blue (0 to 1) of the middle of the picture.
    static func averageColor(_ pixels: CVPixelBuffer, centerFraction: Double = 0.3) -> (r: Double, g: Double, b: Double) {
        CVPixelBufferLockBaseAddress(pixels, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixels, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(pixels) else { return (0, 0, 0) }
        let width = CVPixelBufferGetWidth(pixels), height = CVPixelBufferGetHeight(pixels)
        let rowBytes = CVPixelBufferGetBytesPerRow(pixels)
        let data = base.assumingMemoryBound(to: UInt8.self)
        let x0 = Int(Double(width) * (1 - centerFraction) / 2), x1 = width - x0
        let y0 = Int(Double(height) * (1 - centerFraction) / 2), y1 = height - y0
        var r = 0.0, g = 0.0, b = 0.0, count = 0.0
        for y in stride(from: y0, to: y1, by: 4) {
            for x in stride(from: x0, to: x1, by: 4) {
                let p = data + y * rowBytes + x * 4 // BGRA
                b += Double(p[0]); g += Double(p[1]); r += Double(p[2])
                count += 1
            }
        }
        guard count > 0 else { return (0, 0, 0) }
        return (r / count / 255, g / count / 255, b / count / 255)
    }
}

// MARK: - Color identifier

enum ColorNames {
    /// A plain-language name for a color, such as "dark blue" or "light gray".
    static func name(red: Double, green: Double, blue: Double) -> String {
        let maxValue = max(red, green, blue), minValue = min(red, green, blue)
        let brightness = maxValue
        let saturation = maxValue == 0 ? 0 : (maxValue - minValue) / maxValue
        var hue = 0.0
        if maxValue != minValue {
            let delta = maxValue - minValue
            if maxValue == red { hue = (green - blue) / delta }
            else if maxValue == green { hue = 2 + (blue - red) / delta }
            else { hue = 4 + (red - green) / delta }
            hue = (hue * 60).truncatingRemainder(dividingBy: 360)
            if hue < 0 { hue += 360 }
        }

        if brightness < 0.15 { return "black" }
        if saturation < 0.15 {
            switch brightness {
            case 0.85...: return "white"
            case 0.6..<0.85: return "light gray"
            case 0.35..<0.6: return "gray"
            default: return "dark gray"
            }
        }
        var base: String
        switch hue {
        case 0..<15, 340...360: base = "red"
        case 15..<40: base = brightness < 0.6 ? "brown" : "orange"
        case 40..<68: base = brightness < 0.55 ? "olive" : "yellow"
        case 68..<165: base = "green"
        case 165..<195: base = "teal"
        case 195..<250: base = brightness < 0.45 ? "navy blue" : "blue"
        case 250..<290: base = "purple"
        default: base = "pink"
        }
        if base == "red" && brightness > 0.75 && saturation < 0.5 { base = "pink" }
        if brightness < 0.35 && base != "navy blue" && base != "brown" && base != "olive" { return "dark " + base }
        if brightness > 0.8 && saturation < 0.45 { return "light " + base }
        return base
    }

    /// The English name from `name`, in the user's language.
    static func spoken(_ english: String) -> String {
        if english.hasPrefix("dark "), english != "dark gray" {
            let color = base(String(english.dropFirst(5)))
            return String(localized: "dark \(color)", comment: "A color, such as dark blue")
        }
        if english.hasPrefix("light "), english != "light gray" {
            let color = base(String(english.dropFirst(6)))
            return String(localized: "light \(color)", comment: "A color, such as light pink")
        }
        return base(english)
    }

    private static func base(_ english: String) -> String {
        switch english {
        case "black": String(localized: "black")
        case "white": String(localized: "white")
        case "gray": String(localized: "gray")
        case "light gray": String(localized: "light gray")
        case "dark gray": String(localized: "dark gray")
        case "red": String(localized: "red")
        case "brown": String(localized: "brown")
        case "orange": String(localized: "orange")
        case "olive": String(localized: "olive")
        case "yellow": String(localized: "yellow")
        case "green": String(localized: "green")
        case "teal": String(localized: "teal")
        case "navy blue": String(localized: "navy blue")
        case "blue": String(localized: "blue")
        case "purple": String(localized: "purple")
        case "pink": String(localized: "pink")
        default: english
        }
    }
}

enum ColorIdentifier {
    private static let feed = CameraFeed()

    static func identify() {
        guard !feed.isRunning else { return }
        Tones.play(.status)
        Announcer.say(String(localized: "Hold the item close to the camera"))
        var samples = 0
        feed.start({ pixels in
            samples += 1
            // Use the fifth settled frame, so the item is held still.
            guard samples == 5 else { return }
            let color = CameraFeed.averageColor(pixels)
            DispatchQueue.main.async {
                feed.stop()
                Announcer.say(ColorNames.spoken(ColorNames.name(red: color.r, green: color.g, blue: color.b)))
            }
        }, failed: { Announcer.say($0) })
    }
}

// MARK: - Light detector

enum LightDetector {
    private static let feed = CameraFeed()
    private static let engine = AVAudioEngine()
    nonisolated(unsafe) private static var frequency: Double = 220
    nonisolated(unsafe) private static var phase: Double = 0
    private static var stopWork: DispatchWorkItem?
    /// Counts runs, so a delayed start from an earlier one is ignored.
    private static var run = 0

    static var isRunning: Bool { feed.isRunning }

    static func toggle() {
        isRunning ? stop(announce: true) : start()
    }

    private static func start() {
        let source = AVAudioSourceNode { _, _, frameCount, bufferList in
            let buffers = UnsafeMutableAudioBufferListPointer(bufferList)
            let step = 2 * Double.pi * frequency / 44100
            for frame in 0..<Int(frameCount) {
                let sample = Float(sin(phase)) * 0.12
                phase += step
                if phase > 2 * Double.pi { phase -= 2 * Double.pi }
                for buffer in buffers { buffer.mData?.assumingMemoryBound(to: Float.self)[frame] = sample }
            }
            return noErr
        }
        let format = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 1)!
        engine.attach(source)
        engine.connect(source, to: engine.mainMixerNode, format: format)
        Announcer.say(String(localized: "Light detector on. The tone rises with more light."))
        feed.start({ pixels in
            let color = CameraFeed.averageColor(pixels, centerFraction: 0.8)
            frequency = tone(forBrightness: (color.r + color.g + color.b) / 3)
        }, started: {
            // Start the tone once pictures arrive (after any permission question),
            // and after the announcement, so it doesn't talk over it.
            let thisRun = run
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                guard run == thisRun, isRunning, !engine.isRunning else { return }
                try? engine.start()
            }
        }, failed: { message in
            stop(announce: false)
            Announcer.say(message)
        })
        // Switch off after two minutes, in case it's forgotten.
        let work = DispatchWorkItem { if isRunning { stop(announce: true) } }
        stopWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 120, execute: work)
    }

    private static func stop(announce: Bool) {
        run += 1
        stopWork?.cancel()
        feed.stop()
        engine.stop()
        for node in engine.attachedNodes where node is AVAudioSourceNode { engine.detach(node) }
        if announce { Announcer.say(String(localized: "Light detector off")) }
    }

    /// Dark is a low tone (220 Hz), bright a high one (1760 Hz), evenly spaced in pitch.
    static func tone(forBrightness brightness: Double) -> Double {
        220 * pow(8, min(max(brightness, 0), 1))
    }
}
