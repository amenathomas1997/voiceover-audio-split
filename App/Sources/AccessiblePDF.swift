// AccessiblePDF.swift — turns pages from the camera, a photo or a scanned PDF into
// an accessible PDF: real, selectable text in reading order, tagged headings and
// paragraphs, bookmarks for the headings, a title and the document language.
// Headings are guessed from text size (larger lines are headings), so they're
// a good start, not a guarantee. After saving, the PDF is checked with the
// Document Check and the result is spoken. Text recognition runs on the Mac
// with Apple's Vision framework; nothing is sent anywhere.

import AppKit
import CoreText
import NaturalLanguage
import PDFKit
import SwiftUI
import UniformTypeIdentifiers
import VideoToolbox
import Vision

enum AccessiblePDF {
    /// A recognized line of text; the box is normalised to its page, origin bottom left.
    struct Line: Equatable {
        var text: String
        var box: CGRect
    }

    enum Block: Equatable {
        case heading(level: Int, text: String)
        case paragraph(String)

        var text: String {
            switch self {
            case .heading(_, let text), .paragraph(let text): text
            }
        }
    }

    // MARK: Structure

    /// Top to bottom; lines side by side on the same row, left to right.
    static func readingOrder(_ lines: [Line]) -> [Line] {
        var rows: [[Line]] = []
        for line in lines.sorted(by: { $0.box.maxY > $1.box.maxY }) {
            // Same row when its middle is within the height of the row's first line.
            if let first = rows.last?.first, line.box.midY >= first.box.minY, line.box.midY <= first.box.maxY {
                rows[rows.count - 1].append(line)
            } else {
                rows.append([line])
            }
        }
        return rows.flatMap { $0.sorted { $0.box.minX < $1.box.minX } }
    }

    /// Heading level for a line, from how much taller it is than the body text:
    /// 1.7 times or more is level 1, 1.25 times level 2. Long lines and sentences aren't headings.
    static func headingLevel(height: CGFloat, bodyHeight: CGFloat, text: String) -> Int? {
        guard bodyHeight > 0, text.contains(where: \.isLetter) else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard trimmed.split(separator: " ").count <= 12, !trimmed.hasSuffix("."), !trimmed.hasSuffix(",") else { return nil }
        let ratio = height / bodyHeight
        return ratio >= 1.7 ? 1 : ratio >= 1.25 ? 2 : nil
    }

    /// Headings and paragraphs for one page, in reading order.
    static func blocks(from lines: [Line]) -> [Block] {
        let ordered = readingOrder(lines.filter { !$0.text.trimmingCharacters(in: .whitespaces).isEmpty })
        guard !ordered.isEmpty else { return [] }
        let heights = ordered.map(\.box.height).sorted()
        let body = heights[heights.count / 2]
        let widest = ordered.map(\.box.width).max() ?? 1
        var blocks: [Block] = []
        var previous: (line: Line, level: Int?)?
        for line in ordered {
            let text = line.text.trimmingCharacters(in: .whitespaces)
            let level = ordered.count > 1 ? headingLevel(height: line.box.height, bodyHeight: body, text: text) : nil
            defer { previous = (line, level) }
            guard let last = previous, let block = blocks.last else {
                blocks.append(level.map { .heading(level: $0, text: text) } ?? .paragraph(text))
                continue
            }
            let gap = last.line.box.minY - line.box.maxY
            let near = gap < 0.6 * max(body, min(last.line.box.height, line.box.height))
            // A short line ending a sentence ends its paragraph.
            let ended = last.line.text.trimmingCharacters(in: .whitespaces).last.map { ".!?:".contains($0) } == true
                && last.line.box.width < 0.75 * widest
            switch (block, level) {
            case (.heading(let previousLevel, let heading), let level?) where level == previousLevel && near:
                blocks[blocks.count - 1] = .heading(level: level, text: joined(heading, text))
            case (.paragraph(let paragraph), nil) where last.level == nil && near && !ended:
                blocks[blocks.count - 1] = .paragraph(joined(paragraph, text))
            default:
                blocks.append(level.map { .heading(level: $0, text: text) } ?? .paragraph(text))
            }
        }
        return blocks
    }

    /// Joins two lines of a paragraph, mending a word broken with a hyphen.
    static func joined(_ first: String, _ second: String) -> String {
        if first.hasSuffix("-"), first.dropLast().last?.isLetter == true, second.first?.isLowercase == true {
            return String(first.dropLast()) + second
        }
        return first + " " + second
    }

