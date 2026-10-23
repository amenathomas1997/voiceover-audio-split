// FaceCheck.swift — checks camera framing before a video call, like JAWS Face in
// View: takes a few frames from the camera, finds faces with Vision, and says
// whether the face is centered, at a good distance and well lit.

import AVFoundation
import Vision

final class FaceCheck: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    static let shared = FaceCheck()

    private let queue = DispatchQueue(label: "VoiceOverAudioSplit.camera")
    private var session: AVCaptureSession?
    private var frames = 0
    private var completion: ((String) -> Void)?

    /// Runs one check and calls back on the main thread with what to say.
    func run(completion: @escaping (String) -> Void) {
        guard session == nil else { return }
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            start(completion)
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                DispatchQueue.main.async {
                    granted ? self.start(completion) : completion("Camera access was not allowed")
                }
            }
        default:
            completion("Camera access is off. Turn on VoiceOver Audio Split in System Settings, Privacy and Security, Camera.")
        }
    }

    private func start(_ completion: @escaping (String) -> Void) {
        guard let camera = CameraChoice.preferred(),
              let input = try? AVCaptureDeviceInput(device: camera) else {
            return completion("No camera found")
        }
        let session = AVCaptureSession()
        session.sessionPreset = .medium
        let output = AVCaptureVideoDataOutput()
        output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        output.setSampleBufferDelegate(self, queue: queue)
        guard session.canAddInput(input), session.canAddOutput(output) else { return completion("The camera is busy") }
        session.addInput(input)
        session.addOutput(output)
        self.session = session
        self.completion = completion
        frames = 0
        queue.async { session.startRunning() }
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        frames += 1
        // Skip the first second or so while the camera adjusts its exposure.
        guard frames == 30, let pixels = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let message = Self.describe(pixels)
        session?.stopRunning()
        session = nil
        let completion = self.completion
        self.completion = nil
        DispatchQueue.main.async { completion?(message) }
    }

    private static func describe(_ pixels: CVPixelBuffer) -> String {
        let request = VNDetectFaceRectanglesRequest()
        try? VNImageRequestHandler(cvPixelBuffer: pixels, options: [:]).perform([request])
        let faces = request.results ?? []
        let brightness = averageBrightness(pixels)
        let light = brightness < 0.25 ? "It's dark; add light in front of you." : brightness > 0.85 ? "It's very bright." : ""

        guard let face = faces.max(by: { $0.boundingBox.width < $1.boundingBox.width }) else {
            return "No face found. " + (light.isEmpty ? "Make sure you are in front of the camera." : light)
        }
        var advice: [String] = []
        let box = face.boundingBox // Normalised, origin at the bottom left of the camera image.
        // The camera image is not mirrored: a face on the image's left means you sit
        // to your right, so you should move to your left.
        if box.midX < 0.38 { advice.append("move a little to your left") }
        if box.midX > 0.62 { advice.append("move a little to your right") }
        if box.midY > 0.68 { advice.append("move down a little, or tilt the screen back") }
        if box.midY < 0.35 { advice.append("move up a little, or tilt the screen forward") }
        if box.width < 0.15 { advice.append("move closer") }
        if box.width > 0.5 { advice.append("move back a little") }

        var parts = [advice.isEmpty ? "Your face is centered and well framed." : "Face found. Please " + ListFormatter.localizedString(byJoining: advice) + "."]
        if faces.count > 1 { parts.append("\(faces.count) faces are in view.") }
        parts.append(light.isEmpty ? "Lighting is good." : light)
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
