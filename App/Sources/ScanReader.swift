// ScanReader.swift — Scan and Read, like SuperNova's camera reading: hold a
// letter, label or menu up to the camera and hear its text, with spoken guidance
// to get the page into view. Also reads the text in image files and PDFs
// (including scanned ones). Text recognition runs on the Mac with Apple's
// Vision framework; nothing is sent anywhere.

import AVFoundation
import PDFKit
import SwiftUI
import UniformTypeIdentifiers
import VideoToolbox
import Vision

enum TextRecognition {
    /// Recognized lines of text, top to bottom, with their boxes (normalised, origin bottom left).
    static func lines(in image: CGImage) -> [(text: String, box: CGRect)] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        try? VNImageRequestHandler(cgImage: image, options: [:]).perform([request])
        return (request.results ?? [])
            .compactMap { observation in observation.topCandidates(1).first.map { ($0.string, observation.boundingBox) } }
            .sorted { $0.box.midY > $1.box.midY }
    }

    static func text(in image: CGImage) -> String {
        lines(in: image).map(\.text).joined(separator: "\n")
    }

    /// Spoken advice to get a page fully in view, or nil when it is well placed.
    /// The camera image is not mirrored: text cut off at the image's left edge
    /// means the page sticks out to the user's right.
    static func guidance(for boxes: [CGRect]) -> String? {
        guard !boxes.isEmpty else { return String(localized: "No text yet. Hold the page in front of the camera, about a foot away.") }
        let area = boxes.reduce(CGRect.null) { $0.union($1) }
        var advice: [String] = []
        if area.minX < 0.02 { advice.append(String(localized: "move the page to your left")) }
        if area.maxX > 0.98 { advice.append(String(localized: "move the page to your right")) }
        if area.maxY > 0.98 { advice.append(String(localized: "move the page down")) }
        if area.minY < 0.02 { advice.append(String(localized: "move the page up")) }
        if advice.isEmpty && area.width * area.height < 0.12 { advice.append(String(localized: "hold the page closer")) }
        guard !advice.isEmpty else { return nil }
        let fix = ListFormatter.localizedString(byJoining: advice).capitalizedFirst
        return String(localized: "Text is cut off. \(fix)")
    }
}

extension String {
    var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
}

