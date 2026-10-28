// AutoDescribe.swift — describe images automatically: when the VoiceOver cursor rests on
// a picture for a second (a photo in Photos, an image on a web page), the AI on this Mac
// describes it, without a key press. It makes going through a photo album much quicker.
// Only the on-device model is used, so pictures are never sent anywhere for this. Small
// icons are skipped, a picture already described is repeated from memory, and moving on
// before a description is ready cancels it.

import AppKit
import ImageIO

enum AutoDescribe {
    private static let queue = DispatchQueue(label: "VoiceOverAudioSplit.auto-describe")
    nonisolated(unsafe) private static var timer: DispatchSourceTimer?
    /// The picture the cursor is on, and since when.
    nonisolated(unsafe) private static var candidate: (key: String, since: Date)?
    /// The picture last described, so resting on it doesn't repeat it.
    nonisolated(unsafe) private static var described: String?
    /// Recent descriptions, by picture, to say again at once.
    nonisolated(unsafe) private static var cache: [String: String] = [:]
    nonisolated(unsafe) private static var cacheOrder: [String] = []
    nonisolated(unsafe) private static var permissionWarned = false

    /// How long the cursor rests on a picture before it's described.
    static let delay: TimeInterval = 1
    /// Smaller than this (in points, either way) counts as an icon, not a picture.
    static let minimumSide: CGFloat = 64

    /// Starts or stops watching the VoiceOver cursor, to match the setting.
    static func update(enabled: Bool) {
        let on = enabled && OnDeviceAI.canSeeImages
        if on && timer == nil {
            let source = DispatchSource.makeTimerSource(queue: queue)
            source.schedule(deadline: .now() + 0.5, repeating: .milliseconds(350))
            source.setEventHandler { check() }
            source.resume()
            timer = source
        } else if !on, let running = timer {
            running.cancel()
            timer = nil
            queue.async { candidate = nil; described = nil }
        }
    }

    /// Whether a size is a picture rather than an icon.
    static func isPictureSized(_ size: CGSize) -> Bool {
        size.width >= minimumSide && size.height >= minimumSide
    }

    /// Identifies a picture by its app, place and name, so the same one isn't described twice.
    static func key(pid: pid_t, frame: CGRect, name: String) -> String {
        "\(pid)|\(Int(frame.minX)),\(Int(frame.minY)),\(Int(frame.width)),\(Int(frame.height))|\(name)"
    }

    private static func check() {
        guard NSWorkspace.shared.isVoiceOverEnabled, let element = AX.underVoiceOverCursor(),
              let picture = picture(at: element) else {
            candidate = nil
            described = nil
            return
        }
        let now = Date()
        guard let current = candidate, current.key == picture.key else {
            candidate = (picture.key, now)
            return
        }
        guard now.timeIntervalSince(current.since) >= delay, described != picture.key else { return }
        described = picture.key
        if let known = cache[picture.key] { return say(known) }
        let key = picture.key
        Task {
            do {
                let png = try await ScreenPicture.underVoiceOverCursor()
                guard let image = cgImage(png) else { return }
                let text = try await OnDeviceAI.respond([.text(prompt), .image(image)], instructions: Claude.system)
                queue.async {
                    remember(text, for: key)
                    // Said only if the cursor is still on that picture.
                    if candidate?.key == key { say(text) }
                }
            } catch let failure as ScreenPicture.Failure {
                queue.async {
                    guard !permissionWarned else { return }
                    permissionWarned = true
                    say(failure.message)
                }
            } catch {
                log("Auto describe failed.")
            }
        }
    }

    static let prompt = """
    Describe this picture for a blind person in one or two short sentences. Start with the main subject. \
    Read any text in it. Don't start with "This image" or "The picture".
    """

    /// The picture under the cursor: an image, or a cell or group holding one (photos in
    /// Photos), big enough not to be an icon.
    private static func picture(at element: AXUIElement) -> (key: String, frame: CGRect)? {
        var pid: pid_t = 0
        AXUIElementGetPid(element, &pid)
        guard pid != getpid() else { return nil }
        let role = AX.string(element, kAXRoleAttribute)
        let image: AXUIElement?
        if role == kAXImageRole {
            image = element
        } else if [kAXCellRole, kAXGroupRole, "AXLink", kAXButtonRole].contains(role) {
            image = AX.children(element).first { AX.string($0, kAXRoleAttribute) == kAXImageRole }
        } else {
            image = nil
        }
        guard let image, let frame = AX.frame(image) ?? AX.frame(element), isPictureSized(frame.size) else { return nil }
        let name = AX.text(image)
        return (key(pid: pid, frame: frame, name: name), frame)
    }

    private static func remember(_ text: String, for key: String) {
        cache[key] = text
        cacheOrder.append(key)
        if cacheOrder.count > 100 { cache[cacheOrder.removeFirst()] = nil }
    }

    private static func say(_ text: String) {
        DispatchQueue.main.async { Announcer.say(text) }
    }

    private static func cgImage(_ data: Data) -> CGImage? {
        CGImageSourceCreateWithData(data as CFData, nil).flatMap { CGImageSourceCreateImageAtIndex($0, 0, nil) }
    }
}