    /// Plain text, such as Scan and Read's: paragraphs split at blank lines. No headings can be told.
    static func blocks(fromPlainText text: String) -> [Block] {
        text.components(separatedBy: "\n\n").compactMap { chunk in
            let lines = chunk.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            guard let first = lines.first else { return nil }
            return .paragraph(lines.dropFirst().reduce(first, joined))
        }
    }

    /// If no page has a level 1 heading, level 2 headings become level 1, so levels start at 1.
    static func normalizedLevels(_ pages: [[Block]]) -> [[Block]] {
        let hasTop = pages.joined().contains { if case .heading(1, _) = $0 { true } else { false } }
        guard !hasTop else { return pages }
        return pages.map { $0.map { if case .heading(_, let text) = $0 { .heading(level: 1, text: text) } else { $0 } } }
    }

    /// The first heading, or else the start of the first paragraph.
    static func title(for pages: [[Block]]) -> String? {
        let blocks = pages.joined()
        let heading = blocks.first { if case .heading = $0 { true } else { false } }
        guard let source = (heading ?? blocks.first)?.text else { return nil }
        let words = source.split(separator: " ")
        let short = words.prefix(10).joined(separator: " ")
        return words.count > 10 ? short + "…" : short
    }

    /// The text's language as a BCP 47 code, such as "en", or the Mac's language.
    static func language(of text: String) -> String {
        if let found = NLLanguageRecognizer.dominantLanguage(for: text), found != .undetermined { return found.rawValue }
        return Locale.current.language.languageCode?.identifier ?? "en"
    }

    // MARK: Writing

    /// A PDF with real text drawn by Core Text, tagged H1 to H3 and P in reading order,
    /// with bookmarks for headings and the title in the document info.
    static func pdfData(pages: [[Block]], title: String) -> Data? {
        let data = NSMutableData()
        let letter = Locale.current.measurementSystem == .us
        var media = CGRect(x: 0, y: 0, width: letter ? 612 : 595, height: letter ? 792 : 842)
        let info: [CFString: Any] = [kCGPDFContextTitle: title, kCGPDFContextCreator: "VoiceOver Audio Split"]
        guard let consumer = CGDataConsumer(data: data as CFMutableData),
              let context = CGContext(consumer: consumer, mediaBox: &media, info as CFDictionary) else { return nil }
        let margin: CGFloat = 72
        let width = media.width - 2 * margin
        var pageNumber = 0
        var cursor: CGFloat = 0
        var bookmarks: [[CFString: Any]] = []

        func newPage() {
            if pageNumber > 0 { context.endPDFPage() }
            context.beginPDFPage(nil)
            context.textMatrix = .identity
            pageNumber += 1
            cursor = media.height - margin
        }

        for page in pages where !page.isEmpty {
            newPage()
            for block in page {
                let (string, tag, spacing) = styled(block)
                let setter = CTFramesetterCreateWithAttributedString(string)
                // Keep a heading with the text after it.
                if case .heading = block, cursor - margin < 80, cursor < media.height - margin { newPage() }
                var start = 0
                while start < string.length {
                    let rect = CGRect(x: margin, y: margin, width: width, height: max(cursor - margin, 0))
                    let frame = CTFramesetterCreateFrame(setter, CFRange(location: start, length: 0), CGPath(rect: rect, transform: nil), nil)
                    let shown = CTFrameGetVisibleStringRange(frame)
                    guard shown.length > 0 else {
                        // Not even one line fits: continue on a new page.
                        if cursor < media.height - margin { newPage(); continue }
                        break
                    }
                    if case .heading = block, start == 0 {
                        bookmarks.append([kCGPDFOutlineTitle: block.text, kCGPDFOutlineDestination: pageNumber as CFNumber,
                                          kCGPDFOutlineDestinationRect: CGRect(x: margin, y: cursor - 30, width: width, height: 30).dictionaryRepresentation])
                    }
                    CGPDFContextBeginTag(context, tag, [:] as CFDictionary)
                    CTFrameDraw(frame, context)
                    CGPDFContextEndTag(context)
                    let used = CTFramesetterSuggestFrameSizeWithConstraints(setter, CFRange(location: start, length: shown.length), nil,
                                                                             CGSize(width: width, height: .greatestFiniteMagnitude), nil)
                    cursor -= used.height + spacing
                    start += shown.length
                    if start < string.length { newPage() }
                }
            }
        }
        guard pageNumber > 0 else { return nil }
        context.endPDFPage()
        if !bookmarks.isEmpty {
            CGPDFContextSetOutline(context, [kCGPDFOutlineChildren: bookmarks] as CFDictionary)
        }
        context.closePDF()
        return data as Data
    }

