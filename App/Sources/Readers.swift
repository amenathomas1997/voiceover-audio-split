// Readers.swift — camera readers for everyday things:
//   * Barcode and QR code reader: reads QR codes (links, Wi-Fi details, text) and
//     looks up product barcodes in Open Food Facts, a free product database
//   * Medicine label reader: reads the largest text first (usually the medicine's
//     name), then the rest, and keeps reading new text as you turn the bottle
//   * Money identifier: asks Claude which banknote or coins are in the picture
// Codes and labels are read on the Mac. Only a product's barcode number is sent
// (to Open Food Facts); only the money reader sends a picture (to Anthropic), and
// only when image descriptions are allowed.

import AppKit
import AVFoundation
import CoreImage
import Vision

// MARK: - Barcodes and QR codes

enum CodeReader {
    private static let feed = CameraFeed()
    private static var timeout: DispatchWorkItem?
    private static var reminder: DispatchWorkItem?

    static var isRunning: Bool { feed.isRunning }

    static func toggle() {
        if isRunning { return stop(saying: String(localized: "Code reader off")) }
        Tones.play(.status)
        Announcer.say(String(localized: "Looking for a code. Hold it about 20 centimeters from the camera and turn it slowly."))
        var frame = 0
        nonisolated(unsafe) var found = false
        feed.start({ pixels in
            frame += 1
            guard !found, frame % 6 == 0 else { return }
            let request = VNDetectBarcodesRequest()
            try? VNImageRequestHandler(cvPixelBuffer: pixels).perform([request])
            guard let code = request.results?.first(where: { $0.payloadStringValue?.isEmpty == false }),
                  let payload = code.payloadStringValue else { return }
            found = true
            DispatchQueue.main.async { handle(payload, symbology: code.symbology) }
        }, failed: { Announcer.say($0) })
        let remind = DispatchWorkItem {
            if isRunning { Announcer.say(String(localized: "Still looking. On packages, the barcode is often on the bottom or the back.")) }
        }
        reminder = remind
        DispatchQueue.main.asyncAfter(deadline: .now() + 12, execute: remind)
        let work = DispatchWorkItem { if isRunning { stop(saying: String(localized: "No code found. Try again with more light.")) } }
        timeout = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 40, execute: work)
    }

    private static func stop(saying text: String?) {
        timeout?.cancel()
        reminder?.cancel()
        feed.stop()
        if let text { Announcer.say(text) }
    }

    private static func handle(_ payload: String, symbology: VNBarcodeSymbology) {
        stop(saying: nil)
        Tones.play(.device)
        let product: Set<VNBarcodeSymbology> = [.ean13, .ean8, .upce, .itf14]
        if product.contains(symbology), payload.allSatisfy(\.isNumber) {
            Announcer.say(String(localized: "Barcode \(spaced(payload)). Looking it up."))
            lookUp(payload)
            return
        }
        copy(payload)
        Announcer.say(describe(payload))
    }

    /// What a QR code holds, in words.
    static func describe(_ payload: String) -> String {
        if payload.hasPrefix("WIFI:") {
            func field(_ key: String) -> String {
                payload.components(separatedBy: ";").first { $0.hasPrefix(key + ":") || $0.hasPrefix("WIFI:" + key + ":") }?
                    .components(separatedBy: key + ":").last ?? ""
            }
            return String(localized: "Wi-Fi network \(field("S")). The details are copied to the clipboard.")
        }
        if let url = URL(string: payload), let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme),
           let host = url.host() {
            return String(localized: "Link to \(SitePresets.normalize(host)). Copied to the clipboard.")
        }
        if payload.lowercased().hasPrefix("mailto:") {
            return String(localized: "Email address \(String(payload.dropFirst(7))). Copied to the clipboard.")
        }
        if payload.lowercased().hasPrefix("tel:") {
            return String(localized: "Phone number \(String(payload.dropFirst(4))). Copied to the clipboard.")
        }
        return String(localized: "Code says: \(payload). Copied to the clipboard.")
    }

    /// Digits read in groups, so a long number is easy to follow.
    private static func spaced(_ digits: String) -> String {
        stride(from: 0, to: digits.count, by: 4).map {
            let start = digits.index(digits.startIndex, offsetBy: $0)
            return String(digits[start..<(digits.index(start, offsetBy: 4, limitedBy: digits.endIndex) ?? digits.endIndex)])
        }.joined(separator: " ")
    }

    private static func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    private static func lookUp(_ code: String) {
        guard let url = URL(string: "https://world.openfoodfacts.org/api/v2/product/\(code).json?fields=product_name,brands,quantity") else { return }
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.setValue("VoiceOverAudioSplit/1.0 (https://github.com/amenathomas1997/voiceover-audio-split)", forHTTPHeaderField: "User-Agent")
        URLSession.shared.dataTask(with: request) { data, _, _ in
            let json = data.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
            let product = json?["product"] as? [String: Any]
            let text = productDescription(product)
            DispatchQueue.main.async {
                copy(code)
                Announcer.say(text ?? String(localized: "The product isn't in the database. The barcode number is copied to the clipboard."))
            }
        }.resume()
    }

    /// "Wholegrain oats by Quaker, 500 g", from Open Food Facts.
    static func productDescription(_ product: [String: Any]?) -> String? {
        guard let product, let name = (product["product_name"] as? String)?.trimmingCharacters(in: .whitespaces), !name.isEmpty
        else { return nil }
        let brand = (product["brands"] as? String)?.components(separatedBy: ",").first?.trimmingCharacters(in: .whitespaces) ?? ""
        // European packs add an "e" (estimated weight) after the quantity.
        let quantity = ((product["quantity"] as? String) ?? "").replacingOccurrences(of: #"\s*(e|℮)$"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
        var text = brand.isEmpty || name.localizedCaseInsensitiveContains(brand) ? name : String(localized: "\(name) by \(brand)")
        if !quantity.isEmpty { text += ", " + quantity }
        return text
    }
}

