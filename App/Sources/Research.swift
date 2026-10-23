// Research.swift — quick lookups without opening a browser, like JAWS Research It:
//   * Definition: the Mac's built-in dictionary (works offline)
//   * Wikipedia: the summary of the closest matching article
//   * Weather: current conditions from Open-Meteo (free, no account needed)

import CoreServices
import Foundation
import SwiftUI

enum ResearchSource: String, CaseIterable, Identifiable {
    case definition, wikipedia, weather

    var id: String { rawValue }

    var title: String {
        switch self {
        case .definition: String(localized: "Definition")
        case .wikipedia: String(localized: "Wikipedia")
        case .weather: String(localized: "Weather")
        }
    }

    var prompt: String {
        switch self {
        case .definition: String(localized: "Word to define")
        case .wikipedia: String(localized: "Topic to look up")
        case .weather: String(localized: "City for the weather")
        }
    }
}

enum Research {
    static func lookUp(_ query: String, in source: ResearchSource) async -> String {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return String(localized: "Type something to look up") }
        do {
            switch source {
            case .definition: return define(query)
            case .wikipedia: return try await wikipedia(query)
            case .weather: return try await weather(query)
            }
        } catch {
            return String(localized: "Couldn't look that up. Check your internet connection.")
        }
    }

    private static func define(_ word: String) -> String {
        let range = CFRange(location: 0, length: (word as NSString).length)
        guard let definition = DCSCopyTextDefinition(nil, word as CFString, range)?.takeRetainedValue() as String? else {
            return String(localized: "No definition found for \(word)")
        }
        return definition
    }

    private static func json(_ url: URL) async throws -> Any {
        var request = URLRequest(url: url)
        request.setValue("VoiceOverAudioSplit/1.0 (accessibility app)", forHTTPHeaderField: "User-Agent")
        let (data, _) = try await URLSession.shared.data(for: request)
        return try JSONSerialization.jsonObject(with: data)
    }

    private static func wikipedia(_ topic: String) async throws -> String {
        var search = URLComponents(string: "https://en.wikipedia.org/w/api.php")!
        search.queryItems = [.init(name: "action", value: "opensearch"), .init(name: "search", value: topic),
                             .init(name: "limit", value: "1"), .init(name: "format", value: "json")]
        guard let results = try await json(search.url!) as? [Any], results.count > 1,
              let title = (results[1] as? [String])?.first else { return String(localized: "No Wikipedia article found for \(topic)") }
        let path = title.replacingOccurrences(of: " ", with: "_")
            .addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? title
        guard let summary = try await json(URL(string: "https://en.wikipedia.org/api/rest_v1/page/summary/\(path)")!)
                as? [String: Any],
              let extract = summary["extract"] as? String else { return String(localized: "No summary available for \(title)") }
        return "\(title). \(extract)"
    }

    private static func weather(_ city: String) async throws -> String {
        var geocode = URLComponents(string: "https://geocoding-api.open-meteo.com/v1/search")!
        geocode.queryItems = [.init(name: "name", value: city), .init(name: "count", value: "1")]
        guard let places = (try await json(geocode.url!) as? [String: Any])?["results"] as? [[String: Any]],
              let place = places.first,
              let latitude = place["latitude"] as? Double, let longitude = place["longitude"] as? Double else {
            return String(localized: "Couldn't find a place called \(city)")
        }
        let name = [place["name"] as? String, place["admin1"] as? String].compactMap { $0 }.joined(separator: ", ")
        let fahrenheit = Locale.current.measurementSystem == .us
        var forecast = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        forecast.queryItems = [
            .init(name: "latitude", value: "\(latitude)"), .init(name: "longitude", value: "\(longitude)"),
            .init(name: "current", value: "temperature_2m,apparent_temperature,weather_code,wind_speed_10m"),
            .init(name: "daily", value: "temperature_2m_max,temperature_2m_min,precipitation_probability_max"),
            .init(name: "forecast_days", value: "1"),
            .init(name: "temperature_unit", value: fahrenheit ? "fahrenheit" : "celsius"),
            .init(name: "wind_speed_unit", value: fahrenheit ? "mph" : "kmh"),
        ]
        guard let result = try await json(forecast.url!) as? [String: Any],
              let current = result["current"] as? [String: Any],
              let daily = result["daily"] as? [String: Any] else { return String(localized: "No weather available for \(name)") }
        func number(_ value: Any?) -> Int? { (value as? Double).map { Int($0.rounded()) } }
        func first(_ key: String) -> Int? { number((daily[key] as? [Any])?.first) }
        let unit = fahrenheit ? String(localized: "degrees Fahrenheit") : String(localized: "degrees Celsius")
        var parts = ["\(name): \(describe(code: current["weather_code"] as? Int ?? -1))"]
        if let temperature = number(current["temperature_2m"]) {
            parts.append(fahrenheit ? String(localized: "\(temperature) degrees Fahrenheit") : String(localized: "\(temperature) degrees Celsius"))
        }
        if let feels = number(current["apparent_temperature"]) { parts.append(String(localized: "feels like \(feels)")) }
        if let high = first("temperature_2m_max"), let low = first("temperature_2m_min") {
            parts.append(String(localized: "high \(high), low \(low)"))
        }
        if let rain = first("precipitation_probability_max") { parts.append(String(localized: "\(rain) percent chance of rain")) }
        if let wind = number(current["wind_speed_10m"]) { parts.append(fahrenheit ? String(localized: "wind \(wind) miles per hour") : String(localized: "wind \(wind) kilometres per hour")) }
        return parts.joined(separator: ", ")
    }

    /// WMO weather codes, as used by Open-Meteo.
    private static func describe(code: Int) -> String {
        switch code {
        case 0: String(localized: "clear sky")
        case 1: String(localized: "mainly clear")
        case 2: String(localized: "partly cloudy")
        case 3: String(localized: "overcast")
        case 45, 48: String(localized: "fog")
        case 51, 53, 55: String(localized: "drizzle")
        case 56, 57: String(localized: "freezing drizzle")
        case 61, 63, 65: String(localized: "rain")
        case 66, 67: String(localized: "freezing rain")
        case 71, 73, 75, 77: String(localized: "snow")
        case 80, 81, 82: String(localized: "rain showers")
        case 85, 86: String(localized: "snow showers")
        case 95: String(localized: "thunderstorm")
        case 96, 99: String(localized: "thunderstorm with hail")
        default: String(localized: "unknown conditions")
        }
    }
}

struct ResearchView: View {
    @State private var source = ResearchSource.definition
    @State private var query = ""
    @State private var result = ""
    @State private var busy = false
    @FocusState private var queryFocused: Bool

    var body: some View {
        Form {
            Picker(String(localized: "Look up"), selection: $source) {
                ForEach(ResearchSource.allCases) { Text($0.title).tag($0) }
            }
            TextField(source.prompt, text: $query)
                .focused($queryFocused)
                .onSubmit(lookUp)
            Button(busy ? String(localized: "Looking up…") : String(localized: "Look up"), action: lookUp)
                .keyboardShortcut(.defaultAction)
                .disabled(busy)
            if !result.isEmpty {
                Section(String(localized: "Result")) {
                    Text(result).textSelection(.enabled)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 520, height: 460)
        .onAppear { queryFocused = true }
    }

    private func lookUp() {
        busy = true
        Task {
            let answer = await Research.lookUp(query, in: source)
            result = answer
            busy = false
            Announcer.say(answer)
        }
    }
}
