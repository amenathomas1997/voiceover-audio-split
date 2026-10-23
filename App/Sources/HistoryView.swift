// HistoryView.swift — the Speech History window: what VoiceOver said recently,
// newest first, with buttons to copy one phrase or everything.

import AppKit
import SwiftUI

struct HistoryView: View {
    @ObservedObject var history = SpeechHistory.shared
    @ObservedObject var preferences = Preferences.shared
    @State private var selection: SpokenPhrase.ID?

    private static let timeFormat: DateFormatter = {
        let format = DateFormatter()
        format.timeStyle = .medium
        return format
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !preferences.speechHistory {
                Text(String(localized: "Speech history is off. Turn it on in Settings, or here."))
                Toggle(String(localized: "Keep speech history"), isOn: $preferences.speechHistory)
            } else if history.phrases.isEmpty {
                Text(String(localized: "Nothing yet. What VoiceOver says will appear here, newest first."))
            }
            List(history.phrases, selection: $selection) { phrase in
                Text(phrase.text)
                    .accessibilityLabel("\(phrase.text), \(Self.timeFormat.string(from: phrase.time))")
            }
            .accessibilityLabel(String(localized: "Speech history, newest first"))
            HStack {
                Button(String(localized: "Copy selected")) { copy(history.phrases.filter { $0.id == selection }) }
                    .disabled(selection == nil)
                Button(String(localized: "Copy all")) { copy(history.phrases.reversed()) }
                    .disabled(history.phrases.isEmpty)
                Spacer()
                Button(String(localized: "Clear")) { history.clear() }
                    .disabled(history.phrases.isEmpty)
            }
            Text(String(localized: "Kept in memory only, never saved to disk. Includes this app's own announcements."))
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding()
        .frame(width: 520, height: 520)
    }

    private func copy(_ phrases: [SpokenPhrase]) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(phrases.map(\.text).joined(separator: "\n"), forType: .string)
        Announcer.say(phrases.count == 1 ? String(localized: "Copied") : String(localized: "Copied \(phrases.count) phrases"))
    }
}