    private static func styled(_ block: Block) -> (NSAttributedString, CGPDFTagType, CGFloat) {
        let (size, bold, tag, spacing): (CGFloat, Bool, CGPDFTagType, CGFloat) = switch block {
        case .heading(1, _): (22, true, .header1, 10)
        case .heading(2, _): (17, true, .header2, 8)
        case .heading: (14, true, .header3, 6)
        case .paragraph: (12, false, .paragraph, 10)
        }
        let font = CTFontCreateWithName((bold ? "Helvetica-Bold" : "Helvetica") as CFString, size, nil)
        let attributes: [NSAttributedString.Key: Any] = [NSAttributedString.Key(kCTFontAttributeName as String): font]
        return (NSAttributedString(string: block.text, attributes: attributes), tag, spacing)
    }

    /// Core Graphics can't set the document language, so it is added the standard way
    /// for changing a PDF: a new copy of the catalog appended at the end with its own
    /// cross-reference section. It also asks readers to show the title, not the file
    /// name. Nil if the file isn't laid out as expected.
    static func addingLanguage(_ language: String, to data: Data) -> Data? {
        // Latin-1 keeps every byte as one character, so nothing is lost.
        guard let text = String(data: data, encoding: .isoLatin1),
              let trailerStart = text.range(of: "trailer", options: .backwards),
              let startxref = text.range(of: "startxref", options: .backwards),
              trailerStart.upperBound < startxref.lowerBound else { return nil }
        let trailer = String(text[trailerStart.upperBound..<startxref.lowerBound])
        guard let root = capture(#"/Root (\d+) (\d+) R"#, in: trailer, groups: 2), let size = capture(#"/Size (\d+)"#, in: trailer)?.first,
              let previous = capture(#"^\s*(\d+)"#, in: String(text[startxref.upperBound...]))?.first else { return nil }
        let (number, generation) = (root[0], root[1])
        // The latest copy of the catalog, in case the file was already changed this way.
        guard let objectStart = text.range(of: "\n\(number) \(generation) obj", options: .backwards)
                ?? text.range(of: "\r\(number) \(generation) obj", options: .backwards),
              let objectEnd = text.range(of: "endobj", range: objectStart.upperBound..<text.endIndex) else { return nil }
        let object = text[objectStart.upperBound..<objectEnd.lowerBound]
        guard let open = object.range(of: "<<"), let close = object.range(of: ">>", options: .backwards) else { return nil }
        let catalog = String(object[open.upperBound..<close.lowerBound])
        guard !catalog.contains("/Lang") else { return data }
        let code = language.filter { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") }
        var additions = " /Lang (\(code.isEmpty ? "en" : code))"
        if !catalog.contains("/ViewerPreferences") { additions += " /ViewerPreferences << /DisplayDocTitle true >>" }

        var output = data
        if output.last != 0x0A { output.append(0x0A) }
        let objectOffset = output.count
        output.append(Data("\(number) \(generation) obj\n<<\(catalog)\(additions) >>\nendobj\n".utf8))
        let xrefOffset = output.count
        let entry = String(format: "%010d %05d n\r\n", objectOffset, Int(generation) ?? 0)
        var newTrailer = "/Size \(size) /Root \(number) \(generation) R"
        if let info = capture(#"(/Info \d+ \d+ R)"#, in: trailer)?.first { newTrailer += " " + info }
        if let id = capture(#"(/ID\s*\[[^\]]*\])"#, in: trailer)?.first { newTrailer += " " + id }
        newTrailer += " /Prev \(previous)"
        output.append(Data("xref\n\(number) 1\n\(entry)trailer\n<< \(newTrailer) >>\nstartxref\n\(xrefOffset)\n%%EOF\n".utf8))
        return output
    }

    private static func capture(_ pattern: String, in text: String, groups: Int = 1) -> [String]? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) else { return nil }
        let found = (1...groups).compactMap { Range(match.range(at: $0), in: text).map { String(text[$0]) } }
        return found.count == groups ? found : nil
    }

    /// The finished file: tagged text, title, bookmarks and language.
    static func document(pages: [[Block]], title: String) -> Data? {
        let pages = normalizedLevels(pages)
        guard let data = pdfData(pages: pages, title: title) else { return nil }
        let all = pages.joined().map(\.text).joined(separator: "\n")
        return addingLanguage(language(of: all), to: data) ?? data
    }

    // MARK: Reading files

    /// The lines on each page of an image file or PDF. PDF pages that already have
    /// text keep it; scanned pages are recognized like photos.
    static func lines(in url: URL) -> [[Line]] {
        if url.pathExtension.lowercased() == "pdf", let pdf = PDFDocument(url: url) {
            return (0..<pdf.pageCount).map { index in autoreleasepool {
                guard let page = pdf.page(at: index) else { return [] }
                let bounds = page.bounds(for: .mediaBox)
                if let text = page.string, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                   let lines = page.selection(for: bounds)?.selectionsByLine(), bounds.width > 0, bounds.height > 0 {
                    return lines.compactMap { line -> Line? in
                        guard let string = line.string?.trimmingCharacters(in: .whitespacesAndNewlines), !string.isEmpty else { return nil }
                        let box = line.bounds(for: page)
                        return Line(text: string, box: CGRect(x: (box.minX - bounds.minX) / bounds.width, y: (box.minY - bounds.minY) / bounds.height,
                                                              width: box.width / bounds.width, height: box.height / bounds.height))
                    }
                }
                // A scanned page: render it and recognize the text.
                let image = page.thumbnail(of: CGSize(width: 2000, height: 2600), for: .mediaBox)
                return image.cgImage(forProposedRect: nil, context: nil, hints: nil).map(recognized) ?? []
            } }
        }
        guard let image = NSImage(contentsOf: url)?.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return [] }
        return [recognized(image)]
    }

    static func recognized(_ image: CGImage) -> [Line] {
        TextRecognition.lines(in: image).map { Line(text: $0.text, box: $0.box) }
    }

    // MARK: Entry points

    /// Counts file conversions, so a slow earlier one doesn't open a save panel later.
    @MainActor private static var generation = 0

    /// Choose a photo or PDF, then save it as an accessible PDF.
    @MainActor static func makeFromFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image, .pdf]
        panel.message = String(localized: "Choose a photo or PDF to make accessible")
        NSApp.activate()
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Announcer.say(String(localized: "Reading \(url.lastPathComponent)"))
        generation += 1
        let thisRun = generation
        Task.detached(priority: .userInitiated) {
            let accessing = url.startAccessingSecurityScopedResource()
            defer { if accessing { url.stopAccessingSecurityScopedResource() } }
            let pages = lines(in: url).map(blocks)
            await MainActor.run {
                guard generation == thisRun else { return }
                save(pages, name: url.deletingPathExtension().lastPathComponent + " " + String(localized: "accessible"))
            }
        }
    }

