// DocReader.swift — a large-print reading window, like SuperNova's Doc Reader:
// text is shown in big, high-contrast type and read aloud, with the word being
// spoken highlighted. Step by sentence or paragraph; open text, Word, RTF, HTML
// and PDF files, or read the clipboard.

import AVFoundation
import NaturalLanguage
import PDFKit
import SwiftUI
import UniformTypeIdentifiers

extension ReadingTheme {
    var foreground: Color {
        switch self {
        case .blackOnWhite, .blackOnYellow: .black
        case .whiteOnBlack: .white
        case .yellowOnBlack: .yellow
        }
    }

    var background: Color {
        switch self {
        case .blackOnWhite: .white
        case .whiteOnBlack, .yellowOnBlack: .black
        case .blackOnYellow: .yellow
        }
    }

    /// Highlight for the word being spoken: the reverse of the text colors.
    var highlightForeground: Color { background }
    var highlightBackground: Color { foreground }
}

/// Splits text into paragraphs and sentences, as UTF-16 ranges of the whole text.
struct TextLayout {
    let paragraphs: [NSRange]
    let sentences: [NSRange]

    init(_ text: String) {
        let ns = text as NSString
        var paragraphs: [NSRange] = []
        ns.enumerateSubstrings(in: NSRange(location: 0, length: ns.length), options: .byParagraphs) { value, range, _, _ in
            if let value, !value.trimmingCharacters(in: .whitespaces).isEmpty { paragraphs.append(range) }
        }
        self.paragraphs = paragraphs
        let tokenizer = NLTokenizer(unit: .sentence)
        tokenizer.string = text
        sentences = tokenizer.tokens(for: text.startIndex..<text.endIndex).map { NSRange($0, in: text) }
    }

    /// The start of the range after (or before) the one containing `offset`.
    static func step(_ ranges: [NSRange], from offset: Int, by delta: Int) -> Int? {
        guard !ranges.isEmpty else { return nil }
        let current = ranges.lastIndex { $0.location <= offset } ?? 0
        let target = current + delta
        guard ranges.indices.contains(target) else { return nil }
        return ranges[target].location
    }
}

final class DocReaderModel: NSObject, ObservableObject, AVSpeechSynthesizerDelegate {
    static let shared = DocReaderModel()

    @Published private(set) var text = ""
    @Published private(set) var layout = TextLayout("")
    /// The word being spoken, in the whole text.
    @Published private(set) var highlight: NSRange?
    @Published private(set) var speaking = false
    @Published private(set) var paused = false

    private let synthesizer = AVSpeechSynthesizer()
    /// Where the current utterance starts in the whole text.
    private var utteranceStart = 0
    /// Where reading would continue from.
    private var position = 0

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    func load(_ newText: String) {
        stop()
        text = newText
        layout = TextLayout(newText)
        position = 0
        highlight = nil
    }

    func loadClipboard() {
        guard let string = NSPasteboard.general.string(forType: .string), !string.isEmpty else {
            return Announcer.say("The clipboard has no text")
        }
        load(string)
        Announcer.say("Clipboard loaded. \(layout.paragraphs.count) paragraphs.")
    }

    /// Reads a text, Word, RTF, HTML or PDF file chosen by the user.
    func open(_ url: URL) {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        var loaded: String?
        if url.pathExtension.lowercased() == "pdf" {
            loaded = PDFDocument(url: url)?.string
        } else {
            loaded = try? NSAttributedString(url: url, options: [:], documentAttributes: nil).string
        }
        guard let loaded, !loaded.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return Announcer.say("No text found in \(url.lastPathComponent). For scanned pages, use Scan and Read.")
        }
        load(loaded)
        Announcer.say("\(url.deletingPathExtension().lastPathComponent) loaded. \(layout.paragraphs.count) paragraphs.")
    }

    // MARK: Speaking

    func togglePlay() {
        if speaking && !paused {
            synthesizer.pauseSpeaking(at: .word)
            paused = true
        } else if paused {
            synthesizer.continueSpeaking()
            paused = false
        } else {
            play(from: position)
        }
    }

    func play(from offset: Int) {
        let ns = text as NSString
        guard offset < ns.length else { return }
        synthesizer.stopSpeaking(at: .immediate)
        utteranceStart = offset
        position = offset
        let utterance = AVSpeechUtterance(string: ns.substring(from: offset))
        let rate = Float(Preferences.shared.readerRate)
        utterance.rate = AVSpeechUtteranceMinimumSpeechRate
            + (AVSpeechUtteranceMaximumSpeechRate - AVSpeechUtteranceMinimumSpeechRate) * rate
        speaking = true
        paused = false
        synthesizer.speak(utterance)
    }

    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
        speaking = false
        paused = false
    }

    func step(sentences delta: Int) { jump(TextLayout.step(layout.sentences, from: position, by: delta)) }
    func step(paragraphs delta: Int) { jump(TextLayout.step(layout.paragraphs, from: position, by: delta)) }

    private func jump(_ offset: Int?) {
        guard let offset else { return Announcer.say("No more") }
        position = offset
        if speaking && !paused { play(from: offset) } else { highlight = NSRange(location: offset, length: 0) }
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, willSpeakRangeOfSpeechString range: NSRange,
                           utterance: AVSpeechUtterance) {
        let word = NSRange(location: utteranceStart + range.location, length: range.length)
        DispatchQueue.main.async {
            self.highlight = word
            self.position = word.location
        }
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        DispatchQueue.main.async {
            self.speaking = false
            self.position = 0
        }
    }
}

