// DoItForMe.swift — "find the Submit button", "go to the search field", "press
// Play": Claude reads the names of the controls in the front window and picks the
// one asked for. The VoiceOver cursor is moved there, so the user stays in charge.
// Pressing always needs a confirmation first, and Claude is told never to choose
// pressing for anything that sends, buys, posts or deletes.
// Only the names and roles of the front window's controls are sent, and only when asked.

import AppKit
import SwiftUI

final class DoItModel: ObservableObject {
    static let shared = DoItModel()

    @Published var request = ""
    @Published var busy = false
    @Published var log: [String] = []
    /// A control waiting for the user to confirm pressing it.
    @Published var pendingPress: String?

    /// The app that was in front when the window opened: the one to act on.
    var target: NSRunningApplication?
    private var pendingElement: AXUIElement?

    static let system = """
    You help a blind Mac user who uses the VoiceOver screen reader to find and use controls in an app. You get the \
    user's request and a numbered list of the controls in the app's front window, as "[number] role: name". \
    Choose the single control that best fits the request.

    Reply with only a JSON object and nothing else: {"element": number or null, "action": "move" or "press" or \
    "none", "say": "one or two short sentences for the user"}.

    Use "move" to put the VoiceOver cursor on the control; this is the default. Use "press" only when the user \
    clearly asks to press, click, open, play or activate something. Never use "press" for a control that sends, \
    submits, buys, pays, posts, deletes or signs in: use "move" and say what the control does instead. If nothing \
    fits, use "none" with a null element and say what you looked for and what the window does have. The "say" text \
    is read aloud: plain text, no markdown.
    """

    func run() {
        let request = request.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !request.isEmpty, !busy else { return }
        guard Hotkeys.isTrusted else { return note(String(localized: "Allow keyboard shortcuts in Settings first; this uses the same permission.")) }
        guard let target, !target.isTerminated else { return note(String(localized: "Open the app first, then choose Do It for Me.")) }
        busy = true
        pendingPress = nil
        log.append(String(localized: "You: \(request)"))
        Announcer.say(String(localized: "Looking"))
        let pid = target.processIdentifier
        Task.detached {
            let app = AX.application(pid)
            guard let window = AX.element(app, kAXFocusedWindowAttribute) ?? AX.element(app, kAXMainWindowAttribute) else {
                return await self.finish(String(localized: "That app has no window open."))
            }
            let controls = Self.controls(in: window)
            guard !controls.isEmpty else { return await self.finish(String(localized: "No controls were found in that window.")) }
            let list = controls.enumerated().map { "[\($0.offset)] \($0.element.line)" }.joined(separator: "\n")
            do {
                let reply = try await Claude.send([["role": "user", "content": "Request: \(request)\n\nControls:\n\(list)"]],
                                                  system: Self.system)
                guard let choice = Choice(reply.text) else { return await self.finish(String(localized: "The answer couldn't be understood. Try asking another way.")) }
                let element = choice.element.flatMap { $0 >= 0 && $0 < controls.count ? controls[$0].element : nil }
                await self.act(choice, on: element, named: choice.element.flatMap { $0 >= 0 && $0 < controls.count ? controls[$0].line : nil })
            } catch let failure as Claude.Failure {
                await self.finish(failure.message)
            } catch {
                await self.finish(String(localized: "The request failed."))
            }
        }
    }

    @MainActor
    private func act(_ choice: Choice, on element: AXUIElement?, named name: String?) {
        guard let element, choice.action != "none" else { return finish(choice.say) }
        if choice.action == "press" {
            pendingElement = element
            pendingPress = name
            busy = false
            log.append(choice.say)
            Announcer.say(choice.say + " " + String(localized: "Press Return to press it, or Escape to cancel."))
            return
        }
        busy = false
        log.append(choice.say)
        moveThere(element, saying: choice.say)
    }