    /// Opens the window that scans pages with the camera, one at a time.
    @MainActor static func makeFromCamera() {
        showWindow()
        if PDFScanModel.shared.pages.isEmpty && !PDFScanModel.shared.scanning { PDFScanModel.shared.scanPage() }
    }

    /// Plain text, such as Scan and Read's result, as an accessible PDF (paragraphs only).
    @MainActor static func makeFromText(_ text: String) {
        save([blocks(fromPlainText: text)], name: nil)
    }

    /// Asks where to save, writes the PDF, then checks it and says what was found.
    @MainActor static func save(_ pages: [[Block]], name: String?) {
        let pages = pages.filter { !$0.isEmpty }
        guard !pages.isEmpty else { return Announcer.say(String(localized: "No text was found, so there's nothing to save.")) }
        let title = title(for: pages) ?? String(localized: "Scanned document")
        let panel = NSSavePanel()
        let base = (name ?? title).replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
        panel.nameFieldStringValue = base + ".pdf"
        panel.allowedContentTypes = [.pdf]
        panel.canCreateDirectories = true
        panel.message = String(localized: "Save the accessible PDF")
        NSApp.activate()
        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard let data = document(pages: pages, title: title) else { return Announcer.say(String(localized: "Couldn't make the PDF")) }
        do {
            try data.write(to: url, options: .atomic)
        } catch {
            return Announcer.say(String(localized: "Couldn't save the file"))
        }
        let headings = pages.joined().filter { if case .heading = $0 { true } else { false } }.count
        var spoken = String(localized: "Saved \(url.lastPathComponent). Headings found: \(headings).")
        if let saved = PDFDocument(url: url) {
            spoken += " " + DocumentCheck.summary(DocumentCheck.checkPDF(saved), name: url.deletingPathExtension().lastPathComponent)
        }
        Announcer.say(spoken)
    }

    private static var window: NSWindow?

