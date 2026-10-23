// TextTools.swift — two text checks VoiceOver users miss:
//   * Compare text: hear exactly what changed between two versions (for
//     example after Writing Tools proofreading, which VoiceOver can't review).
//     Copy the original and press the compare key, then copy the new version
//     and press it again.
//   * Text Checker: every formatting problem in the clipboard text with the
//     sentence it is in, to step through one by one (VoiceOver's own Text
//     Checker can't find formatting errors or say where a problem is).

import AppKit
import NaturalLanguage
import SwiftUI

// MARK: - Comparing

struct TextChange: Identifiable, Equatable {
    enum Kind: Equatable {
        case changed(from: String, to: String)
        case added(String)
        case removed(String)
    }

    let id = UUID()
    let kind: Kind
    /// 1-based sentence number in the new text (the old text for removals at the end).
    let sentence: Int

    var spoken: String {
        switch kind {
        case .changed(let from, let to): "Sentence \(sentence): changed \"\(from)\" to \"\(to)\""
        case .added(let words): "Sentence \(sentence): added \"\(words)\""
        case .removed(let words): "Sentence \(sentence): removed \"\(words)\""
        }
    }

    static func == (lhs: TextChange, rhs: TextChange) -> Bool { lhs.kind == rhs.kind && lhs.sentence == rhs.sentence }
}

enum TextCompare {
    /// Word-by-word differences between two versions, grouped into changes.
    static func changes(from old: String, to new: String) -> [TextChange] {
        let a = old.split(whereSeparator: \.isWhitespace).map(String.init)
        let b = new.split(whereSeparator: \.isWhitespace).map(String.init)
        let difference = b.difference(from: a)
        var removed = Set<Int>(), inserted = Set<Int>()
        for change in difference {
            switch change {
            case .remove(let offset, _, _): removed.insert(offset)
            case .insert(let offset, _, _): inserted.insert(offset)
            }
        }

        var changes: [TextChange] = []
        var i = 0, j = 0
        while i < a.count || j < b.count {
            if i < a.count && j < b.count && !removed.contains(i) && !inserted.contains(j) {
                i += 1
                j += 1
                continue
            }
            var gone: [String] = [], added: [String] = []
            let sentence = sentenceNumber(of: j, in: b)
            while i < a.count && removed.contains(i) { gone.append(a[i]); i += 1 }
            while j < b.count && inserted.contains(j) { added.append(b[j]); j += 1 }
            let kind: TextChange.Kind? = switch (gone.isEmpty, added.isEmpty) {
            case (false, false): .changed(from: gone.joined(separator: " "), to: added.joined(separator: " "))
            case (true, false): .added(added.joined(separator: " "))
            case (false, true): .removed(gone.joined(separator: " "))
            case (true, true): nil
            }
            if let kind { changes.append(TextChange(kind: kind, sentence: sentence)) }
            if gone.isEmpty && added.isEmpty { break } // Safety: nothing consumed.
        }
        return changes
    }

    /// The sentence a word starts, counting sentence-ending punctuation before it.
    private static func sentenceNumber(of index: Int, in words: [String]) -> Int {
        1 + words.prefix(index).filter { word in [".", "!", "?"].contains { word.hasSuffix($0) } }.count
    }

    static func summary(_ changes: [TextChange]) -> String {
        guard !changes.isEmpty else { return "No changes. The two versions are the same." }
        let count = "\(changes.count) \(changes.count == 1 ? "change" : "changes")"
        let spoken = changes.prefix(10).map(\.spoken).joined(separator: ". ")
        return "\(count). \(spoken)" + (changes.count > 10 ? ". And \(changes.count - 10) more in the window." : ".")
    }
}

final class CompareModel: ObservableObject {
    static let shared = CompareModel()

    @Published private(set) var original: String?
    @Published private(set) var changes: [TextChange] = []
    @Published private(set) var status = "Copy the original text, then choose Save Original."

    /// The compare key: the first press saves the original, the second compares.
    func step() {
        original == nil ? saveOriginal() : compare()
    }

    func saveOriginal() {
        guard let text = clipboardText() else { return }
        original = text
        changes = []
        report("Original saved. Copy the new version, then press the compare key again.")
    }

    func compare() {
        guard let original else { return report("Save the original first.") }
        guard let text = clipboardText() else { return }
        changes = TextCompare.changes(from: original, to: text)
        self.original = nil
        report(TextCompare.summary(changes))
    }

    func startOver() {
        original = nil
        changes = []
        report("Starting over. Copy the original text, then choose Save Original.")
    }

    private func clipboardText() -> String? {
        guard let text = NSPasteboard.general.string(forType: .string), !text.isEmpty else {
            report("Copy some text first.")
            return nil
        }
        return text
    }