// MARK: - Medicine labels

enum LabelReader {
    private static let feed = CameraFeed()
    private static var stopWork: DispatchWorkItem?
    nonisolated(unsafe) private static var heard: [String] = []
    nonisolated(unsafe) private static var waiting: [String] = []
    nonisolated(unsafe) private static var lastSpoken = Date.distantPast
    private static let lock = NSLock()

    static var isRunning: Bool { feed.isRunning }

    static func toggle() {
        isRunning ? stop() : start()
    }

    private static func start() {
        lock.withLock { heard = []; waiting = [] }
        Tones.play(.status)
        Announcer.say(String(localized: "Label reader on. Hold the label about 20 centimeters from the camera and turn the bottle slowly. Run it again to stop."))
        lastSpoken = Date()
        var frame = 0
        feed.start(preset: .high, { pixels in
            frame += 1
            guard frame % 20 == 0 else { return }
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            try? VNImageRequestHandler(cvPixelBuffer: pixels).perform([request])
            let lines = (request.results ?? []).compactMap { observation -> (String, CGRect)? in
                guard let best = observation.topCandidates(1).first, best.confidence > 0.5,
                      best.string.trimmingCharacters(in: .whitespaces).count >= 3 else { return nil }
                return (best.string, observation.boundingBox)
            }
            add(ordered(lines))
        }, failed: { Announcer.say($0) })
        let work = DispatchWorkItem { if isRunning { stop() } }
        stopWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 120, execute: work)
    }

    /// The largest text first (usually the name and strength), then the rest from top to bottom.
    static func ordered(_ lines: [(String, CGRect)]) -> [String] {
        guard !lines.isEmpty else { return [] }
        let largest = lines.max { $0.1.height < $1.1.height }!
        let rest = lines.filter { $0.0 != largest.0 }.sorted { $0.1.midY > $1.1.midY }
        return [largest.0] + rest.map(\.0)
    }

    /// Queues text not heard yet, and speaks it in batches so speech isn't cut off.
    private static func add(_ lines: [String]) {
        let text: String? = lock.withLock {
            for line in lines where !isHeard(line) {
                heard.append(line)
                waiting.append(line)
            }
            guard !waiting.isEmpty, Date().timeIntervalSince(lastSpoken) > 5 else { return nil }
            lastSpoken = Date()
            defer { waiting = [] }
            return waiting.joined(separator: ". ")
        }
        if let text { DispatchQueue.main.async { Announcer.say(text) } }
    }

    /// The same line read again, or a longer or shorter reading of it, counts as heard.
    private static func isHeard(_ line: String) -> Bool {
        let key = normalized(line)
        return heard.contains { let other = normalized($0); return other.contains(key) || key.contains(other) }
    }

    static func normalized(_ text: String) -> String {
        text.lowercased().filter { $0.isLetter || $0.isNumber }
    }

    private static func stop() {
        stopWork?.cancel()
        feed.stop()
        let all = lock.withLock { heard }
        guard !all.isEmpty else { return Announcer.say(String(localized: "Label reader off. No text was found.")) }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(all.joined(separator: "\n"), forType: .string)
        Announcer.say(String(localized: "Label reader off. Everything it read is copied to the clipboard."))
    }
}

// MARK: - Money

enum MoneyReader {
    private static let feed = CameraFeed()

    static func identify() {
        guard !feed.isRunning else { return }
        guard Preferences.shared.allowImageUpload else {
            return Announcer.say(String(localized: "Identifying money sends a camera picture to Anthropic. Allow image descriptions first: describe any image once and choose Allow."))
        }
        guard APIKey.current != nil else { return Announcer.say(String(localized: "Add your Anthropic API key in Settings first.")) }
        Tones.play(.status)
        Announcer.say(String(localized: "Hold the banknote flat, about 20 centimeters from the camera."))
        var frames = 0
        feed.start(preset: .high, { pixels in
            frames += 1
            // Give the person time to hold it up after the instruction.
            guard frames == 90, let jpeg = jpeg(pixels) else { return }
            DispatchQueue.main.async {
                feed.stop()
                Announcer.say(String(localized: "Identifying"))
                ask(jpeg)
            }
        }, failed: { Announcer.say($0) })
    }

    private static func jpeg(_ pixels: CVPixelBuffer) -> Data? {
        CIContext().jpegRepresentation(of: CIImage(cvPixelBuffer: pixels), colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
                                       options: [kCGImageDestinationLossyCompressionQuality as CIImageRepresentationOption: 0.8])
    }

    private static func ask(_ jpeg: Data) {
        Task {
            let content: [[String: Any]] = [
                ["type": "image", "source": ["type": "base64", "media_type": "image/jpeg", "data": jpeg.base64EncodedString()]],
                ["type": "text", "text": "Identify the money in this camera picture: the currency and the value of each banknote or coin, and the total if there are several. Answer in one short sentence. If no money is visible or you're not sure, say so and suggest how to hold it."],
            ]
            let answer: String
            do {
                answer = try await Claude.send([["role": "user", "content": content]]).text
            } catch let failure as Claude.Failure {
                answer = failure.message
            } catch {
                answer = String(localized: "The request failed.")
            }
            await MainActor.run { Announcer.say(answer) }
        }
    }
}