    @MainActor static func showWindow() {
        let window = self.window ?? {
            let window = NSWindow(contentViewController: NSHostingController(rootView: PDFScanView()))
            window.title = String(localized: "Scan to Accessible PDF")
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            window.center()
            return window
        }()
        self.window = window
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }
}

// MARK: - Camera pages

/// Scans one page at a time with the camera, with the same spoken guidance as Scan and Read.
@MainActor
final class PDFScanModel: ObservableObject {
    static let shared = PDFScanModel()

    @Published private(set) var pages: [[AccessiblePDF.Line]] = []
    @Published private(set) var scanning = false
    @Published private(set) var status = String(localized: "Press Scan Page, then hold the first page up to the camera.")

    private let feed = CameraFeed()
    /// Counts scans, so a page read just as one stops isn't added to the next.
    private var run = 0

    /// Starts reading a page. It is added once the same text is seen twice in a row.
    func scanPage() {
        guard !scanning else { return }
        run += 1
        let thisRun = run
        scanning = true
        report(pages.isEmpty ? String(localized: "Scanning. Hold the first page up to the camera.")
                             : String(localized: "Scanning page \(pages.count + 1)."))
        nonisolated(unsafe) var frame = 0
        nonisolated(unsafe) var previous = ""
        nonisolated(unsafe) var lastGuidance = Date.distantPast
        nonisolated(unsafe) var done = false
        feed.start(preset: .high, { [weak self] pixels in
            frame += 1
            // About twice a second.
            guard !done, frame % 15 == 0 else { return }
            var image: CGImage?
            VTCreateCGImageFromCVPixelBuffer(pixels, options: nil, imageOut: &image)
            guard let image else { return }
            let lines = AccessiblePDF.recognized(image)
            if let advice = TextRecognition.guidance(for: lines.map(\.box)) {
                guard Date().timeIntervalSince(lastGuidance) > 3 else { return }
                lastGuidance = Date()
                Task { @MainActor in if self?.run == thisRun, self?.scanning == true { self?.report(advice) } }
                return
            }
            let text = lines.map(\.text).joined(separator: "\n")
            guard text.count >= 15, text == previous else {
                previous = text
                return
            }
            done = true
            Task { @MainActor in self?.add(lines, thisRun: thisRun) }
        }, failed: { [weak self] message in
            Task { @MainActor in
                self?.scanning = false
                self?.report(message)
            }
        })
    }

    private func add(_ lines: [AccessiblePDF.Line], thisRun: Int) {
        guard run == thisRun, scanning else { return }
        stopCamera()
        pages.append(lines)
        Tones.play(.device)
        report(String(localized: "Page \(pages.count) added. Press Next Page for another, or Done to save."))
    }

    /// Saves every page scanned so far as one PDF, then starts fresh.
    func done() {
        stopCamera()
        guard !pages.isEmpty else { return report(String(localized: "No pages yet. Press Scan Page first.")) }
        let finished = pages.map(AccessiblePDF.blocks)
        AccessiblePDF.save(finished, name: nil)
        pages = []
        status = String(localized: "Press Scan Page, then hold the first page up to the camera.")
    }

    /// Throws away the pages scanned so far.
    func startOver() {
        stopCamera()
        pages = []
        report(String(localized: "Pages cleared."))
    }

    func stopCamera() {
        run += 1
        scanning = false
        feed.stop()
    }

    private func report(_ message: String) {
        status = message
        Announcer.say(message)
    }
}

struct PDFScanView: View {
    @ObservedObject var model = PDFScanModel.shared

    var body: some View {
        Form {
            Section {
                Text(model.status)
                Text(String(localized: "Pages scanned: \(model.pages.count)"))
                HStack {
                    Button(model.pages.isEmpty ? String(localized: "Scan Page") : String(localized: "Next Page")) { model.scanPage() }
                        .disabled(model.scanning)
                        .keyboardShortcut(.defaultAction)
                    Button(String(localized: "Done and Save…")) { model.done() }
                        .disabled(model.pages.isEmpty)
                    Button(String(localized: "Stop Scanning")) { model.stopCamera() }
                        .disabled(!model.scanning)
                    Button(String(localized: "Start Over")) { model.startOver() }
                        .disabled(model.pages.isEmpty)
                }
                Button(String(localized: "Make a File Accessible…")) { AccessiblePDF.makeFromFile() }
            }
            Section {
                Text(String(localized: "The PDF gets real text, headings, bookmarks, a title and its language. Headings are guessed from larger text, so check them. Text is recognized on your Mac; pictures are never saved or sent anywhere."))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 520, height: 360)
        .onDisappear { model.stopCamera() }
    }
}