struct DocReaderView: View {
    @ObservedObject var model = DocReaderModel.shared
    @ObservedObject var preferences = Preferences.shared
    @State private var choosingFile = false

    var body: some View {
        VStack(spacing: 0) {
            controls.padding(10)
            ScrollViewReader { scroll in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: CGFloat(preferences.readerLineSpacing) * 2) {
                        if model.text.isEmpty {
                            Text("Paste text from the clipboard or open a file to start reading.")
                                .font(.system(size: CGFloat(preferences.readerFontSize)))
                        }
                        ForEach(Array(model.layout.paragraphs.enumerated()), id: \.offset) { index, range in
                            Text(paragraph(range))
                                .font(.system(size: CGFloat(preferences.readerFontSize)))
                                .lineSpacing(CGFloat(preferences.readerLineSpacing))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .id(index)
                        }
                    }
                    .padding(24)
                }
                .onChange(of: model.highlight) { _, highlight in
                    guard let highlight,
                          let index = model.layout.paragraphs.lastIndex(where: { $0.location <= highlight.location })
                    else { return }
                    withAnimation { scroll.scrollTo(index, anchor: .center) }
                }
            }
            .foregroundStyle(preferences.readingTheme.foreground)
            .background(preferences.readingTheme.background)
        }
        .frame(minWidth: 640, minHeight: 520)
        .fileImporter(isPresented: $choosingFile,
                      allowedContentTypes: [.plainText, .rtf, .pdf, .html, UTType(filenameExtension: "docx") ?? .data]) {
            if case .success(let url) = $0 { model.open(url) }
        }
    }

    private var controls: some View {
        HStack {
            Button(model.speaking && !model.paused ? "Pause" : "Read") { model.togglePlay() }
                .keyboardShortcut(.return, modifiers: .command)
            Button("Previous Sentence") { model.step(sentences: -1) }
                .keyboardShortcut(.leftArrow, modifiers: .command)
            Button("Next Sentence") { model.step(sentences: 1) }
                .keyboardShortcut(.rightArrow, modifiers: .command)
            Button("Previous Paragraph") { model.step(paragraphs: -1) }
                .keyboardShortcut(.upArrow, modifiers: .command)
            Button("Next Paragraph") { model.step(paragraphs: 1) }
                .keyboardShortcut(.downArrow, modifiers: .command)
            Spacer()
            Button("Paste Clipboard") { model.loadClipboard() }
                .keyboardShortcut("v", modifiers: [.command, .shift])
            Button("Open File…") { choosingFile = true }
                .keyboardShortcut("o", modifiers: .command)
            Menu("Display") {
                Picker("Colors", selection: $preferences.readingTheme) {
                    ForEach(ReadingTheme.allCases) { Text($0.title).tag($0) }
                }
                Stepper("Text size: \(preferences.readerFontSize)", value: $preferences.readerFontSize, in: 14...96, step: 4)
                Stepper("Line spacing: \(preferences.readerLineSpacing)", value: $preferences.readerLineSpacing, in: 0...40, step: 2)
            }
            .frame(width: 100)
            Slider(value: $preferences.readerRate, in: 0.1...0.9) { Text("Reading speed") }
                .frame(width: 160)
        }
    }

    /// One paragraph, with the word being spoken shown in reversed colors.
    private func paragraph(_ range: NSRange) -> AttributedString {
        let string = (model.text as NSString).substring(with: range)
        var attributed = AttributedString(string)
        guard let highlight = model.highlight, highlight.length > 0,
              NSLocationInRange(highlight.location, range) else { return attributed }
        let local = NSRange(location: highlight.location - range.location,
                            length: min(highlight.length, range.length - (highlight.location - range.location)))
        if let stringRange = Range(local, in: string),
           let start = AttributedString.Index(stringRange.lowerBound, within: attributed),
           let end = AttributedString.Index(stringRange.upperBound, within: attributed) {
            attributed[start..<end].foregroundColor = preferences.readingTheme.highlightForeground
            attributed[start..<end].backgroundColor = preferences.readingTheme.highlightBackground
        }
        return attributed
    }
}
