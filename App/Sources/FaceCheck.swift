// FaceCheck.swift — checks camera framing before a video call, like JAWS Face in
// View: takes a few frames from the camera, finds faces with Vision, and says
// whether the face is centered, at a good distance and well lit.

import AVFoundation
import Vision

final class FaceCheck: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    static let shared = FaceCheck()

    private let queue = DispatchQueue(label: "VoiceOverAudioSplit.camera")
    /// Main thread: set while a check is under way.
    private var session: AVCaptureSession?
    /// Camera queue: the session that is running, and its frame count.
    private var running: AVCaptureSession?
    private var frames = 0
    private var completion: ((String) -> Void)?

    /// Runs one check and calls back on the main thread with what to say.
    func run(completion: @escaping (String) -> Void) {
        guard session == nil, !asking else { return }
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            start(completion)
        case .notDetermined:
            asking = true
            AVCaptureDevice.requestAccess(for: .video) { granted in
                DispatchQueue.main.async {
                    self.asking = false
                    granted ? self.start(completion) : completion(String(localized: "Camera access was not allowed"))
                }
            }
        default:
            completion(String(localized: "Camera access is off. Turn on VoiceOver Audio Split in System Settings, Privacy and Security, Camera."))
        }
    }

    /// Waiting for the camera permission answer.
    private var asking = false

    private func start(_ completion: @escaping (String) -> Void) {
        guard session == nil else { return }
        guard let camera = CameraChoice.preferred(),
              let input = try? AVCaptureDeviceInput(device: camera) else {
            return completion(String(localized: "No camera found"))
        }
        let session = AVCaptureSession()
        session.sessionPreset = .medium
        let output = AVCaptureVideoDataOutput()
        output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        output.setSampleBufferDelegate(self, queue: queue)
        guard session.canAddInput(input), session.canAddOutput(output) else { return completion(String(localized: "The camera is busy")) }
        session.addInput(input)
        session.addOutput(output)
        self.session = session
        queue.async {
            self.running = session
            self.completion = completion
            self.frames = 0
            session.startRunning()
        }
        // If the camera never sends a picture, say so instead of waiting forever.
        DispatchQueue.main.asyncAfter(deadline: .now() + 10) { [weak self] in
            guard let self, self.session === session else { return }
            self.queue.async {
                guard let running = self.running, running === session else { return }
                running.stopRunning()
                self.running = nil
                let completion = self.completion
                self.completion = nil
                DispatchQueue.main.async {
                    self.session = nil
                    completion?(String(localized: "The camera isn't sending a picture. Check that it's connected and not in use, then try again."))
                }
            }
        }
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        frames += 1
        // Skip the first second or so while the camera adjusts its exposure.
        guard frames == 30, let pixels = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let message = Self.describe(pixels)
        running?.stopRunning()
        running = nil
        let completion = self.completion
        self.completion = nil
        DispatchQueue.main.async {
            self.session = nil
            completion?(message)
        }
    }

    private static func describe(_ pixels: CVPixelBuffer) -> String {
        let request = VNDetectFaceRectanglesRequest()
        try? VNImageRequestHandler(cvPixelBuffer: pixels, options: [:]).perform([request])
        let faces = request.results ?? []
        let brightness = averageBrightness(pixels)
        let light = brightness < 0.25 ? String(localized: "It's dark; add light in front of you.") : brightness > 0.85 ? String(localized: "It's very bright.") : ""

        guard let face = faces.max(by: { $0.boundingBox.width < $1.boundingBox.width }) else {
            return light.isEmpty ? String(localized: "No face found. Make sure you are in front of the camera.") : String(localized: "No face found. \(light)")
        }
        var advice: [String] = []
        let box = face.boundingBox // Normalised, origin at the bottom left of the camera image.
        // The camera image is not mirrored: a face on the image's left means you sit
        // to your right, so you should move to your left.
        if box.midX < 0.38 { advice.append(String(localized: "move a little to your left")) }
        if box.midX > 0.62 { advice.append(String(localized: "move a little to your right")) }
        if box.midY > 0.68 { advice.append(String(localized: "move down a little, or tilt the screen back")) }
        if box.midY < 0.35 { advice.append(String(localized: "move up a little, or tilt the screen forward")) }
        if box.width < 0.15 { advice.append(String(localized: "move closer")) }
        if box.width > 0.5 { advice.append(String(localized: "move back a little")) }

        var parts = [advice.isEmpty ? String(localized: "Your face is centered and well framed.") : String(localized: "Face found. Please \(ListFormatter.localizedString(byJoining: advice)).")]
        if faces.count > 1 { parts.append(String(localized: "\(faces.count) faces are in view.")) }
        parts.append(light.isEmpty ? String(localized: "Lighting is good.") : light)
        return parts.joined(separator: " ")
    }

    /// Average brightness from 0 to 1, sampled across the image.
    private static func averageBrightness(_ pixels: CVPixelBuffer) -> Double {
        CVPixelBufferLockBaseAddress(pixels, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixels, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(pixels) else { return 0.5 }
        let width = CVPixelBufferGetWidth(pixels), height = CVPixelBufferGetHeight(pixels)
        let rowBytes = CVPixelBufferGetBytesPerRow(pixels)
        let data = base.assumingMemoryBound(to: UInt8.self)
        var total = 0.0
        var count = 0.0
        for y in stride(from: 0, to: height, by: 8) {
            for x in stride(from: 0, to: width, by: 8) {
                let p = data + y * rowBytes + x * 4 // BGRA
                total += 0.114 * Double(p[0]) + 0.587 * Double(p[1]) + 0.299 * Double(p[2])
                count += 1
            }
        }
        return count > 0 ? total / count / 255 : 0.5
    }
}
