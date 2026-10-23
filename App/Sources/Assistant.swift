// Assistant.swift — AI features using Claude:
//   * Describe image: a picture of what is under the VoiceOver cursor, described
//     in detail, with follow-up questions (like JAWS Picture Smart AI)
//   * Ask: questions about using the Mac and VoiceOver (like FS Companion)
// Calls the Claude Messages API over HTTPS (there is no official Swift SDK).
// The API key is kept in the Keychain. Pictures are only sent after the user
// allows it once in the window.

import AppKit
import ScreenCaptureKit
import Security
import SwiftUI

// MARK: - API key

enum APIKey {
    private static let service = "com.fullcircleat.VoiceOverAudioSplit.anthropic"

    static var current: String? {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                    kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func save(_ key: String) {
        let base: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service]
        SecItemDelete(base as CFDictionary)
        guard !key.isEmpty else { return }
        var item = base
        item[kSecValueData as String] = Data(key.utf8)
        SecItemAdd(item as CFDictionary, nil)
    }
}

// MARK: - Claude

enum Claude {
    struct Failure: Error { let message: String }

    static let model = "claude-opus-5-5"

    static let system = """
    You help a blind Mac user who uses the VoiceOver screen reader. Your answers are read aloud, so write plain \
    text: no markdown, headings, bullets, tables or emoji. Put the most important information first and keep \
    answers short unless more detail is asked for.

    When given an image, describe what it shows. Read any text in it exactly. Describe layout or colors only when \
    they matter for understanding it. If it is part of an app, say what the control or content is and what it is \
    for.

    For questions about using a Mac, explain keyboard steps using VoiceOver commands. VO means Control and Option \
    held together. Mention when a step needs a setting turned on first.
    """

    /// Sends the conversation and returns the assistant's full content blocks
    /// (to append to the conversation unchanged) and its spoken text.
    static func send(_ messages: [[String: Any]], system: String = Claude.system) async throws -> (content: [Any], text: String) {
        guard let key = APIKey.current, !key.isEmpty else {
            throw Failure(message: String(localized: "Add your Anthropic API key in Settings first."))
        }
        var request = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 300
        request.setValue(key, forHTTPHeaderField: "x-api-key")
        request.setValue("2026-10-21", forHTTPHeaderField: "anthropic-version")
        // On a safety decline, the API retries on a fallback model in the same call.
        request.setValue("server-side-fallback-2026-07-01", forHTTPHeaderField: "anthropic-beta")
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        // Answer in the language the Mac is set to, unless the user writes in another.
        let code = Locale.current.language.languageCode?.identifier ?? "en"
        let language = Locale(identifier: "en").localizedString(forLanguageCode: code) ?? "English"
        let body: [String: Any] = [
            "model": model, "max_tokens": 16000,
            "system": system + "\n\nWrite any text for the user in \(language) unless the user writes in another language.",
            "messages": messages,
            "output_config": ["effort": "medium"], "fallbacks": "default",
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw Failure(message: String(localized: "Couldn't reach Anthropic. Check your internet connection."))
        }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        guard status == 200 else {
            let detail = ((json["error"] as? [String: Any])?["message"] as? String).map { " \($0)" } ?? ""
            log("Claude request failed with status \(status).")
            switch status {
            case 401: throw Failure(message: String(localized: "The API key was not accepted. Check it in Settings."))
            case 429: throw Failure(message: String(localized: "Too many requests right now. Try again in a minute."))
            case 500...: throw Failure(message: String(localized: "Anthropic's service had a problem. Try again shortly."))
            default: throw Failure(message: String(localized: "The request failed.\(detail)"))
            }
        }
        if json["stop_reason"] as? String == "refusal" {
            throw Failure(message: String(localized: "The request was declined."))
        }
        let content = json["content"] as? [Any] ?? []
        let text = content.compactMap { block -> String? in
            guard let block = block as? [String: Any], block["type"] as? String == "text" else { return nil }
            return block["text"] as? String
        }.joined(separator: "\n\n")
        return (content, text.isEmpty ? String(localized: "No answer was returned.") : text)
    }
}

// MARK: - Screen capture

enum ScreenPicture {
    struct Failure: Error { let message: String }

