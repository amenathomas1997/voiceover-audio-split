// CameraTools.swift — two camera aids familiar from phone apps:
//   * Color identifier: hold something up to the camera and hear its color
//   * Light detector: a tone that rises with the amount of light the camera sees
// Mac cameras adjust exposure and white balance automatically, which would hide
// real changes, so they are locked once the picture has settled, where the
// camera allows it. Results are a close guide, not a measurement.

import AVFoundation

/// Delivers camera frames to a handler until stopped.
final class CameraFeed: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    private let queue = DispatchQueue(label: "VoiceOverAudioSplit.camera-feed")
    private var session: AVCaptureSession?
    private var device: AVCaptureDevice?
    private var frames = 0
    private var handler: ((CVPixelBuffer) -> Void)?

    var isRunning: Bool { session != nil }

    /// Calls `handler` on a background queue with each frame, after the camera has settled.
    func start(_ handler: @escaping (CVPixelBuffer) -> Void, failed: @escaping (String) -> Void) {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: break
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                DispatchQueue.main.async {
                    granted ? self.start(handler, failed: failed) : failed("Camera access was not allowed")
                }
            }
            return
        default:
            return failed("Camera access is off. Turn on VoiceOver Audio Split in System Settings, Privacy and Security, Camera.")
        }
        guard let camera = AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(device: camera) else { return failed("No camera found") }
        let session = AVCaptureSession()
        session.sessionPreset = .medium
        let output = AVCaptureVideoDataOutput()
        output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        output.alwaysDiscardsLateVideoFrames = true
        output.setSampleBufferDelegate(self, queue: queue)
        guard session.canAddInput(input), session.canAddOutput(output) else { return failed("The camera is busy") }
        session.addInput(input)
        session.addOutput(output)
        self.session = session
        self.device = camera
        self.handler = handler
        frames = 0
        queue.async { session.startRunning() }
    }

    func stop() {
        session?.stopRunning()
        session = nil
        handler = nil
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        frames += 1
        // Let the camera settle for about a second, then hold exposure and color steady.
        if frames == 30 { lockAdjustments() }
        guard frames > 30, let pixels = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        handler?(pixels)
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
}

enum ColorIdentifier {
    private static let feed = CameraFeed()

    static func identify() {
        guard !feed.isRunning else { return }
        Tones.play(.status)
        Announcer.say("Hold the item close to the camera")
        var samples = 0
        feed.start({ pixels in
            samples += 1
            // Use the fifth settled frame, so the item is held still.
            guard samples == 5 else { return }
            let color = CameraFeed.averageColor(pixels)
            DispatchQueue.main.async {
                feed.stop()
                Announcer.say(ColorNames.name(red: color.r, green: color.g, blue: color.b))
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
        Announcer.say("Light detector on. The tone rises with more light.")
        feed.start({ pixels in
            let color = CameraFeed.averageColor(pixels, centerFraction: 0.8)
            frequency = tone(forBrightness: (color.r + color.g + color.b) / 3)
        }, failed: { message in
            stop(announce: false)
            Announcer.say(message)
        })
        // Start the tone after the announcement, so it doesn't talk over it.
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            guard isRunning, !engine.isRunning else { return }
            try? engine.start()
        }
        // Switch off after two minutes, in case it's forgotten.
        let work = DispatchWorkItem { if isRunning { stop(announce: true) } }
        stopWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 120, execute: work)
    }

    private static func stop(announce: Bool) {
        stopWork?.cancel()
        feed.stop()
        engine.stop()
        for node in engine.attachedNodes where node is AVAudioSourceNode { engine.detach(node) }
        if announce { Announcer.say("Light detector off") }
    }

    /// Dark is a low tone (220 Hz), bright a high one (1760 Hz), evenly spaced in pitch.
    static func tone(forBrightness brightness: Double) -> Double {
        220 * pow(8, min(max(brightness, 0), 1))
    }
}