    private func report(_ message: String) {
        status = message
        Announcer.say(message)
    }
}

struct CompareView: View {
    @ObservedObject var model = CompareModel.shared

    var body: some View {
        Form {
            Section {
                Text(model.status)
                HStack {
                    Button("Save Original") { model.saveOriginal() }
                    Button("Compare With Clipboard") { model.compare() }
                        .keyboardShortcut(.defaultAction)
                        .disabled(model.original == nil)
                    Button("Start Over") { model.startOver() }
                }
            }
            if !model.changes.isEmpty {
                Section("Changes") {
                    ForEach(model.changes) { Text($0.spoken).textSelection(.enabled) }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 560, height: 460)
    }
}

// MARK: - Text Checker

struct TextIssue: Identifiable {
    let id = UUID()
    let problem: String
    /// The sentence it is in, when the problem belongs to one sentence.
    let sentence: String?
    let sentenceNumber: Int?

    var spoken: String {
        guard let sentence, let sentenceNumber else { return problem }
        return "Sentence \(sentenceNumber): \(problem). \(sentence)"
    }
}

extension TextAnalyzer {
    /// Each problem with the sentence it is in, in reading order, then whole-text problems.
    static func issues(in text: String) -> [TextIssue] {
        var issues: [TextIssue] = []
        let checks: [(String, String)] = [
            ("[^ \\n] {2,}[^ \\n]", "double space"),
            (" [,.;:!?](\\s|$)", "space before punctuation"),
            ("(?i)\\b(\\w+)\\s+\\1\\b", "repeated word"),
        ]
        let tokenizer = NLTokenizer(unit: .sentence)
        tokenizer.string = text
        for (index, range) in tokenizer.tokens(for: text.startIndex..<text.endIndex).enumerated() {
            let sentence = String(text[range])
            for (pattern, problem) in checks where sentence.range(of: pattern, options: .regularExpression) != nil {
                issues.append(TextIssue(problem: problem, sentence: sentence.trimmingCharacters(in: .whitespacesAndNewlines),
                                        sentenceNumber: index + 1))
            }
        }
        // Problems that belong to the whole text rather than one sentence.
        let summary = analyze(text)
        for problem in ["unmatched parentheses", "unmatched square brackets", "unmatched braces", "unmatched curly quotes",
                        "odd number of straight quotes", "extra blank lines", "both tabs and spaces", "ending in a space"]
            where summary.contains(problem) {
            let detail = summary.components(separatedBy: ". ").first { $0.contains(problem) } ?? problem
            issues.append(TextIssue(problem: detail, sentence: nil, sentenceNumber: nil))
        }
        return issues
    }
}

final class TextCheckerModel: ObservableObject {
    static let shared = TextCheckerModel()

    @Published private(set) var issues: [TextIssue] = []
    @Published private(set) var current = 0
    @Published private(set) var summary = ""

    func checkClipboard() {
        guard let text = NSPasteboard.general.string(forType: .string), !text.isEmpty else {
            summary = "Copy some text first, then check it."
            return Announcer.say(summary)
        }
        issues = TextAnalyzer.issues(in: text)
        current = 0
        summary = TextAnalyzer.analyze(text)
        Announcer.say(issues.isEmpty ? summary
                      : "\(issues.count) \(issues.count == 1 ? "problem" : "problems"). First: \(issues[0].spoken)")
    }

    func step(_ delta: Int) {
        guard !issues.isEmpty else { return Announcer.say("No problems to step through") }
        let next = current + delta
        guard issues.indices.contains(next) else { return Announcer.say(delta > 0 ? "Last problem" : "First problem") }
        current = next
        Announcer.say("Problem \(current + 1) of \(issues.count). \(issues[current].spoken)")
    }
}

struct TextCheckerView: View {
    @ObservedObject var model = TextCheckerModel.shared

    var body: some View {
        Form {
            Section {
                Text(model.summary.isEmpty ? "Copy some text, then choose Check Clipboard." : model.summary)
                HStack {
                    Button("Check Clipboard") { model.checkClipboard() }.keyboardShortcut(.defaultAction)
                    Button("Previous Problem") { model.step(-1) }.keyboardShortcut(.upArrow, modifiers: .command)
                    Button("Next Problem") { model.step(1) }.keyboardShortcut(.downArrow, modifiers: .command)
                }
            }
            if !model.issues.isEmpty {
                Section("Problems") {
                    ForEach(Array(model.issues.enumerated()), id: \.element.id) { index, issue in
                        Text("\(index + 1). \(issue.spoken)").textSelection(.enabled)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 600, height: 520)
    }
}