    /// A PNG of the item under the VoiceOver cursor, or of the main screen if
    /// VoiceOver isn't available.
    static func underVoiceOverCursor() async throws -> Data {
        let content: SCShareableContent
        do {
            content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        } catch {
            throw Failure(message: String(localized: "Allow screen recording for VoiceOver Audio Split in System Settings, Privacy and Security, Screen and System Audio Recording. Then try again."))
        }
        let cursor = await Task.detached { VoiceOverText.cursorBounds() }.value
        // VoiceOver reports top-left based screen coordinates, like ScreenCaptureKit.
        let display = content.displays.first { cursor.map($0.frame.intersects) ?? false }
            ?? content.displays.first { $0.displayID == CGMainDisplayID() } ?? content.displays.first
        guard let display else { throw Failure(message: String(localized: "No screen found.")) }

        let configuration = SCStreamConfiguration()
        var area = CGRect(x: 0, y: 0, width: display.width, height: display.height)
        if let cursor, cursor.width >= 8, cursor.height >= 8 {
            area = cursor.offsetBy(dx: -display.frame.minX, dy: -display.frame.minY)
                .intersection(CGRect(x: 0, y: 0, width: display.width, height: display.height))
        }
        configuration.sourceRect = area
        let scale = CGFloat(NSScreen.main?.backingScaleFactor ?? 2)
        configuration.width = Int(area.width * scale)
        configuration.height = Int(area.height * scale)
        let filter = SCContentFilter(display: display, excludingWindows: [])
        let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
        guard let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else {
            throw Failure(message: String(localized: "Couldn't capture the screen."))
        }
        return png
    }

    /// A PNG of the front window of the app in front (leaving out this app's own windows).
    static func frontWindow() async throws -> Data {
        let content: SCShareableContent
        do {
            content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
        } catch {
            throw Failure(message: String(localized: "Allow screen recording for VoiceOver Audio Split in System Settings, Privacy and Security, Screen and System Audio Recording. Then try again."))
        }
        let front = await MainActor.run { NSWorkspace.shared.frontmostApplication?.processIdentifier }
        let me = ProcessInfo.processInfo.processIdentifier
        let candidates = content.windows.filter { window in
            window.windowLayer == 0 && window.frame.width > 100 && window.frame.height > 100
                && window.owningApplication?.processID != me
        }
        // On-screen windows are listed front to back; prefer the front app's frontmost window.
        guard let window = candidates.first(where: { $0.owningApplication?.processID == front }) ?? candidates.first else {
            throw Failure(message: String(localized: "No window to read."))
        }
        let configuration = SCStreamConfiguration()
        let scale = CGFloat(NSScreen.main?.backingScaleFactor ?? 2)
        configuration.width = Int(window.frame.width * scale)
        configuration.height = Int(window.frame.height * scale)
        let image = try await SCScreenshotManager.captureImage(
            contentFilter: SCContentFilter(desktopIndependentWindow: window), configuration: configuration)
        guard let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else {
            throw Failure(message: String(localized: "Couldn't capture the window."))
        }
        return png
    }
}

// MARK: - Window

struct AssistantTurn: Identifiable {
    let id = UUID()
    let fromUser: Bool
    let text: String
}

final class AssistantModel: ObservableObject {
    static let shared = AssistantModel()

    @Published var turns: [AssistantTurn] = []
    @Published var busy = false
    @Published var waitingForImageConsent = false
    /// Shows the window. Called only after the picture is taken: opening the window
    /// earlier would move the VoiceOver cursor away from the image.
    var showWindow: (() -> Void)?
    /// The API conversation, appended to only (never edited), so earlier turns stay valid.
    private var messages: [[String: Any]] = []

    func newConversation() {
        turns = []
        messages = []
    }

    enum ImageTarget {
        /// The item under the VoiceOver cursor; the window opens with the answer.
        case voiceOverCursor
        /// The front window, for a video: the answer is spoken without opening a
        /// window, so the video keeps the focus. Follow-ups work in the Assistant window.
        case video
    }

