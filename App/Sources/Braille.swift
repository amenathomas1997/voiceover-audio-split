// Braille.swift — turns text into Unified English Braille, uncontracted (grade 1)
// or contracted (grade 2), and saves it as a .brf file for embossers and braille
// notetakers, laid out in pages. BRF uses North American Braille ASCII: one
// character per braille cell. Uncontracted braille is translated here; contracted
// braille uses liblouis (App/Vendor/liblouis, LGPL) and its UEB tables, which are
// bundled in Resources/BrailleTables.

import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Uncontracted (grade 1) or contracted (grade 2) braille.
enum BrailleGrade: String, CaseIterable, Identifiable {
    case uncontracted, contracted

    var id: String { rawValue }

    var title: String {
        switch self {
        case .uncontracted: String(localized: "Uncontracted (grade 1)")
        case .contracted: String(localized: "Contracted (grade 2)")
        }
    }
}

enum Braille {
    /// Braille ASCII characters in order of their dot pattern (dot 1 = 1, dot 2 = 2 … dot 6 = 32).
    private static let asciiByDots = Array(" a1b'k2l@cif/msp\"e3h9o6r^djg>ntq,*5<-u8v.%[$+x!&;:4\\0z7(_?w]#y)=")

    private static let punctuation: [Character: String] = [
        ".": "4", ",": "1", ";": "2", ":": "3", "!": "6", "?": "8", "'": "'", "\u{2019}": "'", "\u{2018}": "'",
        "-": "-", "\u{2013}": ",-", "\u{2014}": ",-", "(": "\"<", ")": "\">", "[": ".<", "]": ".>", "/": "_/",
        "&": "@&", "@": "@a", "#": "_?", "$": "@s", "%": ".0", "*": "\"9", "+": "\"6", "=": "\"7",
        "\u{201C}": "8", "\u{201D}": "0", "\u{2026}": "444",
        "_": ".-", "<": "@<", ">": "@>", "~": "@9", "^": "@5", "\\": "_*", "|": "_\\", "{": "_<", "}": "_>", "`": "@*",
    ]

    /// Characters that have no braille here, such as letters from other alphabets.
    static func unsupported(in text: String, grade: BrailleGrade = .uncontracted) -> Int {
        if grade == .contracted, let count = Louis.unsupported(in: text) { return count }
        return text.folding(options: [.diacriticInsensitive], locale: Locale(identifier: "en")).filter { character in
            !(character.isASCII && (character.isLetter || character.isNumber)) && !character.isWhitespace
                && punctuation[character] == nil && character != "\""
        }.count
    }

    /// Whether contracted braille is available (the bundled tables were found).
    static var canContract: Bool { Louis.isAvailable }

    /// One line of text in Braille ASCII, uncontracted or contracted UEB.
    /// Contracted braille falls back to uncontracted if liblouis can't translate it.
    static func translate(_ text: String, grade: BrailleGrade = .uncontracted) -> String {
        if grade == .contracted, let braille = Louis.translate(text) { return braille }
        var output = ""
        // Tabs and other spaces separate words too.
        let words = text.folding(options: [.diacriticInsensitive], locale: Locale(identifier: "en"))
            .map { $0.isWhitespace ? " " : $0 }.split(separator: " ", omittingEmptySubsequences: false)
        for (index, word) in words.enumerated() {
            if index > 0 { output += " " }
            output += translate(word: String(word))
        }
        return output
    }

    private static func translate(word: String) -> String {
        let letters = word.filter(\.isLetter)
        let allCaps = letters.count > 1 && letters.allSatisfy(\.isUppercase)
        var output = allCaps ? ",," : ""
        var inNumber = false
        let characters = Array(word)
        for (i, character) in characters.enumerated() {
            if let digit = character.wholeNumberValue, character.isASCII {
                if !inNumber { output += "#" }
                inNumber = true
                output += String("jabcdefghi"[String.Index(utf16Offset: digit, in: "jabcdefghi")])
                continue
            }
            let nextIsDigit = i + 1 < characters.count && characters[i + 1].isNumber
            if inNumber && (character == "." || character == ",") && nextIsDigit {
                output += character == "." ? "4" : "1"
                continue
            }
            if character.isLetter, character.isASCII {
                // After a number, letters a to j would read as digits: end the number first.
                // (A capital sign ends the number by itself.)
                if inNumber && character.isLowercase && "abcdefghij".contains(character) { output += ";" }
                inNumber = false
                if character.isUppercase && !allCaps { output += "," }
                output += character.lowercased()
                continue
            }
            inNumber = false
            if character == "\"" {
                // Opening at the start of a word, closing anywhere else.
                output += i == 0 || "([".contains(characters[i - 1]) ? "8" : "0"
            } else if let mark = punctuation[character] {
                output += mark
            }
        }
        return output
    }