final class ScanReader: NSObject, ObservableObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    static let shared = ScanReader()

    @Published private(set) var scanning = false
    @Published private(set) var status = String(localized: "Press Start Scanning, then hold a page up to the camera.")
    @Published private(set) var text = ""

    private let queue = DispatchQueue(label: "VoiceOverAudioSplit.scan")
    private var session: AVCaptureSession?
    private var frames = 0
    private var lastGuidance = Date.distantPast
    private var previousText = ""

    // MARK: Camera

    func start() {
        guard !scanning else { return }
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: begin()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                DispatchQueue.main.async { granted ? self.begin() : self.report(String(localized: "Camera access was not allowed")) }
            }
        default:
            report(String(localized: "Camera access is off. Turn on VoiceOver Audio Split in System Settings, Privacy and Security, Camera."))
        }
    }

    private func begin() {
        guard let camera = CameraChoice.preferred(),
              let input = try? AVCaptureDeviceInput(device: camera) else { return report(String(localized: "No camera found")) }
        let session = AVCaptureSession()
        session.sessionPreset = .high
        let output = AVCaptureVideoDataOutput()
        output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        output.alwaysDiscardsLateVideoFrames = true
        output.setSampleBufferDelegate(self, queue: queue)
        guard session.canAddInput(input), session.canAddOutput(output) else { return report(String(localized: "The camera is busy")) }
        session.addInput(input)
        session.addOutput(output)
        self.session = session
        scanning = true
        report(String(localized: "Scanning. Hold the page up to the camera."))
        // Counters are used on the camera queue, so reset them there, before it starts.
        queue.async {
            self.frames = 0
            self.previousText = ""
            session.startRunning()
        }
    }

    /// Stops on the camera queue, after any start still waiting there, so the camera is always left off.
    func stop() {
        guard let session else { return }
        self.session = nil
        scanning = false
        queue.async { session.stopRunning() }
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        frames += 1
        // Check about twice a second, after the camera has had time to adjust.
        guard frames > 20, frames % 15 == 0, let pixels = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        var image: CGImage?
        VTCreateCGImageFromCVPixelBuffer(pixels, options: nil, imageOut: &image)
        guard let image else { return }
        let lines = TextRecognition.lines(in: image)
        let found = lines.map(\.text).joined(separator: "\n")

        if let advice = TextRecognition.guidance(for: lines.map(\.box)) {
            guard Date().timeIntervalSince(lastGuidance) > 3 else { return }
            lastGuidance = Date()
            DispatchQueue.main.async { if self.scanning { self.report(advice) } }
            return
        }
        // Read once the same text is seen twice in a row, so the page has stopped moving.
        guard found.count >= 15, found == previousText else {
            previousText = found
            return
        }
        DispatchQueue.main.async {
            guard self.scanning else { return } // Stopped meanwhile.
            self.stop()
            self.text = found
            self.status = String(localized: "Text found.")
            Announcer.say(found)
        }
    }

    // MARK: Files

    /// Reads the text in an image file or PDF; scanned PDF pages are recognized like photos.
    func read(_ url: URL) {
        report(String(localized: "Reading \(url.lastPathComponent)"))
        DispatchQueue.global(qos: .userInitiated).async {
            let accessing = url.startAccessingSecurityScopedResource()
            defer { if accessing { url.stopAccessingSecurityScopedResource() } }
            let found = Self.text(in: url)
            DispatchQueue.main.async {
                self.text = found
                self.status = found.isEmpty ? String(localized: "No text found.") : String(localized: "Text found.")
                Announcer.say(found.isEmpty ? String(localized: "No text found in \(url.lastPathComponent)") : found)
            }
        }
    }

    private static func text(in url: URL) -> String {
        if url.pathExtension.lowercased() == "pdf", let pdf = PDFDocument(url: url) {
            return (0..<pdf.pageCount).compactMap { index -> String? in autoreleasepool {
                // Each scanned page is a large picture; free it before the next one.
                guard let page = pdf.page(at: index) else { return nil }
                if let string = page.string, !string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    return string
                }
                // A scanned page: render it and recognize the text.
                let image = page.thumbnail(of: CGSize(width: 2000, height: 2600), for: .mediaBox)
                return image.cgImage(forProposedRect: nil, context: nil, hints: nil).map(TextRecognition.text)
            } }.joined(separator: "\n\n")
        }
        guard let image = NSImage(contentsOf: url)?.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return "" }
        return TextRecognition.text(in: image)
    }

    private func report(_ message: String) {
        status = message
        Announcer.say(message)
    }
}

struct ScanView: View {
    @ObservedObject var reader = ScanReader.shared
    @State private var choosingFile = false

    var body: some View {
        Form {
            Section {
                Text(reader.status)
                HStack {
                    Button(reader.scanning ? String(localized: "Stop Scanning") : String(localized: "Start Scanning")) {
                        reader.scanning ? reader.stop() : reader.start()
                    }
                    .keyboardShortcut(.defaultAction)
                    Button(String(localized: "Read a File…")) { choosingFile = true }
                }
            }
            if !reader.text.isEmpty {
                Section(String(localized: "Text")) {
                    Text(reader.text).textSelection(.enabled)
                    HStack {
                        Button(String(localized: "Read Again")) { Announcer.say(reader.text) }
                        Button(String(localized: "Copy")) {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(reader.text, forType: .string)
                            Announcer.say(String(localized: "Copied"))
                        }
                        Button(String(localized: "Save as Text…")) { TextExport.save(reader.text, as: .text) }
                        Button(String(localized: "Save as Word…")) { TextExport.save(reader.text, as: .word) }
                        Button(String(localized: "Open in Doc Reader")) {
                            DocReaderModel.shared.load(reader.text)
                            (NSApp.delegate as? AppDelegate)?.showDocReader()
                        }
                    }
                }
            }
            Section {
                Text(String(localized: "Text is recognized on your Mac. Pictures are never saved or sent anywhere."))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 560, height: 520)
        .fileImporter(isPresented: $choosingFile, allowedContentTypes: [.image, .pdf]) {
            if case .success(let url) = $0 { reader.read(url) }
        }
        .onDisappear { reader.stop() }
    }
}
