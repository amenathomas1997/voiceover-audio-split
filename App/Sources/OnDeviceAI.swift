// OnDeviceAI.swift — the AI features without an API key: Apple's on-device model
// (Apple Intelligence, macOS 27 and later) describes images and videos, answers the
// assistant's questions, picks controls for Do It for Me and identifies money. It runs
// entirely on the Mac: nothing is sent anywhere, and it costs nothing. Settings chooses
// it or Claude (with the user's own Anthropic key); Claude.send routes to it.

import AppKit
import ImageIO
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Which AI the assistant features use.
enum AIProvider: String, CaseIterable, Identifiable {
    /// Apple's on-device model, when this Mac has it.
    case onDevice
    /// Claude, with the user's Anthropic API key.
    case claude

    var id: String { rawValue }

    var title: String {
        switch self {
        case .onDevice: String(localized: "On this Mac (private and free)")
        case .claude: String(localized: "Claude, with your Anthropic API key")
        }
    }

    static var chosen: AIProvider { AIProvider(rawValue: Preferences.shared.aiProvider) ?? .onDevice }
}

enum AI {
    /// The on-device model is used when chosen and ready, and also when Claude is chosen
    /// but no key has been added. Claude is used when chosen with a key, or when the
    /// on-device model isn't available on this Mac but a key is.
    static var usesOnDevice: Bool {
        guard OnDeviceAI.isAvailable else { return false }
        return AIProvider.chosen == .onDevice || APIKey.current == nil
    }

    /// Whether any AI can answer: the on-device model, or Claude with a key.
    static var isReady: Bool { usesOnDevice || APIKey.current != nil }

    /// What to say when no AI can answer.
    static var notReadyMessage: String {
        OnDeviceAI.isSupportedOS
            ? String(localized: "Turn on Apple Intelligence in System Settings to use the AI on your Mac, or add an Anthropic API key in Settings.")
            : String(localized: "Add your Anthropic API key in Settings first. The AI on your Mac needs macOS 27 or later.")
    }
}

enum OnDeviceAI {
    /// About how much text the on-device model takes at once (its context is much smaller
    /// than Claude's); longer requests are trimmed to fit.
    static let maxCharacters = 9000

    static var isSupportedOS: Bool {
        if #available(macOS 27.0, *) { return true }
        return false
    }

