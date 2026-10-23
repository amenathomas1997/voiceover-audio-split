// AXTools.swift — reading other apps' controls through the macOS accessibility
// interface (the same one VoiceOver uses), for custom labels, place markers and
// "do it for me". Needs the Accessibility permission the shortcuts already use.
// Calls can be slow when an app is busy, so don't call from the main thread.

import AppKit
import ApplicationServices

enum AX {
    /// How long to wait for an app to answer. The default is about six seconds per
    /// question, which would stall these features for minutes on a frozen app.
    static let timeout: Float = 1

    /// An app's accessibility element, with the shorter timeout.
    static func application(_ pid: pid_t) -> AXUIElement {
        let element = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(element, timeout)
        return element
    }

    static func string(_ element: AXUIElement, _ attribute: String) -> String {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return "" }
        if let text = value as? String { return text }
        if let number = value as? NSNumber { return number.stringValue }
        return ""
    }

    static func element(_ element: AXUIElement, _ attribute: String) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }

    static func children(_ element: AXUIElement) -> [AXUIElement] {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &value) == .success else { return [] }
        return value as? [AXUIElement] ?? []
    }

    /// Screen frame, top-left based like VoiceOver's bounds.
    static func frame(_ element: AXUIElement) -> CGRect? {
        var position: CFTypeRef?, size: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &position) == .success,
              AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &size) == .success else { return nil }
        // Some apps return something other than a position or size here.
        guard let position, let size, CFGetTypeID(position) == AXValueGetTypeID(), CFGetTypeID(size) == AXValueGetTypeID()
        else { return nil }
        var point = CGPoint.zero, extent = CGSize.zero
        AXValueGetValue(position as! AXValue, .cgPoint, &point)
        AXValueGetValue(size as! AXValue, .cgSize, &extent)
        return CGRect(origin: point, size: extent)
    }

    static func pid(_ element: AXUIElement) -> pid_t {
        var pid: pid_t = 0
        AXUIElementGetPid(element, &pid)
        return pid
    }

    /// What a person would call the element: its title, description, value or help.
    static func text(_ element: AXUIElement) -> String {
        for attribute in [kAXTitleAttribute, kAXDescriptionAttribute, kAXValueAttribute, kAXHelpAttribute] {
            let text = string(element, attribute).trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty { return String(text.prefix(200)) }
        }
        return ""
    }

    static func pressResult(_ element: AXUIElement) -> AXError {
        AXUIElementPerformAction(element, kAXPressAction as CFString)
    }

    static func focus(_ element: AXUIElement) -> Bool {
        AXUIElementSetAttributeValue(element, kAXFocusedAttribute as CFString, kCFBooleanTrue) == .success
    }

    /// The element in the middle of what the VoiceOver cursor is on.
    static func underVoiceOverCursor() -> AXUIElement? {
        guard let bounds = VoiceOverText.cursorBounds() else { return nil }
        var found: AXUIElement?
        let point = CGPoint(x: bounds.midX, y: bounds.midY)
        let system = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(system, timeout)
        guard AXUIElementCopyElementAtPosition(system, Float(point.x), Float(point.y), &found) == .success
        else { return nil }
        return found
    }

    /// The front app's focused window.
    static func frontWindow() -> AXUIElement? {
        guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
        let element = application(app.processIdentifier)
        return self.element(element, kAXFocusedWindowAttribute) ?? self.element(element, kAXMainWindowAttribute)
    }

    /// Every element below `root`, depth first, up to `limit` elements.
    /// Stops after `seconds` too, so a slow app can't hold things up for long.
    static func descendants(of root: AXUIElement, limit: Int = 6000, seconds: TimeInterval = 8) -> [AXUIElement] {
        var result: [AXUIElement] = []
        var stack = [root]
        let deadline = Date().addingTimeInterval(seconds)
        while let next = stack.popLast(), result.count < limit, Date() < deadline {
            result.append(next)
            stack.append(contentsOf: children(next).reversed())
        }
        return result
    }

    /// Moves the VoiceOver cursor to an element: scrolls it into view, puts the
    /// mouse pointer on it, and asks VoiceOver to follow the pointer.
    static func moveVoiceOverCursor(to element: AXUIElement) -> Bool {
        AXUIElementPerformAction(element, "AXScrollToVisible" as CFString)
        guard let frame = frame(element), frame.width > 0, frame.height > 0 else { return false }
        CGWarpMouseCursorPosition(CGPoint(x: frame.midX, y: frame.midY))
        return VoiceOverText.run("perform command \"move voiceover cursor to mouse pointer\"") != nil
    }
}

/// Recognizes the same control again later, even without a name: by app, role,
/// identifier or text, and otherwise by where it sits in its window.
struct ElementSignature: Codable, Hashable {
    var bundleID: String
    var role: String
    var identifier: String
    var text: String
    var windowTitle: String
    /// Position and size in its window, in points.
    var x: Int, y: Int, width: Int, height: Int

    init(bundleID: String, role: String, identifier: String = "", text: String = "", windowTitle: String = "",
         frame: CGRect = .zero) {
        self.bundleID = bundleID
        self.role = role
        self.identifier = identifier
        self.text = text
        self.windowTitle = windowTitle
        x = Int(frame.minX.rounded()); y = Int(frame.minY.rounded())
        width = Int(frame.width.rounded()); height = Int(frame.height.rounded())
    }

    init?(_ element: AXUIElement) {
        guard let app = NSRunningApplication(processIdentifier: AX.pid(element)), let bundleID = app.bundleIdentifier else { return nil }
        let window = AX.element(element, kAXWindowAttribute)
        var frame = AX.frame(element) ?? .zero
        if let window, let windowFrame = AX.frame(window) {
            frame.origin = CGPoint(x: frame.minX - windowFrame.minX, y: frame.minY - windowFrame.minY)
        }
        let identifier = AX.string(element, kAXIdentifierAttribute)
        self.init(bundleID: bundleID, role: AX.string(element, kAXRoleAttribute),
                  identifier: identifier.isEmpty ? AX.string(element, "AXDOMIdentifier") : identifier,
                  text: AX.text(element), windowTitle: window.map { AX.string($0, kAXTitleAttribute) } ?? "", frame: frame)
    }

    /// Whether `other` is the same control. Identifiers and text are trusted first;
    /// a control with neither must be in the same place in a window with the same title.
    func matches(_ other: ElementSignature) -> Bool {
        guard bundleID == other.bundleID, role == other.role else { return false }
        if !identifier.isEmpty || !other.identifier.isEmpty { return identifier == other.identifier }
        if !text.isEmpty || !other.text.isEmpty { return text == other.text }
        return windowTitle == other.windowTitle && abs(x - other.x) <= 6 && abs(y - other.y) <= 6
            && abs(width - other.width) <= 6 && abs(height - other.height) <= 6
    }
}
