// AudioHub.swift — one keyboard-friendly place to find and play audio, like
// SuperNova Connect:
//   * Radio: internet radio stations from the free Radio Browser directory
//   * Podcasts: Apple's podcast directory, then each show's episodes
//   * Audiobooks: free public-domain books from LibriVox, chapter by chapter
//   * News: headlines from RSS feeds, read aloud
// No accounts or keys. The hub plays through this app, whose own sound can't be
// captured (that would feed back), so it isn't moved by the split; it does go
// quiet in quiet mode and follows the speech and other-sounds balance.

import AVFoundation
import SwiftUI

enum HubSource: String, CaseIterable, Identifiable {
    case radio, podcasts, audiobooks, news

    var id: String { rawValue }

    var title: String {
        switch self {
        case .radio: String(localized: "Radio")
        case .podcasts: String(localized: "Podcasts")
        case .audiobooks: String(localized: "Audiobooks")
        case .news: String(localized: "News")
        }
    }
}

struct HubItem: Identifiable, Hashable {
    enum Kind: Hashable {
        /// Plays this address.
        case audio(URL)
        /// Opens a feed of episodes or chapters.
        case feed(URL)
        /// A headline: read its summary aloud.
        case headline(String)
    }

    let id = UUID()
    let title: String
    let detail: String
    let kind: Kind
}

// MARK: - RSS

/// A minimal RSS reader: item titles, summaries and audio enclosures.
final class RSSFeed: NSObject, XMLParserDelegate {
    struct Item: Equatable {
        var title = ""
        var summary = ""
        var audio: URL?
    }

    private var items: [Item] = []
    private var current: Item?
    private var text = ""

    static func parse(_ data: Data) -> [Item] {
        let feed = RSSFeed()
        let parser = XMLParser(data: data)
        parser.delegate = feed
        parser.parse()
        return feed.items
    }

