// ScreenText.swift — reads the text in the front window with on-device text
// recognition: slides shared in a Zoom or Teams meeting, apps built without
// accessibility, remote desktops, and text inside videos. The text is spoken
// and kept for the Doc Reader. Nothing leaves the Mac.

import AppKit

enum ScreenText {
    /// The last text read, so it can be opened in the Doc Reader.
    private(set) static var lastText = ""

    static func readFrontWindow() {
        Tones.play(.status)
        Announcer.say("Reading the window")
        Task {
            do {
                let png = try await ScreenPicture.frontWindow()
                let text = await Task.detached {
                    NSBitmapImageRep(data: png)?.cgImage.map(TextRecognition.text) ?? ""
                }.value
                await MainActor.run {
                    lastText = text
                    Announcer.say(text.isEmpty ? "No text found in the window" : text)
                }
            } catch let failure as ScreenPicture.Failure {
                await MainActor.run { Announcer.say(failure.message) }
            } catch {
                await MainActor.run { Announcer.say("Couldn't read the window") }
            }
        }
    }

    static func openInDocReader() {
        guard !lastText.isEmpty else { return Announcer.say("Read a window first") }
        DocReaderModel.shared.load(lastText)
        (NSApp.delegate as? AppDelegate)?.showDocReader()
    }
}