    /// Braille pages for a .brf file: lines of at most `width` cells, `height` lines a
    /// page with the page number at the top right, pages separated by form feeds.
    static func brf(_ text: String, grade: BrailleGrade = .uncontracted, width: Int = 40, height: Int = 25) -> String {
        var lines: [String] = []
        for paragraph in text.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n") {
            let braille = translate(paragraph.trimmingCharacters(in: .whitespaces), grade: grade)
            if braille.isEmpty { lines.append(""); continue }
            var line = ""
            for word in braille.split(separator: " ") {
                var word = String(word)
                while word.count > width {
                    if !line.isEmpty { lines.append(line); line = "" }
                    lines.append(String(word.prefix(width - 1)) + "-")
                    word = String(word.dropFirst(width - 1))
                }
                if line.isEmpty { line = word }
                else if line.count + 1 + word.count <= width { line += " " + word }
                else { lines.append(line); line = word }
            }
            lines.append(line)
        }
        let perPage = max(height - 1, 1)
        var pages: [String] = []
        for (index, start) in stride(from: 0, to: max(lines.count, 1), by: perPage).enumerated() {
            let number = translate(String(index + 1))
            let header = String(repeating: " ", count: max(width - number.count, 0)) + number
            pages.append(([header] + lines[start..<min(start + perPage, lines.count)]).joined(separator: "\r\n"))
        }
        return pages.joined(separator: "\r\n\u{0C}")
    }

    /// Braille ASCII for dot patterns from liblouis (Unicode braille cells); dots 7
    /// and 8 have no place in a .brf file and are dropped.
    fileprivate static func ascii(dots: UInt16) -> Character {
        asciiByDots[Int(dots & 0x3F)]
    }

    /// Braille ASCII as Unicode braille cells, to show on screen and on braille displays.
    static func unicode(_ ascii: String) -> String {
        String(ascii.map { character -> Character in
            if let dots = asciiByDots.firstIndex(of: Character(character.lowercased())) {
                return Character(UnicodeScalar(0x2800 + dots)!)
            }
            return character
        })
    }
}

/// Contracted UEB through liblouis. liblouis isn't thread safe, so every call goes
/// through one serial queue.
private enum Louis {
    private static let queue = DispatchQueue(label: "com.fullcircleat.VoiceOverAudioSplit.liblouis")

    /// The bundled tables, by absolute path, so they are found inside the sandbox
    /// without a search path. liblouis finds included tables next to the first one.
    /// A comma separates tables in liblouis's table lists, so a path with one can't be used.
    private static let tables: (contracted: String, uncontracted: String)? = {
        guard let folder = Bundle.main.url(forResource: "BrailleTables", withExtension: nil)?.path,
              !folder.contains(",") else { return nil }
        queue.sync { lou_setLogLevel(LOU_LOG_ERROR) }
        return (folder + "/en-ueb-g2.ctb", folder + "/en-ueb-g1.ctb")
    }()

    static var isAvailable: Bool { tables != nil }

    /// Whether each character can be put in braille, worked out once per character.
    private static var known: [Character: Bool] = [:]

    /// Dot patterns as Unicode braille, leaving out characters the tables don't know.
    private static let mode = Int32(ucBrl.rawValue | dotsIO.rawValue | noUndefined.rawValue)

    static func translate(_ text: String) -> String? {
        guard let table = tables?.contracted else { return nil }
        // Tabs and other spaces separate words, like in uncontracted braille.
        let input = Array(String(text.map { $0.isWhitespace ? " " : $0 }).utf16)
        if input.isEmpty { return "" }
        return queue.sync { run(table, input) }
    }