    /// Ready to use: macOS 27, an Apple Intelligence Mac with it turned on, and the model downloaded.
    static var isAvailable: Bool {
        #if canImport(FoundationModels)
        if #available(macOS 27.0, *) {
            return SystemLanguageModel.default.availability == .available
        }
        #endif
        return false
    }

    /// Whether the on-device model can look at pictures.
    static var canSeeImages: Bool {
        #if canImport(FoundationModels)
        if #available(macOS 27.0, *) {
            return isAvailable && SystemLanguageModel.default.capabilities.contains(.vision)
        }
        #endif
        return false
    }

    /// Why it can't be used, for Settings.
    static var status: String {
        #if canImport(FoundationModels)
        if #available(macOS 27.0, *) {
            switch SystemLanguageModel.default.availability {
            case .available: return String(localized: "The AI on this Mac is ready.")
            case .unavailable(.deviceNotEligible): return String(localized: "This Mac can't run Apple Intelligence, so the AI on this Mac isn't available.")
            case .unavailable(.appleIntelligenceNotEnabled): return String(localized: "Turn on Apple Intelligence in System Settings to use the AI on this Mac.")
            case .unavailable(.modelNotReady): return String(localized: "The AI on this Mac is still downloading. Try again later.")
            case .unavailable: return String(localized: "The AI on this Mac isn't available right now.")
            }
        }
        #endif
        return String(localized: "The AI on this Mac needs macOS 27 or later.")
    }

    // MARK: Requests

    /// One piece of a request: text, or a picture.
    enum Part {
        case text(String)
        case image(CGImage)
    }

    /// The parts of a conversation in Claude's message format ("role" and "content",
    /// content as text or as text and base64 image blocks), as one prompt: earlier turns as
    /// text, labelled, then the last message. Pictures are kept, in order.
    static func parts(of messages: [[String: Any]]) -> [Part] {
        var parts: [Part] = []
        for (index, message) in messages.enumerated() {
            let last = index == messages.count - 1
            let role = message["role"] as? String == "assistant" ? String(localized: "You answered:") : String(localized: "The user said:")
            var texts: [String] = []
            var images: [CGImage] = []
            if let text = message["content"] as? String {
                texts.append(text)
            } else if let blocks = message["content"] as? [Any] {
                for case let block as [String: Any] in blocks {
                    switch block["type"] as? String {
                    case "text": if let text = block["text"] as? String { texts.append(text) }
                    case "image":
                        if let source = block["source"] as? [String: Any], let base64 = source["data"] as? String,
                           let data = Data(base64Encoded: base64), let image = cgImage(from: data) { images.append(image) }
                    default: break
                    }
                }
            }
            parts += images.map(Part.image)
            let text = texts.joined(separator: "\n")
            if !text.isEmpty { parts.append(.text(last || messages.count == 1 ? text : "\(role) \(text)")) }
        }
        return trimmed(parts)
    }

    /// Keeps the request within what the on-device model takes: the newest text wins, and
    /// older turns are left out first. A single long text keeps its beginning.
    static func trimmed(_ parts: [Part]) -> [Part] {
        var budget = maxCharacters
        var kept: [Part] = []
        for part in parts.reversed() {
            switch part {
            case .image: kept.append(part)
            case .text(let text):
                guard budget > 0 else { continue }
                if text.count <= budget {
                    kept.append(part)
                    budget -= text.count
                } else {
                    kept.append(.text(String(text.prefix(budget)) + "\n…"))
                    budget = 0
                }
            }
        }
        return kept.reversed()
    }

    private static func cgImage(from data: Data) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }

    /// The small on-device model doesn't know VoiceOver's keys reliably, and guesses: these
    /// are the ones it may name, and it's told to point to VoiceOver Help for any other.
    static let voiceOverKeys = """
    VoiceOver keys you may mention (VO means Control and Option held together): Command F5 turns VoiceOver on \
    or off. VO Right Arrow and VO Left Arrow move to the next and previous item. VO Space presses or activates \
    the item. VO Shift Down Arrow interacts with (goes into) a group, table or web area, and VO Shift Up Arrow \
    stops interacting. VO A reads everything from here. VO U opens the rotor; Left and Right Arrow change its list \
    and Up and Down Arrow choose an item. VO Command H moves to the next heading, VO Command L the next link, \
    VO Command J the next form control and VO Command T the next table. VO M opens the menu bar, and VO Shift M \
    the shortcut menu for the item. VO I opens the item chooser. VO F finds text. VO H opens VoiceOver Help. \
    VO K turns on keyboard help. VO Z repeats the last phrase. VO F8 opens VoiceOver Utility. Command Tab switches \
    apps. If a key isn't in this list, don't guess: say to look it up in VoiceOver Help with VO H, and then H again \
    for the Commands menu.
    """

    /// Answers a conversation on the Mac, in the same shape Claude.send returns.
    static func send(_ messages: [[String: Any]], system: String) async throws -> (content: [Any], text: String) {
        let text = try await respond(parts(of: messages), instructions: system + "\n\n" + voiceOverKeys)
        return ([["type": "text", "text": text]], text)
    }

    /// Asks the on-device model, with instructions, text and pictures.
    static func respond(_ parts: [Part], instructions: String) async throws -> String {
        #if canImport(FoundationModels)
        if #available(macOS 27.0, *) {
            guard isAvailable else { throw Claude.Failure(message: status) }
            let hasImage = parts.contains { if case .image = $0 { true } else { false } }
            if hasImage && !canSeeImages {
                throw Claude.Failure(message: String(localized: "The AI on this Mac can't describe pictures on this version of macOS."))
            }
            let code = Locale.current.language.languageCode?.identifier ?? "en"
            let language = Locale(identifier: "en").localizedString(forLanguageCode: code) ?? "English"
            let session = LanguageModelSession(model: .default, instructions:
                instructions + "\n\nWrite any text for the user in \(language) unless the user writes in another language.")
            let prompt = Prompt(parts.map { part -> Prompt in
                switch part {
                case .text(let text): Prompt(text)
                case .image(let image): Prompt(Attachment(image))
                }
            })
            do {
                let reply = try await session.respond(to: prompt).content.trimmingCharacters(in: .whitespacesAndNewlines)
                return reply.isEmpty ? String(localized: "No answer was returned.") : reply
            } catch let error as LanguageModelError {
                log("On-device AI failed: \(error).")
                switch error {
                case .guardrailViolation: throw Claude.Failure(message: String(localized: "The request was declined."))
                case .contextSizeExceeded: throw Claude.Failure(message: String(localized: "That's too long for the AI on this Mac. Try a shorter question."))
                default: throw Claude.Failure(message: String(localized: "The AI on this Mac couldn't answer. Try again."))
                }
            } catch {
                log("On-device AI failed: \(error).")
                throw Claude.Failure(message: String(localized: "The AI on this Mac couldn't answer. Try again."))
            }
        }
        #endif
        throw Claude.Failure(message: status)
    }
}
