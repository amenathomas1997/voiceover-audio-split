// DocumentCheck.swift — checks a Word document or PDF for what makes it hard to
// read with a screen reader, before you send it: a missing title, no headings or
// skipped heading levels, pictures without descriptions, tables without header
// rows, blank lines used for spacing, unclear link text, and for PDFs, no text
// (a scan) or no tags. Like Word's Accessibility Checker, but spoken and on any Mac.
// Runs on the Mac; nothing is sent anywhere.

import AppKit
import Compression
import PDFKit
import SwiftUI
import UniformTypeIdentifiers

enum DocumentCheck {
    struct Finding: Identifiable, Hashable {
        let id = UUID()
        let problem: String
        let fix: String
    }

    static func check(_ url: URL) -> [Finding]? {
        switch url.pathExtension.lowercased() {
        case "docx": Zip.entries(of: url, only: ["word/document.xml", "word/styles.xml", "docProps/core.xml"]).map(checkWord)
        case "pdf": PDFDocument(url: url).map(checkPDF)
        default: nil
        }
    }

    // MARK: Word

    static func checkWord(_ files: [String: Data]) -> [Finding] {
        let document = files["word/document.xml"].flatMap { String(data: $0, encoding: .utf8) } ?? ""
        let core = files["docProps/core.xml"].flatMap { String(data: $0, encoding: .utf8) } ?? ""
        var findings: [Finding] = []

        let title = first(#"<dc:title>([^<]*)</dc:title>"#, in: core)?.trimmingCharacters(in: .whitespaces) ?? ""
        if title.isEmpty {
            findings.append(Finding(problem: String(localized: "The document has no title."),
                                    fix: String(localized: "In Word, choose File, Properties, and fill in Title. Screen readers announce it when the document opens.")))
        }

        let paragraphs = matches(#"<w:p(?: [^>]*)?/>|<w:p(?: [^>]*)?>.*?</w:p>"#, in: document)
        let headingStyles = headingLevels(files["word/styles.xml"].flatMap { String(data: $0, encoding: .utf8) } ?? "")
        let levels = paragraphs.compactMap { paragraph -> Int? in
            if let outline = first(#"<w:outlineLvl w:val="(\d)""#, in: paragraph), let level = Int(outline) { return level + 1 }
            guard let style = first(#"<w:pStyle w:val="([^"]+)""#, in: paragraph) else { return nil }
            if let level = headingStyles[style] { return level }
            if style == "Title" { return 0 }
            return style.hasPrefix("Heading") ? Int(style.dropFirst(7)) : nil
        }
        if levels.isEmpty && paragraphs.count > 15 {
            findings.append(Finding(problem: String(localized: "There are no headings."),
                                    fix: String(localized: "Use Word's Heading 1, Heading 2 and so on for section titles, rather than bold or larger text, so people can jump between sections.")))
        }
        var previous = 0
        for level in levels where level > 0 {
            if level > previous + 1 {
                findings.append(Finding(problem: previous == 0 ? String(localized: "The first heading is level \(level), not level 1.")
                                                               : String(localized: "A heading skips from level \(previous) to level \(level)."),
                                        fix: String(localized: "Use heading levels in order, so a Heading \(previous + 1) comes before any Heading \(level).")))
                break
            }
            previous = level
        }

        // A picture's description and "decorative" mark are both inside its docPr.
        let pictures = matches(#"<wp:docPr\b[^>]*/>|<wp:docPr\b[^>]*>.*?</wp:docPr>"#, in: document)
        let undescribed = pictures.filter { picture in
            (first(#"descr="([^"]*)""#, in: picture) ?? "").trimmingCharacters(in: .whitespaces).isEmpty
                && first(#"<adec:decorative\b[^>]*\bval="(1|true)""#, in: picture) == nil
        }.count
        if undescribed > 0 {
            let count = undescribed
            findings.append(Finding(problem: count == 1 ? String(localized: "1 picture has no description.") : String(localized: "\(count) pictures have no description."),
                                    fix: String(localized: "In Word, select each picture and choose View Alt Text. Describe it, or mark it as decorative.")))
        }

        let tables = matches(#"<w:tbl>.*?</w:tbl>"#, in: document)
        let headerless = tables.filter { !$0.contains("<w:tblHeader") }.count
        if headerless > 0 {
            findings.append(Finding(problem: headerless == 1 ? String(localized: "1 table has no header row.") : String(localized: "\(headerless) tables have no header row."),
                                    fix: String(localized: "Select the table's first row and turn on Repeat Header Rows, so screen readers announce column names.")))
        }

        // Empty table cells hold empty paragraphs too, and page or section breaks have no text.
        let outsideTables = document.replacingOccurrences(of: #"<w:tbl>.*?</w:tbl>"#, with: "", options: .regularExpression)
        var blankRun = 0, spacing = 0
        for paragraph in matches(#"<w:p(?: [^>]*)?/>|<w:p(?: [^>]*)?>.*?</w:p>"#, in: outsideTables) {
            if text(of: paragraph).trimmingCharacters(in: .whitespaces).isEmpty && !paragraph.contains("<w:drawing")
                && !paragraph.contains("w:type=\"page\"") && !paragraph.contains("<w:sectPr") {
                blankRun += 1
                if blankRun == 3 { spacing += 1 }
            } else {
                blankRun = 0
            }
        }
        if spacing > 0 {
            findings.append(Finding(problem: String(localized: "Blank lines are used for spacing in \(spacing) places."),
                                    fix: String(localized: "Use paragraph spacing or page breaks instead; screen readers announce each blank line.")))
        }

        let unclear: Set<String> = ["click here", "here", "link", "more", "read more", "this", "this link"]
        let links = matches(#"<w:hyperlink\b.*?</w:hyperlink>"#, in: document).map { text(of: $0).lowercased().trimmingCharacters(in: .whitespaces) }
        let vague = links.filter { unclear.contains($0) || $0.hasPrefix("http") }.count
        if vague > 0 {
            findings.append(Finding(problem: vague == 1 ? String(localized: "1 link has unclear text.") : String(localized: "\(vague) links have unclear text."),
                                    fix: String(localized: "Make each link say where it goes, such as \"2026 price list\", rather than \"click here\" or a web address.")))
        }
        return findings
    }

    /// Heading level for each paragraph style ID. The IDs are translated in non-English
    /// Word ("berschrift1", "Titre1"), but the style names inside are always English.
    static func headingLevels(_ styles: String) -> [String: Int] {
        var levels: [String: Int] = [:]
        for style in matches(#"<w:style\b[^>]*w:styleId="[^"]+"[^>]*>.*?</w:style>"#, in: styles) {
            guard let id = first(#"w:styleId="([^"]+)""#, in: style), let name = first(#"<w:name w:val="([^"]+)""#, in: style)?.lowercased()
            else { continue }
            if name == "title" { levels[id] = 0 }
            else if name.hasPrefix("heading "), let level = Int(name.dropFirst(8)) { levels[id] = level }
            else if let outline = first(#"<w:outlineLvl w:val="(\d)""#, in: style), let level = Int(outline) { levels[id] = level + 1 }
        }
        return levels
    }

    // MARK: PDF

    static func checkPDF(_ pdf: PDFDocument) -> [Finding] {
        var findings: [Finding] = []
        // Read tags and language from the document catalog: searching the file's bytes
        // misses them in compressed or large PDFs.
        var structure: CGPDFDictionaryRef?, language: CGPDFStringRef?
        let catalog = pdf.documentRef?.catalog
        let tagged = catalog.map { CGPDFDictionaryGetDictionary($0, "StructTreeRoot", &structure) } ?? false
        let hasLanguage = catalog.map { CGPDFDictionaryGetString($0, "Lang", &language) } ?? false
        let characters = (pdf.string ?? "").filter { !$0.isWhitespace }.count
        if pdf.pageCount > 0 && characters < 20 * pdf.pageCount {
            findings.append(Finding(problem: String(localized: "There is little or no text: this is probably a scanned picture of pages."),
                                    fix: String(localized: "Ask for the original document, or run text recognition, for example with Scan and Read, Preview or Adobe Acrobat.")))
        }
        let title = (pdf.documentAttributes?[PDFDocumentAttribute.titleAttribute] as? String)?.trimmingCharacters(in: .whitespaces) ?? ""
        if title.isEmpty {
            findings.append(Finding(problem: String(localized: "The PDF has no title."),
                                    fix: String(localized: "Set the title in the program that made the PDF, or in Acrobat under File, Properties.")))
        }
        if !tagged {
            findings.append(Finding(problem: String(localized: "The PDF isn't tagged."),
                                    fix: String(localized: "Without tags, screen readers can't tell headings, lists and tables apart. Export it again with \"Best for accessibility\" or tagged PDF turned on.")))
        }
        if !hasLanguage {
            findings.append(Finding(problem: String(localized: "The PDF doesn't say what language it is in."),
                                    fix: String(localized: "Set the document language, so screen readers use the right voice and pronunciation.")))
        }
        if pdf.pageCount > 8 && (pdf.outlineRoot?.numberOfChildren ?? 0) == 0 {
            findings.append(Finding(problem: String(localized: "This long PDF has no bookmarks."),
                                    fix: String(localized: "Bookmarks, usually made from headings, let people jump to each section.")))
        }
        return findings
    }

    // MARK: Text helpers

    private static func matches(_ pattern: String, in text: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]) else { return [] }
        return regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap { Range($0.range, in: text).map { String(text[$0]) } }
    }

    private static func first(_ pattern: String, in text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range(at: 1), in: text) else { return nil }
        return String(text[range])
    }

    /// The visible text of a piece of Word XML.
    private static func text(of xml: String) -> String {
        matches(#"<w:t(?: [^>]*)?>[^<]*</w:t>"#, in: xml).map { $0.replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression) }.joined()
    }

    /// A spoken summary.
    static func summary(_ findings: [Finding], name: String) -> String {
        if findings.isEmpty { return String(localized: "\(name): no accessibility problems found.") }
        let list = findings.map(\.problem).joined(separator: " ")
        return findings.count == 1 ? String(localized: "\(name): 1 problem. \(list)") : String(localized: "\(name): \(findings.count) problems. \(list)")
    }
}

/// Reads the files in a zip archive, such as a .docx, into memory.
enum Zip {
    /// `only` limits it to the files needed, so pictures in a big document aren't unpacked.
    static func entries(of url: URL, only wanted: Set<String>? = nil) -> [String: Data]? {
        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe) else { return nil }
        return entries(data, only: wanted)
    }

    static func entries(_ data: Data, only wanted: Set<String>? = nil) -> [String: Data]? {
        let bytes = [UInt8](data)
        func u16(_ i: Int) -> Int { i + 1 < bytes.count ? Int(bytes[i]) | Int(bytes[i + 1]) << 8 : 0 }
        func u32(_ i: Int) -> Int { u16(i) | u16(i + 2) << 16 }
        // The end of central directory record is in the last 64 KB.
        guard bytes.count > 22, let end = stride(from: bytes.count - 22, through: max(0, bytes.count - 65_558), by: -1)
            .first(where: { u32($0) == 0x0605_4b50 }) else { return nil }
        var offset = u32(end + 16)
        var files: [String: Data] = [:]
        for _ in 0..<u16(end + 10) {
            // A damaged file can point past its end; stop rather than read outside it.
            guard offset + 46 <= bytes.count, u32(offset) == 0x0201_4b50 else { break }
            let method = u16(offset + 10), compressed = u32(offset + 20), size = u32(offset + 24)
            let nameLength = u16(offset + 28), extraLength = u16(offset + 30), commentLength = u16(offset + 32)
            let local = u32(offset + 42)
            guard offset + 46 + nameLength <= bytes.count else { break }
            let name = String(decoding: bytes[(offset + 46)..<(offset + 46 + nameLength)], as: UTF8.self)
            offset += 46 + nameLength + extraLength + commentLength
            if let wanted, !wanted.contains(name) { continue }
            guard local + 30 <= bytes.count else { continue }
            let start = local + 30 + u16(local + 26) + u16(local + 28)
            guard start + compressed <= bytes.count, size < 200_000_000 else { continue }
            let stored = Array(bytes[start..<(start + compressed)])
            switch method {
            case 0: files[name] = Data(stored)
            case 8: files[name] = inflate(stored, size: size)
            default: continue
            }
        }
        return files
    }

    /// Raw deflate, as zip files use it.
    private static func inflate(_ input: [UInt8], size: Int) -> Data? {
        guard size > 0 else { return Data() }
        var output = [UInt8](repeating: 0, count: size)
        let written = compression_decode_buffer(&output, size, input, input.count, nil, COMPRESSION_ZLIB)
        return written == size ? Data(output) : nil
    }
}

final class DocumentCheckModel: ObservableObject {
    static let shared = DocumentCheckModel()
    @Published var name = ""
    @Published var findings: [DocumentCheck.Finding] = []
    @Published var checked = false

    @MainActor
    func choose() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "docx") ?? .data, .pdf]
        panel.message = String(localized: "Choose a Word document or PDF to check")
        NSApp.activate()
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Announcer.say(String(localized: "Checking"))
        DispatchQueue.global(qos: .userInitiated).async {
            let findings = DocumentCheck.check(url)
            DispatchQueue.main.async {
                self.name = url.lastPathComponent
                guard let findings else {
                    self.checked = false
                    return Announcer.say(String(localized: "That file couldn't be read. Choose a .docx Word document or a PDF."))
                }
                self.findings = findings
                self.checked = true
                Announcer.say(DocumentCheck.summary(findings, name: url.deletingPathExtension().lastPathComponent))
            }
        }
    }
}

struct DocumentCheckView: View {
    @ObservedObject var model = DocumentCheckModel.shared

    var body: some View {
        Form {
            Section {
                Button(String(localized: "Choose a Document…")) { model.choose() }
                Text(String(localized: "Checks a Word document (.docx) or PDF for problems that make it hard to read with a screen reader. The document is checked on your Mac and isn't sent anywhere."))
                    .font(.caption).foregroundStyle(.secondary)
            }
            if model.checked {
                Section(model.findings.isEmpty ? String(localized: "\(model.name): no problems found")
                                               : String(localized: "\(model.name): \(model.findings.count) problems")) {
                    ForEach(model.findings) { finding in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(finding.problem).font(.headline)
                            Text(finding.fix)
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 540, height: 480)
    }
}