    /// Characters in the text that the tables have no braille for.
    static func unsupported(in text: String) -> Int? {
        guard let table = tables?.uncontracted else { return nil }
        return queue.sync {
            text.filter { character in
                if character.isWhitespace { return false }
                if let isKnown = known[character] { return !isKnown }
                let isKnown = run(table, Array(String(character).utf16)).map { !$0.isEmpty } ?? false
                known[character] = isKnown
                return !isKnown
            }.count
        }
    }

    /// Runs liblouis on the queue, making the output room bigger until everything fits.
    private static func run(_ table: String, _ input: [UInt16]) -> String? {
        dispatchPrecondition(condition: .onQueue(queue))
        var room = input.count * 2 + 64
        while room <= input.count * 64 + 1024 {
            var inLength = Int32(input.count)
            var outLength = Int32(room)
            var output = [UInt16](repeating: 0, count: room)
            let ok = lou_translateString(table, input, &inLength, &output, &outLength, nil, nil, mode)
            guard ok == 1 else { return nil }
            if inLength >= Int32(input.count) && outLength < Int32(room) {
                return String(output.prefix(Int(outLength)).map { cell -> Character in
                    cell & 0xFF00 == 0x2800 ? Braille.ascii(dots: cell) : " "
                })
            }
            room *= 4
        }
        return nil
    }
}

struct BrailleView: View {
    @State private var text = BrailleView.clipboardText()
    @State private var width = 40
    @State private var height = 25
    @State private var preview = ""
    @State private var saving = false
    @AppStorage("brailleGrade") private var grade: BrailleGrade = .contracted

    /// What's on the clipboard, unless it was marked as not to be shown (a password manager's copy).
    static func clipboardText() -> String {
        let board = NSPasteboard.general
        let concealed = ["org.nspasteboard.ConcealedType", "org.nspasteboard.TransientType"].map { NSPasteboard.PasteboardType($0) }
        if board.types?.contains(where: concealed.contains) == true { return "" }
        return board.string(forType: .string) ?? ""
    }

    var body: some View {
        Form {
            Section {
                TextEditor(text: $text)
                    .frame(minHeight: 160)
                    .accessibilityLabel(String(localized: "Text to put in braille"))
                Picker(String(localized: "Braille grade"), selection: $grade) {
                    ForEach(BrailleGrade.allCases) { Text($0.title).tag($0) }
                }
                Stepper(String(localized: "Cells per line: \(width)"), value: $width, in: 20...42)
                Stepper(String(localized: "Lines per page: \(height)"), value: $height, in: 10...30)
                Button(String(localized: "Save as Braille File…")) { save() }
                    .disabled(saving || text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                Text(String(localized: "Unified English Braille, as a .brf file for embossers and notetakers. The text starts as what's on the clipboard."))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section(String(localized: "Preview")) {
                Text(preview)
                    .textSelection(.enabled)
            }
        }
        .formStyle(.grouped)
        .frame(width: 520, height: 520)
        // Translating (and loading the tables the first time) happens off the main thread,
        // which also carries the keyboard shortcuts: typing stays smooth.
        .task(id: "\(grade.rawValue)|\(text.prefix(400))") {
            let sample = String(text.prefix(400)), grade = grade
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            preview = await Task.detached { Braille.unicode(Braille.translate(sample, grade: grade)) }.value
        }
    }

    private func save() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = String(localized: "Braille.brf")
        panel.allowedContentTypes = [UTType(filenameExtension: "brf") ?? .plainText]
        NSApp.activate()
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let (text, grade, width, height) = (text, grade, width, height)
        saving = true
        Task.detached {
            let result = Result { try Braille.brf(text, grade: grade, width: width, height: height).write(to: url, atomically: true, encoding: .ascii) }
            let missing = Braille.unsupported(in: text, grade: grade)
            let uncontracted = grade == .contracted && !Braille.canContract
            await MainActor.run {
                saving = false
                switch result {
                case .success:
                    var said = String(localized: "Saved \(url.lastPathComponent)")
                    if uncontracted { said += " " + String(localized: "Contracted braille isn't available on this Mac, so the file is uncontracted.") }
                    if missing > 0 { said += " " + String(localized: "\(missing) characters have no braille here and were left out.") }
                    Announcer.say(said)
                case .failure:
                    Announcer.say(String(localized: "Couldn't save the braille file"))
                }
            }
        }
    }
}
