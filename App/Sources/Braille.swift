// Braille.swift — turns text into uncontracted (grade 1) Unified English Braille
// and saves it as a .brf file for embossers and braille notetakers, laid out in
// pages. BRF uses North American Braille ASCII: one character per braille cell.
// Contracted braille needs a full rule table (such as liblouis), so it isn't here yet.

import AppKit
import SwiftUI
import UniformTypeIdentifiers

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
    static func unsupported(in text: String) -> Int {
        text.folding(options: [.diacriticInsensitive], locale: Locale(identifier: "en")).filter { character in
            !(character.isASCII && (character.isLetter || character.isNumber)) && !character.isWhitespace
                && punctuation[character] == nil && character != "\""
        }.count
    }

    /// One line of text in Braille ASCII, uncontracted UEB.
    static func translate(_ text: String) -> String {
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
    static func brf(_ text: String, width: Int = 40, height: Int = 25) -> String {
        var lines: [String] = []
        for paragraph in text.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n") {
            let braille = translate(paragraph.trimmingCharacters(in: .whitespaces))
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

struct BrailleView: View {
    @State private var text = NSPasteboard.general.string(forType: .string) ?? ""
    @State private var width = 40
    @State private var height = 25

    var body: some View {
        Form {
            Section {
                TextEditor(text: $text)
                    .frame(minHeight: 160)
                    .accessibilityLabel(String(localized: "Text to put in braille"))
                Stepper(String(localized: "Cells per line: \(width)"), value: $width, in: 20...42)
                Stepper(String(localized: "Lines per page: \(height)"), value: $height, in: 10...30)
                Button(String(localized: "Save as Braille File…")) { save() }
                    .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                Text(String(localized: "Uncontracted (grade 1) Unified English Braille, as a .brf file for embossers and notetakers. The text starts as what's on the clipboard."))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section(String(localized: "Preview")) {
                Text(Braille.unicode(Braille.translate(String(text.prefix(400)))))
                    .textSelection(.enabled)
            }
        }
        .formStyle(.grouped)
        .frame(width: 520, height: 520)
    }

    private func save() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = String(localized: "Braille.brf")
        panel.allowedContentTypes = [UTType(filenameExtension: "brf") ?? .plainText]
        NSApp.activate()
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try Braille.brf(text, width: width, height: height).write(to: url, atomically: true, encoding: .ascii)
            let missing = Braille.unsupported(in: text)
            Announcer.say(String(localized: "Saved \(url.lastPathComponent)")
                          + (missing > 0 ? " " + String(localized: "\(missing) characters have no braille here and were left out.") : ""))
        } catch {
            Announcer.say(String(localized: "Couldn't save the braille file"))
        }
    }
}