    /// Starts a new conversation about a picture of the screen.
    func describeImage(_ target: ImageTarget = .voiceOverCursor) {
        guard Preferences.shared.allowImageUpload else {
            waitingForImageConsent = true
            showWindow?()
            Announcer.say(String(localized: "Describing images sends a picture of your screen to Anthropic. Choose Allow in the window to continue."))
            return
        }
        waitingForImageConsent = false
        newConversation()
        busy = true
        Announcer.say(String(localized: "Describing"))
        let opensWindow = target == .voiceOverCursor
        Task { @MainActor in
            do {
                let png: Data
                let request: String
                switch target {
                case .voiceOverCursor:
                    png = try await ScreenPicture.underVoiceOverCursor()
                    request = String(localized: "Describe this. It is what my VoiceOver cursor is on.")
                    turns.append(AssistantTurn(fromUser: true, text: String(localized: "Describe the item under the VoiceOver cursor.")))
                case .video:
                    png = try await ScreenPicture.frontWindow()
                    request = String(localized: "This is a frame from a video I'm watching. In two or three sentences, describe what is happening right now, and read any text on screen. Don't describe the video player's controls.")
                    turns.append(AssistantTurn(fromUser: true, text: String(localized: "What's happening in the video?")))
                }
                if opensWindow { showWindow?() }
                let content: [[String: Any]] = [
                    ["type": "image", "source": ["type": "base64", "media_type": "image/png",
                                                 "data": png.base64EncodedString()]],
                    ["type": "text", "text": request],
                ]
                await send(content)
            } catch let failure as ScreenPicture.Failure {
                if opensWindow { showWindow?() }
                finish(failure.message)
            } catch {
                if opensWindow { showWindow?() }
                finish(String(localized: "Couldn't capture the screen."))
            }
        }
    }

    func ask(_ question: String) {
        let question = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty, !busy else { return }
        busy = true
        turns.append(AssistantTurn(fromUser: true, text: question))
        Task { @MainActor in await send([["type": "text", "text": question]]) }
    }

    @MainActor
    private func send(_ content: [[String: Any]]) async {
        let message: [String: Any] = ["role": "user", "content": content]
        do {
            let reply = try await Claude.send(messages + [message])
            messages.append(message)
            messages.append(["role": "assistant", "content": reply.content])
            finish(reply.text)
        } catch let failure as Claude.Failure {
            finish(failure.message)
        } catch {
            finish(String(localized: "The request failed."))
        }
    }

    private func finish(_ text: String) {
        turns.append(AssistantTurn(fromUser: false, text: text))
        busy = false
        Announcer.say(text)
    }
}

struct AssistantView: View {
    @ObservedObject var model = AssistantModel.shared
    @ObservedObject var preferences = Preferences.shared
    @State private var question = ""
    @State private var key = ""
    @FocusState private var questionFocused: Bool

    var body: some View {
        Form {
            if APIKey.current == nil {
                Section(String(localized: "Anthropic API key")) {
                    Text(String(localized: "The assistant and image descriptions use Claude. Paste an API key from console.anthropic.com. It is stored in your Mac's Keychain. Requests are billed to that account."))
                    SecureField(String(localized: "API key"), text: $key)
                    Button(String(localized: "Save key")) {
                        APIKey.save(key.trimmingCharacters(in: .whitespacesAndNewlines))
                        key = ""
                        Announcer.say(String(localized: "Key saved"))
                    }
                    .disabled(key.isEmpty)
                }
            }
            if model.waitingForImageConsent {
                Section(String(localized: "Allow image descriptions?")) {
                    Text(String(localized: "To describe an image, a picture of the item under your VoiceOver cursor is sent to Anthropic. Only that picture is sent, and only when you ask. You can turn this off in Settings."))
                    Button(String(localized: "Allow")) {
                        preferences.allowImageUpload = true
                        model.waitingForImageConsent = false
                        Announcer.say(String(localized: "Allowed. Go back to the image and press the describe shortcut again."))
                    }
                    Button(String(localized: "Not Now")) { model.waitingForImageConsent = false }
                }
            }
            Section(String(localized: "Conversation")) {
                if model.turns.isEmpty {
                    Text(String(localized: "Ask about using your Mac or VoiceOver, or press the describe-image shortcut on a picture."))
                }
                ForEach(model.turns) { turn in
                    Text(turn.fromUser ? String(localized: "You: \(turn.text)") : String(localized: "Claude: \(turn.text)"))
                        .textSelection(.enabled)
                }
                if model.busy { Text(String(localized: "Thinking…")) }
            }
            Section {
                TextField(model.turns.isEmpty ? String(localized: "Your question") : String(localized: "Follow-up question"), text: $question, axis: .vertical)
                    .focused($questionFocused)
                    .onSubmit(send)
                HStack {
                    Button(String(localized: "Ask"), action: send)
                        .keyboardShortcut(.defaultAction)
                        .disabled(question.isEmpty || model.busy)
                    Button(String(localized: "New Conversation")) { model.newConversation() }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 560, height: 620)
        .onAppear { questionFocused = true }
    }

    private func send() {
        model.ask(question)
        question = ""
    }
}
