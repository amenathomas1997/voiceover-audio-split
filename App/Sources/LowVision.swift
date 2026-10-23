// LowVision.swift — on-screen aids for people who use speech and sight together:
//   * Captions: a floating large-print strip showing what VoiceOver says
//     (built on speech history)
//   * Focus frame: a thick, high-visibility frame that follows the VoiceOver cursor
// Both float above other windows, ignore the mouse, and are left out of screen
// pictures so they never appear in image descriptions.

import AppKit
import SwiftUI

/// A borderless window that floats above everything on every Space and lets clicks through.
private func overlayWindow(_ frame: NSRect) -> NSPanel {
    let panel = NSPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
    panel.level = .screenSaver
    panel.isOpaque = false
    panel.backgroundColor = .clear
    panel.hasShadow = false
    panel.ignoresMouseEvents = true
    panel.sharingType = .none
    panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
    return panel
}

// MARK: - Captions

enum Captions {
    private static var panel: NSPanel?

    static var isShowing: Bool { panel != nil }

    static func show() {
        guard panel == nil, let screen = NSScreen.main else { return }
        // Captions come from speech history, so make sure it is on.
        Preferences.shared.speechHistory = true
        let width = screen.visibleFrame.width * 0.9
        let frame = NSRect(x: screen.visibleFrame.midX - width / 2, y: screen.visibleFrame.minY + 20,
                           width: width, height: 240)
        let panel = overlayWindow(frame)
        panel.contentView = NSHostingView(rootView: CaptionView())
        panel.orderFrontRegardless()
        self.panel = panel
    }

    static func hide() {
        panel?.orderOut(nil)
        panel = nil
    }
}

private struct CaptionView: View {
    @ObservedObject var history = SpeechHistory.shared
    @ObservedObject var preferences = Preferences.shared

    var body: some View {
        VStack {
            Spacer(minLength: 0)
            Text(history.phrases.first?.text ?? String(localized: "Captions are on"))
                .font(.system(size: CGFloat(preferences.captionSize), weight: .semibold))
                .foregroundStyle(preferences.readingTheme.foreground)
                .lineLimit(3)
                .minimumScaleFactor(0.5)
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity)
                .background(preferences.readingTheme.background.opacity(0.92), in: RoundedRectangle(cornerRadius: 16))
                .accessibilityHidden(true) // VoiceOver already said it.
        }
    }
}

// MARK: - Focus frame

enum FocusFrame {
    private static var panel: NSPanel?
    private static var timer: DispatchSourceTimer?
    private static var lastBounds: CGRect?

    static var isShowing: Bool { panel != nil }

    static func show() {
        guard panel == nil else { return }
        let panel = overlayWindow(.zero)
        panel.contentView = FrameView()
        self.panel = panel
        // VoiceOver has no "cursor moved" notification, so check its position a few times a second.
        let timer = DispatchSource.makeTimerSource(queue: DispatchQueue(label: "VoiceOverAudioSplit.focus-frame"))
        timer.schedule(deadline: .now(), repeating: .milliseconds(150))
        timer.setEventHandler {
            let bounds = NSWorkspace.shared.isVoiceOverEnabled ? VoiceOverText.cursorBounds() : nil
            DispatchQueue.main.async { move(to: bounds) }
        }
        timer.resume()
        self.timer = timer
    }

    static func hide() {
        timer?.cancel()
        timer = nil
        panel?.orderOut(nil)
        panel = nil
        lastBounds = nil
    }

    /// Redraws with the current color and thickness.
    static func refresh() {
        panel?.contentView?.needsDisplay = true
        if let lastBounds { place(lastBounds) }
    }

    private static func move(to bounds: CGRect?) {
        guard let panel else { return }
        guard let bounds, bounds.width > 2, bounds.height > 2 else {
            panel.orderOut(nil)
            return
        }
        guard bounds != lastBounds else { return }
        let moved = lastBounds != nil
        lastBounds = bounds
        place(bounds)
        panel.orderFrontRegardless()
        if moved && Preferences.shared.focusFrameFlash {
            panel.alphaValue = 0.3
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.25
                panel.animator().alphaValue = 1
            }
        }
    }

    /// VoiceOver gives top-left based screen coordinates; windows use bottom-left.
    private static func place(_ bounds: CGRect) {
        let margin = CGFloat(Preferences.shared.focusFrameThickness) + 4
        let screenHeight = NSScreen.screens.first?.frame.height ?? 0
        let frame = NSRect(x: bounds.minX - margin, y: screenHeight - bounds.maxY - margin,
                           width: bounds.width + margin * 2, height: bounds.height + margin * 2)
        panel?.setFrame(frame, display: true)
    }

    private final class FrameView: NSView {
        override func draw(_ dirtyRect: NSRect) {
            let preferences = Preferences.shared
            let thickness = CGFloat(preferences.focusFrameThickness)
            let path = NSBezierPath(roundedRect: bounds.insetBy(dx: thickness / 2 + 2, dy: thickness / 2 + 2),
                                    xRadius: 8, yRadius: 8)
            path.lineWidth = thickness
            // A thin dark outline keeps the frame visible on light and dark backgrounds.
            NSColor.black.withAlphaComponent(0.8).setStroke()
            let outline = path.copy() as! NSBezierPath
            outline.lineWidth = thickness + 4
            outline.stroke()
            color(preferences.focusFrameColor).setStroke()
            path.stroke()
        }

        private func color(_ choice: FrameColor) -> NSColor {
            switch choice {
            case .yellow: .systemYellow
            case .red: .systemRed
            case .magenta: .magenta
            case .cyan: .cyan
            case .green: .systemGreen
            case .orange: .systemOrange
            }
        }
    }
}
