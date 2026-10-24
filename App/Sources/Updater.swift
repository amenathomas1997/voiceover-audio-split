// Updater.swift — Check for Updates: asks GitHub for the newest release of the app,
// and if it's newer than this copy, downloads its installer, checks that it arrived
// whole, and opens it in Apple's Installer, which checks Apple's notarization.
// Nothing is installed without the user choosing to. Only in the installer build from
// build.sh: copies from TestFlight or the App Store are updated there instead. Only GitHub is contacted, and nothing about
// the user is sent.

import AppKit
import CryptoKit

enum UpdateCheck {
    static let latestURL = URL(string: "https://api.github.com/repos/amenathomas1997/voiceover-audio-split/releases/latest")!
    static let releasesPage = URL(string: "https://github.com/amenathomas1997/voiceover-audio-split/releases")!
    /// The installer's name in every release.
    static let assetName = "VoiceOver-Audio-Split.pkg"

    struct Release: Equatable {
        /// "1.1", from the tag "v1.1".
        let version: String
        /// The build number, from a "Build 202610241900" line in the notes, if there is one.
        let build: String?
        let notes: String
        let installer: URL
        let size: Int
        /// The installer's SHA-256, as GitHub publishes it, if it does.
        let sha256: String?
    }

    /// The release described by GitHub's "latest release" answer, if it has the installer.
    static func parse(_ data: Data) -> Release? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tag = json["tag_name"] as? String,
              let assets = json["assets"] as? [[String: Any]],
              let asset = assets.first(where: { $0["name"] as? String == assetName }),
              let link = (asset["browser_download_url"] as? String).flatMap(URL.init(string:)),
              link.scheme == "https" else { return nil }
        let notes = json["body"] as? String ?? ""
        let digest = (asset["digest"] as? String).flatMap { $0.hasPrefix("sha256:") ? String($0.dropFirst(7)).lowercased() : nil }
        let version = tag.hasPrefix("v") || tag.hasPrefix("V") ? String(tag.dropFirst()) : tag
        return Release(version: version, build: build(in: notes), notes: notes, installer: link,
                       size: asset["size"] as? Int ?? 0, sha256: digest)
    }

    static func build(in notes: String) -> String? {
        guard let range = notes.range(of: #"Build (\d{6,})"#, options: .regularExpression) else { return nil }
        return String(notes[range].dropFirst("Build ".count))
    }

    /// Newer if its version is higher, or the same version with a higher build number.
    static func isNewer(_ release: Release, thanVersion version: String, build: String) -> Bool {
        let theirs = numbers(release.version), ours = numbers(version)
        for index in 0..<max(theirs.count, ours.count) {
            let a = index < theirs.count ? theirs[index] : 0, b = index < ours.count ? ours[index] : 0
            if a != b { return a > b }
        }
        guard let newBuild = release.build.flatMap({ Int($0) }), let ourBuild = Int(build) else { return false }
        return newBuild > ourBuild
    }

    private static func numbers(_ version: String) -> [Int] {
        version.split(separator: ".").map { Int($0.prefix { $0.isNumber }) ?? 0 }
    }

    /// The release notes as plain text to read in a dialog: no Markdown marks, links as their words.
    static func plain(_ notes: String) -> String {
        var text = notes.replacingOccurrences(of: #"\[([^\]]+)\]\([^)]+\)"#, with: "$1", options: .regularExpression)
        text = text.replacingOccurrences(of: #"(?m)^#+\s*"#, with: "", options: .regularExpression)
        text = text.replacingOccurrences(of: "**", with: "").replacingOccurrences(of: "`", with: "")
        text = text.replacingOccurrences(of: #"\n{3,}"#, with: "\n\n", options: .regularExpression)
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.count > 900 ? String(trimmed.prefix(900)) + "…" : trimmed
    }

    static func sha256(of file: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: file)
        defer { try? handle.close() }
        var hash = SHA256()
        while let chunk = try handle.read(upToCount: 1 << 20), !chunk.isEmpty { hash.update(data: chunk) }
        return hash.finalize().map { String(format: "%02x", $0) }.joined()
    }

    /// Installed from TestFlight or the App Store, which bring their own updates. Only the
    /// installer that build.sh makes (built with DIRECT_DOWNLOAD) can update itself: App Store
    /// and TestFlight builds never download or install code (App Store guideline 2.5.2).
    static var isStoreCopy: Bool {
        #if DIRECT_DOWNLOAD
        Bundle.main.appStoreReceiptURL.map { FileManager.default.fileExists(atPath: $0.path) } ?? false
        #else
        true
        #endif
    }

    static var version: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0" }
    static var buildNumber: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0" }
}

@MainActor
final class Updater {
    static let shared = Updater()

    private(set) var busy = false
    private var timer: Timer?

    /// Checks once a day while automatic checks are on, starting soon after launch.
    func startAutomaticChecks() {
        guard !UpdateCheck.isStoreCopy else { return }
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { _ in
            MainActor.assumeIsolated { Updater.shared.checkIfDue() }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 60) { self.checkIfDue() }
    }

    private func checkIfDue() {
        let preferences = Preferences.shared
        guard preferences.checkForUpdates, preferences.finishedSetup,
              Date().timeIntervalSince1970 - preferences.lastUpdateCheck > 20 * 3600 else { return }
        check(userInitiated: false)
    }

    /// Asks GitHub for the newest release. Automatic checks stay quiet unless there's an update.
    func check(userInitiated: Bool) {
        guard !busy else {
            if userInitiated { Announcer.say(String(localized: "Already checking for updates")) }
            return
        }
        guard !UpdateCheck.isStoreCopy else {
            if userInitiated { Announcer.say(String(localized: "This copy was installed from TestFlight or the App Store, which bring its updates.")) }
            return
        }
        busy = true
        if userInitiated {
            Tones.play(.status)
            Announcer.say(String(localized: "Checking for updates"))
        }
        Task {
            let release = await newerRelease(userInitiated: userInitiated)
            busy = false
            guard let release else { return }
            // A version the user chose to skip isn't offered again automatically.
            if !userInitiated && Preferences.shared.skippedUpdate == release.version + (release.build ?? "") { return }
            offer(release, userInitiated: userInitiated)
        }
    }

    /// The newest release, if it's newer than this copy; says why not when asked by the user.
    private func newerRelease(userInitiated: Bool) async -> UpdateCheck.Release? {
        var request = URLRequest(url: UpdateCheck.latestURL, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("VoiceOverAudioSplit/\(UpdateCheck.version)", forHTTPHeaderField: "User-Agent")
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200, let release = UpdateCheck.parse(data) else {
            log("Update check failed.")
            if userInitiated { Announcer.say(String(localized: "Couldn't check for updates. Check your internet connection, and try again later.")) }
            return nil
        }
        Preferences.shared.lastUpdateCheck = Date().timeIntervalSince1970
        guard UpdateCheck.isNewer(release, thanVersion: UpdateCheck.version, build: UpdateCheck.buildNumber) else {
            if userInitiated { Announcer.say(String(localized: "You have the latest version, \(UpdateCheck.version).")) }
            return nil
        }
        log("Update available: \(release.version) \(release.build ?? "").")
        return release
    }

    private func offer(_ release: UpdateCheck.Release, userInitiated: Bool) {
        Tones.play(.status)
        NSApp.activate()
        let alert = NSAlert()
        alert.messageText = String(localized: "VoiceOver Audio Split \(release.version) is available")
        let notes = UpdateCheck.plain(release.notes)
        alert.informativeText = String(localized: "You have version \(UpdateCheck.version). Install the update now? The app closes while it installs and opens again afterwards.")
            + (notes.isEmpty ? "" : "\n\n" + notes)
        alert.addButton(withTitle: String(localized: "Download and Install"))
        alert.addButton(withTitle: String(localized: "Later"))
        if !userInitiated { alert.addButton(withTitle: String(localized: "Skip This Version")) }
        switch alert.runModal() {
        case .alertFirstButtonReturn: install(release)
        case .alertThirdButtonReturn: Preferences.shared.skippedUpdate = release.version + (release.build ?? "")
        default: break
        }
    }

    private func install(_ release: UpdateCheck.Release) {
        busy = true
        Announcer.say(String(localized: "Downloading the update"))
        Task {
            defer { busy = false }
            do {
                let (download, response) = try await URLSession.shared.download(from: release.installer)
                guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
                // In the app's own temporary folder; the Installer can read it from there.
                let folder = FileManager.default.temporaryDirectory.appendingPathComponent("Update", isDirectory: true)
                try? FileManager.default.removeItem(at: folder)
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                let installer = folder.appendingPathComponent("VoiceOver Audio Split \(release.version).pkg")
                try FileManager.default.moveItem(at: download, to: installer)
                // It must arrive whole: the size, and the checksum when GitHub gives one.
                let size = (try? FileManager.default.attributesOfItem(atPath: installer.path)[.size] as? Int) ?? 0
                let hash = try await Task.detached { try UpdateCheck.sha256(of: installer) }.value
                guard release.size == 0 || size == release.size, release.sha256 == nil || hash == release.sha256 else {
                    try? FileManager.default.removeItem(at: folder)
                    log("Update download didn't match its checksum.")
                    return Announcer.say(String(localized: "The update didn't download correctly, so nothing was installed. Try again later."))
                }
                log("Update downloaded; opening the installer.")
                Tones.play(.device)
                Announcer.say(String(localized: "Opening the installer. Follow its steps; VoiceOver Audio Split closes while it installs and opens again afterwards."))
                let installerApp = URL(fileURLWithPath: "/System/Library/CoreServices/Installer.app")
                NSWorkspace.shared.open([installer], withApplicationAt: installerApp, configuration: NSWorkspace.OpenConfiguration()) { _, error in
                    guard error != nil else { return }
                    DispatchQueue.main.async {
                        log("Couldn't open the installer.")
                        Announcer.say(String(localized: "The installer couldn't be opened. Opening the download page instead."))
                        NSWorkspace.shared.open(UpdateCheck.releasesPage)
                    }
                }
            } catch {
                log("Update download failed.")
                Announcer.say(String(localized: "The update couldn't be downloaded. Check your internet connection, and try again later."))
            }
        }
    }
}