    func parser(_ parser: XMLParser, didStartElement element: String, namespaceURI: String?,
                qualifiedName: String?, attributes: [String: String] = [:]) {
        text = ""
        if element == "item" || element == "entry" { current = Item() }
        if element == "enclosure", let url = attributes["url"].flatMap(URL.init(string:)),
           attributes["type"]?.hasPrefix("audio") ?? true {
            current?.audio = url
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) { text += string }

    func parser(_ parser: XMLParser, foundCDATA block: Data) { text += String(decoding: block, as: UTF8.self) }

    func parser(_ parser: XMLParser, didEndElement element: String, namespaceURI: String?, qualifiedName: String?) {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        switch element {
        case "title": if current?.title.isEmpty == true { current?.title = value }
        case "description", "summary", "itunes:summary":
            if current?.summary.isEmpty == true { current?.summary = Self.plain(value) }
        case "item", "entry":
            if let current { items.append(current) }
            current = nil
        default: break
        }
    }

    /// Strips HTML tags and entities from a summary.
    static func plain(_ html: String) -> String {
        guard html.contains("<") || html.contains("&"),
              let data = html.data(using: .utf8),
              let attributed = try? NSAttributedString(data: data, options: [
                .documentType: NSAttributedString.DocumentType.html,
                .characterEncoding: String.Encoding.utf8.rawValue], documentAttributes: nil)
        else { return html }
        return attributed.string.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - Hub

final class AudioHub: ObservableObject {
    static let shared = AudioHub()

    @Published var source = HubSource.radio
    @Published private(set) var results: [HubItem] = []
    @Published private(set) var status = String(localized: "Choose Radio, Podcasts, Audiobooks or News, then search.")
    @Published private(set) var nowPlaying: String?
    @Published private(set) var playing = false
    @Published var volume: Float = 0.8 { didSet { applyVolume() } }

    private let player = AVPlayer()
    /// From the mixer: other-sounds balance, and silence in quiet mode.
    private var mixGain: Float = 1

    // MARK: Searching

    func search(_ query: String) {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard source == .news || !query.isEmpty else { return report(String(localized: "Type something to search for")) }
        report(String(localized: "Searching"))
        Task { @MainActor in
            do {
                let found = try await find(query, in: source)
                results = found
                report(found.isEmpty ? String(localized: "Nothing found") : String(localized: "\(found.count) results"))
            } catch {
                report(String(localized: "Couldn't search. Check your internet connection."))
            }
        }
    }

    func find(_ query: String, in source: HubSource) async throws -> [HubItem] {
        switch source {
        case .radio:
            var url = URLComponents(string: "https://de1.api.radio-browser.info/json/stations/search")!
            url.queryItems = [.init(name: "name", value: query), .init(name: "limit", value: "40"),
                              .init(name: "hidebroken", value: "true"), .init(name: "order", value: "clickcount"),
                              .init(name: "reverse", value: "true")]
            let stations = try await json(url.url!) as? [[String: Any]] ?? []
            return stations.compactMap { station in
                guard let name = station["name"] as? String,
                      let address = (station["url_resolved"] as? String).flatMap(URL.init(string:)) else { return nil }
                let detail = [station["country"] as? String, station["tags"] as? String]
                    .compactMap { $0?.isEmpty == false ? $0 : nil }.joined(separator: ", ")
                return HubItem(title: name.trimmingCharacters(in: .whitespaces), detail: detail, kind: .audio(address))
            }
        case .podcasts:
            var url = URLComponents(string: "https://itunes.apple.com/search")!
            url.queryItems = [.init(name: "media", value: "podcast"), .init(name: "term", value: query),
                              .init(name: "limit", value: "30")]
            let shows = (try await json(url.url!) as? [String: Any])?["results"] as? [[String: Any]] ?? []
            return shows.compactMap { show in
                guard let name = show["collectionName"] as? String,
                      let feed = (show["feedUrl"] as? String).flatMap(URL.init(string:)) else { return nil }
                return HubItem(title: name, detail: show["artistName"] as? String ?? "", kind: .feed(feed))
            }
        case .audiobooks:
            // LibriVox matches whole titles only; "^" means "title starts with". If no
            // title starts with the words, try them as an author's name instead.
            func books(_ field: String, _ value: String) async -> [[String: Any]] {
                var url = URLComponents(string: "https://librivox.org/api/feed/audiobooks/")!
                url.queryItems = [.init(name: field, value: value), .init(name: "format", value: "json"),
                                  .init(name: "extended", value: "1"), .init(name: "limit", value: "30")]
                return (try? await json(url.url!) as? [String: Any])?["books"] as? [[String: Any]] ?? []
            }
            var found = await books("title", "^" + query)
            if found.isEmpty { found = await books("author", query) }
            return found.compactMap { book in
                guard let title = book["title"] as? String,
                      let feed = (book["url_rss"] as? String).flatMap(URL.init(string:)) else { return nil }
                let authors = (book["authors"] as? [[String: Any]] ?? []).map {
                    "\($0["first_name"] as? String ?? "") \($0["last_name"] as? String ?? "")"
                        .trimmingCharacters(in: .whitespaces)
                }
                return HubItem(title: title, detail: authors.joined(separator: ", "), kind: .feed(feed))
            }
        case .news:
            var headlines: [HubItem] = []
            for address in Preferences.shared.newsFeeds {
                guard let url = URL(string: address) else { continue }
                let items = (try? await data(url)).map(RSSFeed.parse) ?? []
                headlines += items.prefix(15)
                    .filter { query.isEmpty || $0.title.localizedCaseInsensitiveContains(query) }
                    .map { HubItem(title: $0.title, detail: url.host() ?? "", kind: .headline($0.summary)) }
            }
            return headlines
        }
    }

    // MARK: Choosing

    func choose(_ item: HubItem) {
        switch item.kind {
        case .audio(let url): play(url, title: item.title)
        case .headline(let summary): Announcer.say(item.title + ". " + summary)
        case .feed(let url):
            report(String(localized: "Opening \(item.title)"))
            Task { @MainActor in
                let items = (try? await data(url)).map(RSSFeed.parse) ?? []
                results = items.compactMap { entry in
                    entry.audio.map { HubItem(title: entry.title, detail: item.title, kind: .audio($0)) }
                }
                report(results.isEmpty ? String(localized: "No episodes found") : String(localized: "\(item.title): \(results.count) episodes"))
            }
        }
    }

    // MARK: Playing

    private func play(_ url: URL, title: String) {
        player.replaceCurrentItem(with: AVPlayerItem(url: url))
        applyVolume()
        player.play()
        nowPlaying = title
        playing = true
        Tones.play(.status)
        Announcer.say(String(localized: "Playing \(title)"))
    }

    func togglePlay() {
        guard nowPlaying != nil else { return Announcer.say(String(localized: "Nothing is playing. Open the audio hub to choose something.")) }
        if playing { player.pause() } else { player.play() }
        playing.toggle()
        Announcer.say(playing ? String(localized: "Playing") : String(localized: "Paused"))
    }

    func stop() {
        player.pause()
        player.replaceCurrentItem(with: nil)
        nowPlaying = nil
        playing = false
    }

    func skip(seconds: Double) {
        guard let item = player.currentItem, item.duration.isNumeric else { return }
        let target = CMTimeAdd(player.currentTime(), CMTime(seconds: seconds, preferredTimescale: 600))
        player.seek(to: target)
    }

    /// Called by the Controller when the balance or quiet mode changes.
    func applyMix(othersGain: Float, quiet: Bool) {
        mixGain = quiet ? 0 : othersGain
        applyVolume()
    }

    private func applyVolume() { player.volume = volume * mixGain }

    // MARK: Network

    private func data(_ url: URL) async throws -> Data {
        var request = URLRequest(url: url)
        request.setValue("VoiceOverAudioSplit/1.0 (accessibility app)", forHTTPHeaderField: "User-Agent")
        return try await URLSession.shared.data(for: request).0
    }

    private func json(_ url: URL) async throws -> Any {
        try JSONSerialization.jsonObject(with: try await data(url))
    }

    private func report(_ message: String) {
        status = message
        Announcer.say(message)
    }
}

struct AudioHubView: View {
    @ObservedObject var hub = AudioHub.shared
    @ObservedObject var preferences = Preferences.shared
    @State private var query = ""
    @State private var selection: HubItem.ID?
    @State private var newFeed = ""
    @FocusState private var queryFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Picker(String(localized: "Source"), selection: $hub.source) {
                ForEach(HubSource.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            HStack {
                TextField(hub.source == .news ? String(localized: "Filter headlines (optional)") : String(localized: "Search \(hub.source.title.lowercased())"),
                          text: $query)
                    .focused($queryFocused)
                    .onSubmit { hub.search(query) }
                Button(hub.source == .news ? String(localized: "Get Headlines") : String(localized: "Search")) { hub.search(query) }
                    .keyboardShortcut(.defaultAction)
            }
            Text(hub.status).font(.caption)
            List(hub.results, selection: $selection) { item in
                Text(item.detail.isEmpty ? item.title : "\(item.title), \(item.detail)")
                    .tag(item.id)
            }
            .onKeyPress(.return) {
                openSelection()
                return .handled
            }
            .accessibilityLabel(String(localized: "Results. Press Return to open or play."))
            HStack {
                Button(String(localized: "Open or Play")) { openSelection() }.disabled(selection == nil)
                Button(hub.playing ? String(localized: "Pause") : String(localized: "Play")) { hub.togglePlay() }
                    .disabled(hub.nowPlaying == nil)
                Button(String(localized: "Back 30 Seconds")) { hub.skip(seconds: -30) }.disabled(hub.nowPlaying == nil)
                Button(String(localized: "Forward 30 Seconds")) { hub.skip(seconds: 30) }.disabled(hub.nowPlaying == nil)
                Button(String(localized: "Stop")) { hub.stop() }.disabled(hub.nowPlaying == nil)
                Slider(value: $hub.volume, in: 0...1) { Text(String(localized: "Volume")) }.frame(width: 140)
            }
            if let title = hub.nowPlaying { Text(String(localized: "Now playing: \(title)")) }
            if hub.source == .news {
                DisclosureGroup(String(localized: "News feeds")) {
                    ForEach(preferences.newsFeeds, id: \.self) { feed in
                        HStack {
                            Text(feed)
                            Button(String(localized: "Remove")) { preferences.newsFeeds.removeAll { $0 == feed } }
                        }
                    }
                    HStack {
                        TextField(String(localized: "Add a feed address (RSS)"), text: $newFeed)
                        Button(String(localized: "Add")) {
                            preferences.newsFeeds.append(newFeed.trimmingCharacters(in: .whitespaces))
                            newFeed = ""
                        }
                        .disabled(URL(string: newFeed)?.scheme?.hasPrefix("http") != true)
                    }
                }
            }
        }
        .padding()
        .frame(width: 620, height: 560)
        .onAppear { queryFocused = true }
    }

    private func openSelection() {
        guard let item = hub.results.first(where: { $0.id == selection }) else { return }
        hub.choose(item)
    }
}