    /// Brings the app back to the front and puts the VoiceOver cursor on the control.
    private func moveThere(_ element: AXUIElement, saying text: String) {
        NSApp.hide(nil)
        target?.activate()
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.6) {
            let moved = AX.moveVoiceOverCursor(to: element)
            DispatchQueue.main.async {
                Announcer.say(moved ? text : text + " " + String(localized: "VoiceOver couldn't be moved there."))
            }
        }
    }

    func confirmPress() {
        guard let element = pendingElement else { return }
        pendingElement = nil
        pendingPress = nil
        NSApp.hide(nil)
        target?.activate()
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.4) {
            // A slow app can report "couldn't complete" after the press already happened;
            // only press through VoiceOver when the control has no press action at all.
            let result = AX.pressResult(element)
            let pressed = result == .success || result == .cannotComplete
                || ([.actionUnsupported, .attributeUnsupported].contains(result)
                    && AX.moveVoiceOverCursor(to: element) && VoiceOverText.run("tell vo cursor to perform action") != nil)
            DispatchQueue.main.async {
                Announcer.say(pressed ? String(localized: "Pressed") : String(localized: "It couldn't be pressed"))
            }
        }
    }

    func cancelPress() {
        pendingElement = nil
        pendingPress = nil
        Announcer.say(String(localized: "Cancelled"))
    }

    @MainActor
    private func finish(_ text: String) {
        busy = false
        note(text)
    }

    private func note(_ text: String) {
        log.append(text)
        Announcer.say(text)
    }

    /// The controls worth naming: anything with a name, plus buttons, fields and
    /// links without one, which are described by role and position.
    struct Control {
        let element: AXUIElement
        let line: String
    }

    static let actionable: Set<String> = [
        kAXButtonRole, kAXTextFieldRole, kAXTextAreaRole, kAXCheckBoxRole, kAXRadioButtonRole, kAXPopUpButtonRole,
        kAXMenuButtonRole, kAXComboBoxRole, kAXSliderRole, kAXTabGroupRole, "AXLink", kAXCellRole, kAXRowRole,
        kAXImageRole, "AXHeading", kAXStaticTextRole, "AXSearchField", kAXDisclosureTriangleRole, kAXIncrementorRole,
    ]

    static func controls(in window: AXUIElement) -> [Control] {
        var result: [Control] = []
        for element in AX.descendants(of: window, limit: 4000) where result.count < 400 {
            let role = AX.string(element, kAXRoleAttribute)
            guard actionable.contains(role) else { continue }
            let text = AX.text(element)
            if role == kAXStaticTextRole && text.count < 2 { continue }
            let roleName = AX.string(element, kAXRoleDescriptionAttribute)
            result.append(Control(element: element, line: "\(roleName.isEmpty ? role : roleName): \(text.isEmpty ? "(no name)" : text)"))
        }
        return result
    }

    /// Claude's choice, from the JSON in its reply.
    struct Choice {
        let element: Int?
        let action: String
        let say: String

        init?(_ text: String) {
            guard let start = text.firstIndex(of: "{"), let end = text.lastIndex(of: "}"),
                  let json = try? JSONSerialization.jsonObject(with: Data(text[start...end].utf8)) as? [String: Any],
                  let action = json["action"] as? String else { return nil }
            element = json["element"] as? Int
            self.action = ["move", "press", "none"].contains(action) ? action : "none"
            say = json["say"] as? String ?? ""
        }
    }
}

struct DoItForMeView: View {
    @ObservedObject var model = DoItModel.shared
    @FocusState private var focused: Bool

    var body: some View {
        Form {
            Section {
                Text(String(localized: "Acting on: \(model.target?.localizedName ?? String(localized: "no app"))"))
                TextField(String(localized: "What should I find or press? For example, the search field, or press Play."), text: $model.request)
                    .focused($focused)
                    .onSubmit { model.run() }
                Button(String(localized: "Do It")) { model.run() }
                    .disabled(model.busy || model.request.trimmingCharacters(in: .whitespaces).isEmpty)
                Text(String(localized: "The names of the controls in that app's front window are sent to Anthropic. Nothing is pressed without your confirmation."))
                    .font(.caption).foregroundStyle(.secondary)
            }
            if let name = model.pendingPress {
                Section(String(localized: "Press \(name)?")) {
                    HStack {
                        Button(String(localized: "Press")) { model.confirmPress() }
                            .keyboardShortcut(.defaultAction)
                        Button(String(localized: "Cancel")) { model.cancelPress() }
                            .keyboardShortcut(.cancelAction)
                    }
                }
            }
            Section(String(localized: "What happened")) {
                ForEach(Array(model.log.enumerated().reversed()), id: \.offset) { Text($0.element) }
            }
        }
        .formStyle(.grouped)
        .frame(width: 520, height: 460)
        .onAppear { focused = true }
    }
}
