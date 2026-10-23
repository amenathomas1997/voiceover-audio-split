// Lessons.swift — VoiceOver Lessons: a course for someone new to VoiceOver, from
// turning it on to web pages, editing text and getting help. Each lesson explains a
// skill in plain words, then asks you to press the keys. For commands that are safe
// to carry out here, VoiceOver really does them once you get them right, in the
// lesson window's practice area and practice web page. Each lesson ends with a quick
// check, and finished lessons are remembered.
// Keys are caught at the same level as the app's shortcuts, ahead of VoiceOver, but
// only while a lesson runs and its window is in front.

import AppKit
import SwiftUI
import WebKit

/// A key with its modifiers. `vo` means Control and Option held together (or Caps Lock,
/// when it's set as the VO key in VoiceOver Utility).
struct KeyCombo: Hashable {
    let code: Int64
    var vo = true
    var shift = false
    var command = false
    var option = false

    /// The letter on this key on a US keyboard, which lessons name; nil for other keys.
    var letter: Character? {
        guard let name = Key.named(code)?.name, name.count == 1, let first = name.lowercased().first, first.isLetter else { return nil }
        return first
    }

    /// The letter a key press types on the user's own keyboard (A is in a different place on
    /// a French keyboard, Z on a German one). VoiceOver goes by the letter, so lessons do too.
    static func letter(typedBy event: NSEvent?) -> Character? {
        guard let typed = event?.charactersIgnoringModifiers?.lowercased(), typed.count == 1,
              let first = typed.first, first.isLetter, first.isASCII else { return nil }
        return first
    }

    func matches(keyCode: Int64, flags: CGEventFlags, letter typed: Character? = nil) -> Bool {
        // Letters by the letter typed; arrows, function keys and the rest by their key, which is the same everywhere.
        let rightKey = if let letter, let typed { typed == letter } else { keyCode == code }
        guard rightKey, flags.contains(.maskShift) == shift, flags.contains(.maskCommand) == command else { return false }
        if vo { return Self.isVO(flags) }
        return !flags.contains(.maskControl) && flags.contains(.maskAlternate) == option
    }

    static func isVO(_ flags: CGEventFlags) -> Bool {
        flags.contains([.maskControl, .maskAlternate]) || flags.contains(.maskAlphaShift)
    }

    /// "VO Command Shift H", "Option Left Arrow": what someone pressed, in words.
    static func describe(keyCode: Int64, flags: CGEventFlags, letter: Character? = nil) -> String {
        var parts: [String] = []
        let vo = isVO(flags)
        if vo { parts.append("VO") }
        if flags.contains(.maskCommand) { parts.append(String(localized: "Command")) }
        if flags.contains(.maskShift) { parts.append(String(localized: "Shift")) }
        if !vo && flags.contains(.maskAlternate) { parts.append(String(localized: "Option")) }
        if !vo && flags.contains(.maskControl) { parts.append(String(localized: "Control")) }
        parts.append(letter.map { String($0).uppercased() } ?? name(of: keyCode))
        return parts.joined(separator: " ")
    }

    static func name(of code: Int64) -> String {
        let special: [Int64: String] = [
            122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6", 98: "F7", 100: "F8",
            115: String(localized: "Home"), 119: String(localized: "End"), 48: String(localized: "Tab"),
            53: String(localized: "Escape"), 51: String(localized: "Delete"),
        ]
        return special[code] ?? Key.named(code)?.name ?? String(localized: "another key")
    }
}

struct LessonStep: Hashable {
    enum Kind: Hashable {
        /// Explanation, then Return to go on.
        case explain(String)
        /// Press these keys. `realKeys`: VoiceOver carries them out once they're right.
        case practice(task: String, keys: String, combo: KeyCombo, tip: String, realKeys: Bool)
        /// Do something for real, anywhere on the Mac; the lesson notices when it's done.
        case mission(task: String, check: Mission, tip: String)
    }
    let kind: Kind

    static func say(_ text: String) -> LessonStep { LessonStep(kind: .explain(text)) }
    static func press(_ task: String, _ keys: String, _ combo: KeyCombo, tip: String = "", real: Bool = false) -> LessonStep {
        LessonStep(kind: .practice(task: task, keys: keys, combo: combo, tip: tip, realKeys: real))
    }
    static func doIt(_ task: String, _ check: Mission, tip: String = "") -> LessonStep {
        LessonStep(kind: .mission(task: task, check: check, tip: tip))
    }
}

/// Something done for real, checked about once a second.
enum Mission: Hashable {
    case frontApp(String)
    case finderShowing(FinderPlace)
    case pressedPlay, checkedSubscribe, typedInField

    enum FinderPlace: Hashable { case downloads }

    func isDone(_ runner: LessonRunner) -> Bool {
        switch self {
        case .frontApp(let bundleID): return NSWorkspace.shared.frontmostApplication?.bundleIdentifier == bundleID
        case .pressedPlay: return runner.pressedPlay
        case .checkedSubscribe: return runner.subscribed
        case .typedInField: return runner.notes.trimmingCharacters(in: .whitespacesAndNewlines).count >= 2
        case .finderShowing(.downloads):
            guard let finder = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.finder").first,
                  NSWorkspace.shared.frontmostApplication == finder, let downloads = SystemEvents.downloadsFolder,
                  let window = AX.element(AX.application(finder.processIdentifier), kAXFocusedWindowAttribute) else { return false }
            return AX.string(window, kAXTitleAttribute) == FileManager.default.displayName(atPath: downloads.path)
        }
    }

    /// Checks that ask another app (Finder's window title) run off the main thread.
    var needsAccessibility: Bool { if case .finderShowing = self { true } else { false } }
}

struct Lesson: Identifiable, Hashable {
    let id: String
    let title: String
    let summary: String
    let steps: [LessonStep]

    var practice: [LessonStep] { steps.filter { if case .practice = $0.kind { true } else { false } } }

    /// Each practice step with an ID that stays the same between runs, for remembering mistakes.
    var practiceWithIDs: [(id: String, step: LessonStep)] {
        steps.enumerated().compactMap { index, step in
            if case .practice = step.kind { return ("\(id).\(index)", step) }
            return nil
        }
    }

    static let all: [Lesson] = [
        Lesson(id: "start", title: String(localized: "1. Getting started: the VO keys"),
               summary: String(localized: "Turning VoiceOver on and off, the VO keys, stopping speech, and keyboard help."), steps: [
            .say(String(localized: "Welcome. VoiceOver is the screen reader built into your Mac. It reads what's on the screen and lets you do everything from the keyboard. Command F5 turns it on and off. On a Mac with Touch ID, you can also hold Command and press Touch ID three times quickly.")),
            .say(String(localized: "Most VoiceOver commands use the VO keys: Control and Option, held down together. In these lessons, VO always means hold Control and Option. If you've set Caps Lock as your VO key in VoiceOver Utility, you can hold Caps Lock instead.")),
            .say(String(localized: "To stop VoiceOver talking, press Control on its own. You can do that at any time, for example during a long passage.")),
            .press(String(localized: "Turn on keyboard help, to explore keys safely"), String(localized: "VO K"), KeyCombo(code: 40),
                   tip: String(localized: "In keyboard help, every key is described instead of done. Press Escape to leave it.")),
            .press(String(localized: "Open the VoiceOver help menu"), String(localized: "VO H"), KeyCombo(code: 4),
                   tip: String(localized: "It lists VoiceOver's commands and has the VoiceOver Getting Started guide.")),
        ]),
        Lesson(id: "moving", title: String(localized: "2. Moving around and pressing things"),
               summary: String(localized: "The VoiceOver cursor, moving item by item, groups, and activating."), steps: [
            .say(String(localized: "VoiceOver has its own cursor, the VoiceOver cursor. It moves from item to item: buttons, text, checkboxes and more. VO Right Arrow moves to the next item, and VO Left Arrow to the previous one. This window's practice area has a few items to move through.")),
            .press(String(localized: "Move to the next item"), String(localized: "VO Right Arrow"), KeyCombo(code: 124), real: true),
            .press(String(localized: "Move to the previous item"), String(localized: "VO Left Arrow"), KeyCombo(code: 123), real: true),
            .say(String(localized: "Some items hold others, such as a toolbar, a list, a table or a web page. These are groups. To go inside a group, interact with it: VO Shift Down Arrow. To come back out, VO Shift Up Arrow. VoiceOver says in and out as you go.")),
            .press(String(localized: "Go inside a group"), String(localized: "VO Shift Down Arrow"), KeyCombo(code: 125, shift: true), real: true),
            .press(String(localized: "Come back out of the group"), String(localized: "VO Shift Up Arrow"), KeyCombo(code: 126, shift: true), real: true),
            .say(String(localized: "To press a button, check a box or follow a link, use VO Space. It does what a click does.")),
            .press(String(localized: "Press the item in the VoiceOver cursor"), String(localized: "VO Space"), KeyCombo(code: 49)),
            .doIt(String(localized: "Now for real: move to the Play button in the practice area, and press it with VO Space."), .pressedPlay,
                  tip: String(localized: "The practice area is further down this window. VO Right Arrow moves toward it.")),
            .say(String(localized: "To jump to the top or bottom of a window, use VO Home and VO End. On a laptop keyboard, add Fn: VO Fn Left Arrow is Home, and VO Fn Right Arrow is End.")),
            .press(String(localized: "Go to the top of the window"), String(localized: "VO Home, or VO Fn Left Arrow"), KeyCombo(code: 115), real: true),
        ]),
        Lesson(id: "reading", title: String(localized: "3. Reading text"),
               summary: String(localized: "Reading everything, lines, sentences, paragraphs, words and characters."), steps: [
            .say(String(localized: "When the VoiceOver cursor is on text, you can read it in pieces of different sizes. VO A reads everything from the cursor onward. Press Control to stop it.")),
            .press(String(localized: "Read everything from here"), String(localized: "VO A"), KeyCombo(code: 0), real: true),
            .say(String(localized: "For smaller pieces: VO L reads the line, VO S the sentence, VO P the paragraph, VO W the word and VO C the character. Press VO W twice to hear the word spelled, and VO C twice to hear the letter phonetically, like alpha or bravo.")),
            .press(String(localized: "Read the current line"), String(localized: "VO L"), KeyCombo(code: 37), real: true),
            .press(String(localized: "Read the current paragraph"), String(localized: "VO P"), KeyCombo(code: 35), real: true),
            .press(String(localized: "Read the current word"), String(localized: "VO W"), KeyCombo(code: 13), real: true),
            .press(String(localized: "Read the current character"), String(localized: "VO C"), KeyCombo(code: 8), real: true),
            .say(String(localized: "Missed something? VO Z says the last thing again, and VO Shift C copies it to the clipboard.")),
            .press(String(localized: "Repeat the last thing VoiceOver said"), String(localized: "VO Z"), KeyCombo(code: 6), real: true),
            .press(String(localized: "Copy the last thing VoiceOver said"), String(localized: "VO Shift C"), KeyCombo(code: 8, shift: true), real: true),
        ]),
        Lesson(id: "apps", title: String(localized: "4. Menus, the Dock and switching apps"),
               summary: String(localized: "The menu bar, menu extras, the Dock, shortcut menus, and moving between apps and windows."), steps: [
            .say(String(localized: "Every app has a menu bar at the top of the screen. VO M moves there. Left and Right Arrow choose a menu, Down Arrow opens it, Up and Down Arrow choose a command, Return uses it, and Escape closes the menu.")),
            .press(String(localized: "Go to the menu bar"), String(localized: "VO M"), KeyCombo(code: 46)),
            .say(String(localized: "Press VO M twice quickly for the menu extras: the icons at the right of the menu bar, such as Wi-Fi, sound, battery and this app's headphones. VO D goes to the Dock, where your apps are kept.")),
            .press(String(localized: "Go to the Dock"), String(localized: "VO D"), KeyCombo(code: 2)),
            .say(String(localized: "VO Shift M opens the shortcut menu for the item in the VoiceOver cursor. It's like a right-click.")),
            .press(String(localized: "Open the shortcut menu"), String(localized: "VO Shift M"), KeyCombo(code: 46, shift: true)),
            .say(String(localized: "To switch apps, hold Command and press Tab; each Tab moves to the next app, and letting go switches. Command Grave Accent switches between the windows of one app. VO F1 twice lists the open apps, and VO F2 twice lists the windows.")),
            .press(String(localized: "Switch to another app"), String(localized: "Command Tab"), KeyCombo(code: 48, vo: false, command: true)),
            .press(String(localized: "Switch to another window of this app"), String(localized: "Command Grave Accent"), KeyCombo(code: 50, vo: false, command: true)),
        ]),
        Lesson(id: "finding", title: String(localized: "5. Finding things: the rotor and item chooser"),
               summary: String(localized: "Jumping to headings, links and more with the rotor, the item chooser and find."), steps: [
            .say(String(localized: "The rotor is a quick way to jump around. Press VO U. Left and Right Arrow change the list, such as headings, links, form controls or windows. Up and Down Arrow choose an item, and Return goes there. Type a few letters to narrow the list, and press Escape to close it.")),
            .press(String(localized: "Open the rotor"), String(localized: "VO U"), KeyCombo(code: 32)),
            .say(String(localized: "The item chooser lists everything in the window. Press VO I, type part of a name, and press Return to go there.")),
            .press(String(localized: "Open the item chooser"), String(localized: "VO I"), KeyCombo(code: 34)),
            .say(String(localized: "To find text, press VO F, type what you're looking for, and press Return.")),
            .press(String(localized: "Find text"), String(localized: "VO F"), KeyCombo(code: 3)),
        ]),
        Lesson(id: "web", title: String(localized: "6. Web pages"),
               summary: String(localized: "Jumping by heading, link, form control and table, on a practice web page."), steps: [
            .say(String(localized: "Web pages can be long, so VoiceOver has keys that jump by kind of item. VO Command H goes to the next heading, VO Command L to the next link, VO Command J to the next form control, such as a text field or button, and VO Command T to the next table. Add Shift to go back: VO Command Shift H is the previous heading.")),
            .say(String(localized: "There's a practice web page at the bottom of this window. Move the VoiceOver cursor to it with VO Right Arrow, then go inside with VO Shift Down Arrow. When you're in it, press Return to go on.")),
            .press(String(localized: "Go to the next heading"), String(localized: "VO Command H"), KeyCombo(code: 4, command: true), real: true),
            .press(String(localized: "Go to the next link"), String(localized: "VO Command L"), KeyCombo(code: 37, command: true), real: true),
            .press(String(localized: "Go to the next form control"), String(localized: "VO Command J"), KeyCombo(code: 38, command: true), real: true),
            .press(String(localized: "Go to the next table"), String(localized: "VO Command T"), KeyCombo(code: 17, command: true), real: true),
            .press(String(localized: "Go back to the previous heading"), String(localized: "VO Command Shift H"), KeyCombo(code: 4, shift: true, command: true), real: true),
            .say(String(localized: "Inside a table, hold VO and use the arrow keys to move from cell to cell; VoiceOver reads the column heading as you go. On real websites, the rotor's headings list (VO U) is often the fastest way to get an overview.")),
        ]),
        Lesson(id: "quicknav", title: String(localized: "7. Quick Nav"),
               summary: String(localized: "Moving with the arrow keys alone, and single letters on web pages."), steps: [
            .say(String(localized: "Quick Nav lets you move with the arrow keys alone, without holding VO. Press Left Arrow and Right Arrow together to turn it on or off. With Quick Nav on, Left and Right Arrow move to the previous or next item, and Up and Down Arrow move by the kind of item chosen in the rotor.")),
            .say(String(localized: "Single-key Quick Nav goes further on web pages: H for the next heading, L for the next link, T for the next table, and Shift with the letter to go back. VO Q turns it on or off.")),
            .press(String(localized: "Turn single-key Quick Nav on or off"), String(localized: "VO Q"), KeyCombo(code: 12)),
            .say(String(localized: "Remember to turn Quick Nav off before typing, or letters move you around instead of typing. When you're in a text field, VoiceOver usually types normally anyway.")),
        ]),
        Lesson(id: "text", title: String(localized: "8. Typing and editing text"),
               summary: String(localized: "Moving the text cursor, selecting, copying, pasting and undoing."), steps: [
            .say(String(localized: "For this lesson, go to the practice text field in this window and type a sentence or two, so there's text to move through. Press Return when you're ready.")),
            .say(String(localized: "In a text field, the arrow keys move the text cursor, and VoiceOver reads as you go: Left and Right Arrow by letter, Up and Down Arrow by line. Option Left and Right Arrow move by word. Command Left and Right Arrow go to the start or end of the line, and Command Up and Down Arrow to the start or end of the text.")),
            .press(String(localized: "Move back one word"), String(localized: "Option Left Arrow"), KeyCombo(code: 123, vo: false, option: true), real: true),
            .press(String(localized: "Go to the end of the line"), String(localized: "Command Right Arrow"), KeyCombo(code: 124, vo: false, command: true), real: true),
            .press(String(localized: "Go to the start of the text"), String(localized: "Command Up Arrow"), KeyCombo(code: 126, vo: false, command: true), real: true),
            .say(String(localized: "Add Shift to select as you move: Shift Option Right Arrow selects the next word. Then Command C copies, Command X cuts, Command V pastes, and Command Z undoes. VoiceOver says what's selected.")),
            .press(String(localized: "Select the next word"), String(localized: "Shift Option Right Arrow"), KeyCombo(code: 124, vo: false, shift: true, option: true), real: true),
            .press(String(localized: "Copy"), String(localized: "Command C"), KeyCombo(code: 8, vo: false, command: true), real: true),
            .press(String(localized: "Undo"), String(localized: "Command Z"), KeyCombo(code: 6, vo: false, command: true), real: true),
            .doIt(String(localized: "Now for real: type a few words in the practice text field."), .typedInField,
                  tip: String(localized: "VoiceOver says each letter as you type. If Quick Nav is on, turn it off first.")),
            .say(String(localized: "In the text field, try the keys from this lesson for real: move by word, select, copy and undo. VO L reads the line you're on, and VO F3 describes the field.")),
        ]),
        Lesson(id: "help", title: String(localized: "9. Getting help and staying in control"),
               summary: String(localized: "Bringing the VoiceOver cursor and keyboard focus together, describing things, locking the VO keys, and VoiceOver Utility."), steps: [
            .say(String(localized: "The VoiceOver cursor and the keyboard focus can end up in different places. VO Shift F4 brings the VoiceOver cursor to the keyboard focus. VO Command F4 brings the keyboard focus to the VoiceOver cursor. On a laptop, hold Fn as well for the F keys.")),
            .press(String(localized: "Move the VoiceOver cursor to the keyboard focus"), String(localized: "VO Shift F4"), KeyCombo(code: 118, shift: true), real: true),
            .press(String(localized: "Move the keyboard focus to the VoiceOver cursor"), String(localized: "VO Command F4"), KeyCombo(code: 118, command: true), real: true),
            .say(String(localized: "To find out where you are: VO F3 describes the item in the VoiceOver cursor, VO F2 the window, and VO F1 the app.")),
            .press(String(localized: "Describe the item in the VoiceOver cursor"), String(localized: "VO F3"), KeyCombo(code: 99), real: true),
            .press(String(localized: "Describe the window"), String(localized: "VO F2"), KeyCombo(code: 120), real: true),
            .say(String(localized: "Tired of holding VO? VO Semicolon locks the VO keys, so every key acts as if you're holding them. Press it again to unlock.")),
            .press(String(localized: "Lock or unlock the VO keys"), String(localized: "VO Semicolon"), KeyCombo(code: 41)),
            .say(String(localized: "VO F8 opens VoiceOver Utility, where you change voices, speaking rate, how much is said and much more. VO H, then H again, opens the Commands menu with every command, and you can type to search it. If VoiceOver ever stops responding, this app's Restart VoiceOver command fixes it.")),
            .press(String(localized: "Open VoiceOver Utility"), String(localized: "VO F8"), KeyCombo(code: 100)),
        ]),
        Lesson(id: "finder", title: String(localized: "10. Finder and files"),
               summary: String(localized: "Opening Finder, moving through files, opening and going back, common folders, and the Trash."), steps: [
            .say(String(localized: "Finder is where your files and folders are kept. It's always running. To bring it to the front, go to the Dock with VO D; Finder is the first item. Press VO Space to open it.")),
            .doIt(String(localized: "Bring Finder to the front, for real."), .frontApp("com.apple.finder"),
                  tip: String(localized: "VO D, then VO Space on Finder. Come back to the lessons with Command Tab when you hear Done.")),
            .say(String(localized: "In a Finder window, move between files with the arrow keys; VoiceOver reads each name. Command Down Arrow opens the selected file or folder, and Command Up Arrow goes back to the folder it's in. Space shows a Quick Look preview, and Space again closes it.")),
            .press(String(localized: "Open the selected item"), String(localized: "Command Down Arrow"), KeyCombo(code: 125, vo: false, command: true)),
            .press(String(localized: "Go back to the folder it's in"), String(localized: "Command Up Arrow"), KeyCombo(code: 126, vo: false, command: true)),
            .say(String(localized: "Finder has keys for the usual places: Command Shift A opens Applications, Command Shift D the Desktop, Option Command L Downloads, and Command Shift H your home folder. Command Shift G lets you type the path of any folder.")),
            .press(String(localized: "Open the Applications folder"), String(localized: "Command Shift A"), KeyCombo(code: 0, vo: false, shift: true, command: true)),
            .press(String(localized: "Open the Downloads folder"), String(localized: "Option Command L"), KeyCombo(code: 37, vo: false, command: true, option: true)),
            .press(String(localized: "Go to a folder by typing its path"), String(localized: "Command Shift G"), KeyCombo(code: 5, vo: false, shift: true, command: true)),
            .doIt(String(localized: "Now for real: show your Downloads folder in Finder."), .finderShowing(.downloads),
                  tip: String(localized: "Switch to Finder with Command Tab, then press Option Command L.")),
            .say(String(localized: "To move a file to the Trash, select it and press Command Delete; Command Z puts it back. To rename a file, select it, press Return, type the new name, and press Return again.")),
            .press(String(localized: "Move the selected item to the Trash"), String(localized: "Command Delete"), KeyCombo(code: 51, vo: false, command: true)),
        ]),
        Lesson(id: "safari", title: String(localized: "11. Safari and websites"),
               summary: String(localized: "The address field, tabs, going back, finding on a page, and Reader."), steps: [
            .say(String(localized: "Safari is the Mac's web browser. Command L goes to the address field: type a web address or a search, and press Return. Command T opens a new tab and Command W closes it. Command Left Bracket goes back a page, and Command R loads it again.")),
            .press(String(localized: "Go to the address field"), String(localized: "Command L"), KeyCombo(code: 37, vo: false, command: true)),
            .press(String(localized: "Open a new tab"), String(localized: "Command T"), KeyCombo(code: 17, vo: false, command: true)),
            .press(String(localized: "Close the tab"), String(localized: "Command W"), KeyCombo(code: 13, vo: false, command: true)),
            .press(String(localized: "Go back a page"), String(localized: "Command Left Bracket"), KeyCombo(code: 33, vo: false, command: true)),
            .press(String(localized: "Find text on the page"), String(localized: "Command F"), KeyCombo(code: 3, vo: false, command: true)),
            .say(String(localized: "When a page loads, VoiceOver starts reading it. Most sites start with menus and links, so jump to the content: VO Command H for the next heading, or the rotor, VO U, for a list of headings, links or landmarks. On articles, Reader shows just the text: Command Shift R.")),
            .press(String(localized: "Show the page in Reader"), String(localized: "Command Shift R"), KeyCombo(code: 15, vo: false, shift: true, command: true)),
            .doIt(String(localized: "Now for real: open Safari."), .frontApp("com.apple.Safari"),
                  tip: String(localized: "Use Spotlight: Command Space, type Safari, and press Return. Come back here with Command Tab afterwards.")),
        ]),
        Lesson(id: "dialogs", title: String(localized: "12. Dialogs, forms and the keyboard"),
               summary: String(localized: "Moving between controls with Tab, checkboxes, default buttons and cancelling."), steps: [
            .say(String(localized: "Dialogs and forms are made of controls: text fields, checkboxes, pop-up menus and buttons. Tab moves the keyboard focus to the next control, and Shift Tab to the previous one. For Tab to reach every control, turn on Keyboard navigation in System Settings, Keyboard.")),
            .press(String(localized: "Move to the next control"), String(localized: "Tab"), KeyCombo(code: 48, vo: false)),
            .press(String(localized: "Move to the previous control"), String(localized: "Shift Tab"), KeyCombo(code: 48, vo: false, shift: true)),
            .say(String(localized: "On a checkbox, Space checks or unchecks it. In most dialogs, Return presses the default button, such as OK or Save, and Escape or Command Period cancels.")),
            .press(String(localized: "Cancel a dialog"), String(localized: "Command Period"), KeyCombo(code: 47, vo: false, command: true)),
            .doIt(String(localized: "Now for real: check the Subscribe box in the practice area."), .checkedSubscribe,
                  tip: String(localized: "Move to it with VO Right Arrow, then press VO Space, or Space if it has the keyboard focus.")),
            .say(String(localized: "When you save a document, the save dialog asks for a name. Type it, then Tab to choose where. Command Shift G there lets you type a folder's path, just like in Finder.")),
        ]),
        Lesson(id: "windows", title: String(localized: "13. Opening apps and handling windows"),
               summary: String(localized: "Spotlight, and closing, minimizing, hiding and quitting."), steps: [
            .say(String(localized: "Spotlight opens apps and finds files. Press Command Space, type part of an app's name, and press Return. It also does sums and conversions: type 12 times 8, or 5 miles in kilometres.")),
            .press(String(localized: "Open Spotlight"), String(localized: "Command Space"), KeyCombo(code: 49, vo: false, command: true)),
            .doIt(String(localized: "Now for real: open TextEdit with Spotlight."), .frontApp("com.apple.TextEdit"),
                  tip: String(localized: "Command Space, type TextEdit, press Return. Come back here with Command Tab afterwards.")),
            .say(String(localized: "Window keys that work in almost every app: Command W closes the window, Command M minimizes it, Command H hides the whole app, and Command Q quits it. Command N usually makes a new window or document, and Command Comma opens the app's settings.")),
            .press(String(localized: "Quit the app"), String(localized: "Command Q"), KeyCombo(code: 12, vo: false, command: true)),
            .press(String(localized: "Minimize the window"), String(localized: "Command M"), KeyCombo(code: 46, vo: false, command: true)),
            .press(String(localized: "Open the app's settings"), String(localized: "Command Comma"), KeyCombo(code: 43, vo: false, command: true)),
            .say(String(localized: "If an app stops responding, Option Command Escape opens Force Quit Applications, where you can choose the app and quit it.")),
            .press(String(localized: "Open Force Quit Applications"), String(localized: "Option Command Escape"), KeyCombo(code: 53, vo: false, command: true, option: true)),
        ]),
        Lesson(id: "mail", title: String(localized: "14. Mail"),
               summary: String(localized: "Reading the message list, writing, replying and sending."), steps: [
            .say(String(localized: "Mail is the Mac's email app. In the message list, Up and Down Arrow move between messages, and VoiceOver reads who each is from and its subject. To read a message, move to the message area with VO Right Arrow and read it with VO A.")),
            .say(String(localized: "Command N starts a new message. In it, Tab moves from the To field to Subject and then to the message itself. Command Shift D sends it. Command R replies to a message, and Command Shift R replies to everyone.")),
            .press(String(localized: "Start a new message"), String(localized: "Command N"), KeyCombo(code: 45, vo: false, command: true)),
            .press(String(localized: "Reply to a message"), String(localized: "Command R"), KeyCombo(code: 15, vo: false, command: true)),
            .press(String(localized: "Send the message"), String(localized: "Command Shift D"), KeyCombo(code: 2, vo: false, shift: true, command: true)),
        ]),
        Lesson(id: "customize", title: String(localized: "15. Making VoiceOver your own"),
               summary: String(localized: "Speech rate and voice, verbosity, VoiceOver Utility, Commanders, Activities and braille displays."), steps: [
            .say(String(localized: "You can change how VoiceOver sounds without leaving what you're doing. Hold VO and Command and press Right or Left Arrow to choose a speech setting, such as rate, pitch or volume. Then VO Command Up or Down Arrow changes it.")),
            .press(String(localized: "Choose the next speech setting"), String(localized: "VO Command Right Arrow"), KeyCombo(code: 124, command: true), real: true),
            .press(String(localized: "Change the speech setting"), String(localized: "VO Command Up Arrow"), KeyCombo(code: 126, command: true)),
            .say(String(localized: "Verbosity is how much VoiceOver says about each item. VO V opens the verbosity rotor, to change it quickly, with Left and Right Arrow to choose and Up and Down Arrow to change.")),
            .press(String(localized: "Open the verbosity rotor"), String(localized: "VO V"), KeyCombo(code: 9)),
            .say(String(localized: "For full control, open VoiceOver Utility with VO F8. Under Speech you can choose voices and download better ones. Under Verbosity, how much is said, including punctuation and hints. Commanders let you give your own keys, trackpad gestures or number pad keys to any command. Activities change VoiceOver's settings by themselves in a particular app or website.")),
            .say(String(localized: "Braille displays work too: connect one with USB or Bluetooth, and set it up in VoiceOver Utility under Braille. You've now covered the essentials. The review that follows mixes everything, and the more help section lists Apple's VoiceOver guide and AppleVis.")),
        ]),
    ]

    /// The last lesson: a mixed review of everything, without the keys being said,
    /// starting with the keys you've missed before.
    static let review = Lesson(id: "review", title: String(localized: "16. Review: everything so far"),
                               summary: String(localized: "A mixed quiz from all the lessons, starting with what you've missed."), steps: [])
    static var course: [Lesson] { all + [review] }

    /// Every practice step in the course, by ID.
    static var allPractice: [(id: String, step: LessonStep)] { all.flatMap(\.practiceWithIDs) }
}

final class LessonRunner: ObservableObject {
    static let shared = LessonRunner()

    enum Phase: Equatable { case idle, explaining, checking, done }

    @Published private(set) var phase = Phase.idle
    @Published private(set) var lesson: Lesson?
    @Published private(set) var stepNumber = 0
    @Published private(set) var stepCount = 0
    /// What's being said now, also shown on screen and on braille displays.
    @Published private(set) var text = ""
    @Published private(set) var score = ""

    // The practice area's controls, so real tasks can see what was done.
    @Published var pressedPlay = false
    @Published var subscribed = false
    @Published var notes = ""

    /// The lesson window: keys are only taken while it's in front.
    weak var window: NSWindow?

    private var steps: [LessonStep] = []
    /// The practice ID of each step (empty for explanations and tasks), for remembering mistakes.
    private var stepIDs: [String] = []
    private var index = 0
    private var checkRight = 0
    private var wrongTries = 0
    private var session = 0
    private var missionTimer: Timer?

    // MARK: Running

    func start(_ lesson: Lesson, onlyMissed: Bool = false) {
        PracticeModel.shared.stop()
        TypingTrainer.shared.stop()
        stopMission()
        self.lesson = lesson
        session += 1
        index = 0
        checkRight = 0
        if lesson.id == Lesson.review.id {
            let missed = Set(Preferences.shared.lessonsMissed)
            let all = Lesson.allPractice
            let pick = onlyMissed ? all.filter { missed.contains($0.id) }.shuffled()
                                  : (all.filter { missed.contains($0.id) }.shuffled() + all.filter { !missed.contains($0.id) }.shuffled())
            let chosen = Array(pick.prefix(onlyMissed ? 20 : 15))
            steps = chosen.map(\.step)
            stepIDs = chosen.map(\.id)
            phase = .checking
        } else {
            steps = lesson.steps
            stepIDs = lesson.steps.indices.map { index in
                if case .practice = lesson.steps[index].kind { return "\(lesson.id).\(index)" }
                return ""
            }
            phase = .explaining
        }
        stepCount = steps.count
        Hotkeys.keyObserver = { [weak self] keyCode, flags, event in
            self?.handle(keyCode, flags, letter: KeyCombo.letter(typedBy: event)) ?? false
        }
        let intro = String(localized: "\(lesson.title). Press Return to go on, R to hear something again, and Escape to stop.")
        say(intro)
        let thisSession = session
        DispatchQueue.main.asyncAfter(deadline: .now() + 4.5) { [weak self] in
            guard self?.session == thisSession else { return }
            self?.present()
        }
    }

    func stop() {
        guard phase != .idle && phase != .done else { return }
        Hotkeys.keyObserver = nil
        stopMission()
        session += 1
        phase = .idle
        say(String(localized: "Lesson stopped. You can pick it up again any time."))
    }

    private var current: LessonStep? { index < steps.count ? steps[index] : nil }
    private var currentID: String { index < stepIDs.count ? stepIDs[index] : "" }

    private func present() {
        guard let step = current else { return lessonPartDone() }
        stepNumber = index + 1
        wrongTries = 0
        switch step.kind {
        case .explain(let words):
            say(words)
        case .practice(let task, let keys, _, let tip, _):
            if phase == .checking {
                say(String(localized: "\(stepNumber). \(task)?"))
            } else {
                say([String(localized: "Try it: \(task). Press \(keys)."), tip].filter { !$0.isEmpty }.joined(separator: " "))
            }
        case .mission(let task, let check, let tip):
            say([task, tip, String(localized: "Press Return here to skip it.")].filter { !$0.isEmpty }.joined(separator: " "))
            watch(check)
        }
    }

    // MARK: Real tasks

    private func watch(_ mission: Mission) {
        stopMission()
        let thisSession = session
        let step = index
        // Done already (for example Finder is in front): notice it after the instructions.
        missionTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let self, self.session == thisSession, self.index == step else { return }
            if mission.needsAccessibility {
                DispatchQueue.global(qos: .userInitiated).async {
                    let done = mission.isDone(self)
                    DispatchQueue.main.async { if done, self.session == thisSession, self.index == step { self.missionDone() } }
                }
            } else if mission.isDone(self) {
                self.missionDone()
            }
        }
    }

    private func missionDone() {
        stopMission()
        Tones.play(.device)
        say(String(localized: "Done! Well done."))
        advance(after: 2.5)
    }

    private func stopMission() {
        missionTimer?.invalidate()
        missionTimer = nil
    }

    // MARK: Moving on

    private func advance(after seconds: Double) {
        let thisSession = session
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { [weak self] in
            guard let self, self.session == thisSession else { return }
            self.index += 1
            self.present()
        }
    }

    /// The lesson's steps are done: on to its quick check, or finished.
    private func lessonPartDone() {
        guard let lesson else { return }
        if phase == .explaining && !lesson.practice.isEmpty {
            phase = .checking
            let checks = lesson.practiceWithIDs.shuffled()
            steps = checks.map(\.step)
            stepIDs = checks.map(\.id)
            stepCount = steps.count
            index = 0
            checkRight = 0
            say(String(localized: "Quick check. I'll say a task without the keys; press them. Press R if you want to hear it again."))
            let thisSession = session
            DispatchQueue.main.asyncAfter(deadline: .now() + 4.5) { [weak self] in
                guard let self, self.session == thisSession else { return }
                self.present()
            }
            return
        }
        finish()
    }

    private func finish() {
        guard let lesson else { return }
        Hotkeys.keyObserver = nil
        stopMission()
        session += 1
        phase = .done
        score = String(localized: "\(checkRight) of \(steps.count) right first time")
        var done = Preferences.shared.lessonsDone
        if !done.contains(lesson.id) { done.append(lesson.id) }
        Preferences.shared.lessonsDone = done
        let course = Lesson.course
        let next = course.firstIndex(of: lesson).flatMap { $0 + 1 < course.count ? course[$0 + 1] : nil }
        let missed = Preferences.shared.lessonsMissed.count
        var message = String(localized: "Lesson finished. \(score).")
        if let next { message += " " + String(localized: "Next: \(next.title).") }
        else { message += " " + String(localized: "That's the whole course. Well done!") }
        if missed > 0 { message += " " + String(localized: "Practice what I missed has \(missed) keys to go over.") }
        Tones.play(.device)
        say(message)
    }

    // MARK: Keys

    /// Return, R and Escape steer the lesson; while practicing, the answer is checked.
    /// Everything else goes through, so VoiceOver works normally during explanations.
    private func handle(_ keyCode: Int64, _ flags: CGEventFlags, letter: Character?) -> Bool {
        guard NSApp.isActive, window == nil || NSApp.keyWindow === window else { return false }
        let plain = flags.intersection([.maskCommand, .maskControl, .maskAlternate, .maskShift]).isEmpty && !flags.contains(.maskAlphaShift)
        if keyCode == Key.escape && plain {
            DispatchQueue.main.async { self.stop() }
            return true
        }
        // Typing in the practice text field: letters go to the field; Return still steers the lesson.
        if plain && keyCode != 36 && NSApp.keyWindow?.firstResponder is NSTextView { return false }
        if plain && (letter == "r" || (letter == nil && keyCode == 15)) { // R
            DispatchQueue.main.async { self.repeatCurrent() }
            return true
        }
        guard let step = current else { return false }
        switch step.kind {
        case .explain:
            guard plain && keyCode == 36 else { return false } // Return
            DispatchQueue.main.async { self.index += 1; self.present() }
            return true
        case .mission:
            guard plain && keyCode == 36 else { return false } // Return skips the task.
            DispatchQueue.main.async {
                self.stopMission()
                self.say(String(localized: "Skipped."))
                self.advance(after: 1)
            }
            return true
        case .practice(let task, let keys, let combo, _, let real):
            if plain && keyCode == 36 {
                DispatchQueue.main.async { self.say(String(localized: "\(task): press \(keys).")) }
                return true
            }
            // Only judge real attempts: something held with the key, or the keys asked for.
            let attempt = KeyCombo.isVO(flags) || flags.contains(.maskCommand) || flags.contains(.maskAlternate)
                || flags.contains(.maskShift) || combo.matches(keyCode: keyCode, flags: flags, letter: letter) || keyCode == 48
            guard attempt else { return false }
            if combo.matches(keyCode: keyCode, flags: flags, letter: letter) {
                DispatchQueue.main.async { self.right(real: real && self.phase == .explaining) }
                // Let VoiceOver really do it, where that's safe.
                return !(real && phase == .explaining)
            }
            let pressed = KeyCombo.describe(keyCode: keyCode, flags: flags, letter: letter)
            DispatchQueue.main.async { self.wrong(pressed: pressed, task: task, keys: keys, combo: combo) }
            return true
        }
    }

    private func right(real: Bool) {
        guard current != nil else { return }
        if wrongTries == 0 && phase == .checking {
            checkRight += 1
            remember(currentID, missed: false)
        }
        Tones.play(.louder)
        if real {
            // VoiceOver is speaking the result; give it time.
            advance(after: 3)
        } else {
            say(String(localized: "Right."))
            advance(after: 1.2)
        }
    }

    private func wrong(pressed: String, task: String, keys: String, combo: KeyCombo) {
        wrongTries += 1
        remember(currentID, missed: true)
        Tones.play(.quieter)
        var message = String(localized: "That was \(pressed). \(task): press \(keys).")
        // A second miss: say exactly what to hold and what to press.
        if wrongTries >= 2 { message += " " + Self.howToPress(combo) }
        say(message)
    }

    /// "Hold Control, Option and Command, then press H."
    static func howToPress(_ combo: KeyCombo) -> String {
        var held: [String] = []
        if combo.vo { held += [String(localized: "Control"), String(localized: "Option")] }
        if combo.option && !combo.vo { held.append(String(localized: "Option")) }
        if combo.command { held.append(String(localized: "Command")) }
        if combo.shift { held.append(String(localized: "Shift")) }
        let key = KeyCombo.name(of: combo.code)
        guard !held.isEmpty else { return String(localized: "Press \(key) on its own.") }
        let list = ListFormatter.localizedString(byJoining: held)
        var hint = String(localized: "Hold \(list), keep holding, then press \(key).")
        if combo.vo { hint += " " + String(localized: "Control and Option are side by side at the bottom left of the keyboard.") }
        if [122, 120, 99, 118, 96, 100].contains(combo.code) {
            hint += " " + String(localized: "On a laptop, also hold Fn for the F keys.")
        }
        return hint
    }

    private func remember(_ id: String, missed: Bool) {
        guard !id.isEmpty else { return }
        var list = Preferences.shared.lessonsMissed
        if missed { if !list.contains(id) { list.append(id) } } else { list.removeAll { $0 == id } }
        if list != Preferences.shared.lessonsMissed { Preferences.shared.lessonsMissed = list }
    }

    func repeatCurrent() {
        guard let step = current else { return say(text) }
        switch step.kind {
        case .explain(let words): say(words)
        case .mission(let task, _, let tip): say([task, tip].filter { !$0.isEmpty }.joined(separator: " "))
        case .practice(let task, let keys, _, let tip, _):
            say(phase == .checking ? String(localized: "\(task)? The keys are \(keys).")
                                   : [String(localized: "\(task): press \(keys)."), tip].filter { !$0.isEmpty }.joined(separator: " "))
        }
    }

    private func say(_ words: String) {
        text = words
        Announcer.say(words)
    }
}

/// Words a beginner meets in the lessons.
enum Glossary {
    static let terms: [(String, String)] = [
        (String(localized: "VO keys"), String(localized: "Control and Option held together, or Caps Lock if you've chosen it. Most VoiceOver commands start with them.")),
        (String(localized: "VoiceOver cursor"), String(localized: "Where VoiceOver is reading. It moves with VO and the arrow keys, and is shown as a dark outline.")),
        (String(localized: "Keyboard focus"), String(localized: "Where your typing goes. It moves with Tab and with clicks. It's usually in the same place as the VoiceOver cursor, but not always.")),
        (String(localized: "Interact"), String(localized: "Going inside a group, such as a table, a list or a web page, with VO Shift Down Arrow, so you can move among the items in it.")),
        (String(localized: "Rotor"), String(localized: "A menu of lists, such as headings, links and windows, opened with VO U, to jump straight to something.")),
        (String(localized: "Quick Nav"), String(localized: "A mode where the arrow keys, or single letters on web pages, move you around without holding VO.")),
        (String(localized: "Item chooser"), String(localized: "A searchable list of everything in the window, opened with VO I.")),
        (String(localized: "Verbosity"), String(localized: "How much VoiceOver says about each item, such as its type and hints. Changed with VO V or in VoiceOver Utility.")),
        (String(localized: "Menu extras"), String(localized: "The icons at the right of the menu bar, such as Wi-Fi, sound and battery. VO M twice goes there.")),
    ]
}

// MARK: - Window

struct LessonsView: View {
    @ObservedObject var runner = LessonRunner.shared
    @ObservedObject var preferences = Preferences.shared

    var body: some View {
        Form {
            if runner.phase == .idle || runner.phase == .done {
                Section(String(localized: "VoiceOver Lessons")) {
                    Text(String(localized: "A course for learning VoiceOver from the beginning. Each lesson explains a skill, then you try the keys, and some ask you to do a task for real. Start with lesson 1, or pick any lesson."))
                        .font(.caption).foregroundStyle(.secondary)
                    Text(String(localized: "\(preferences.lessonsDone.count) of \(Lesson.course.count) lessons done"))
                    ForEach(Lesson.course) { lesson in
                        let done = preferences.lessonsDone.contains(lesson.id)
                        Button(done ? String(localized: "\(lesson.title), done") : lesson.title) { runner.start(lesson) }
                            .accessibilityHint(lesson.summary)
                    }
                    if !preferences.lessonsMissed.isEmpty {
                        Button(String(localized: "Practice What I Missed (\(preferences.lessonsMissed.count))")) {
                            runner.start(Lesson.review, onlyMissed: true)
                        }
                    }
                    if !runner.score.isEmpty { Text(runner.text) }
                }
            } else {
                Section(runner.lesson?.title ?? "") {
                    Text(runner.phase == .checking ? String(localized: "Quick check, \(runner.stepNumber) of \(runner.stepCount)")
                                                   : String(localized: "Step \(runner.stepNumber) of \(runner.stepCount)"))
                    Text(runner.text).font(.title3)
                    HStack {
                        Button(String(localized: "Say It Again")) { runner.repeatCurrent() }
                        Button(String(localized: "Stop Lesson")) { runner.stop() }
                    }
                    Text(String(localized: "Return goes on, R repeats, Escape stops."))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }

            Section(String(localized: "Practice area")) {
                Text(String(localized: "Practice area")).font(.headline).accessibilityAddTraits(.isHeader)
                Text(String(localized: "This is a short paragraph to practice reading. It has three sentences. Try reading it by line, by sentence and by word."))
                HStack {
                    Button(String(localized: "Play")) { runner.pressedPlay = true; Announcer.say(String(localized: "You pressed Play.")) }
                    Button(String(localized: "Pause")) { Announcer.say(String(localized: "You pressed Pause.")) }
                    Toggle(String(localized: "Subscribe"), isOn: $runner.subscribed)
                }
                TextField(String(localized: "Practice text field"), text: $runner.notes, axis: .vertical)
                    .lineLimit(3...6)
            }

            Section(String(localized: "Practice web page")) {
                PracticeWebPage()
                    .frame(height: 320)
                    .accessibilityLabel(String(localized: "Practice web page"))
            }

            Section(String(localized: "Words to know")) {
                ForEach(Glossary.terms, id: \.0) { term, meaning in
                    Text(String(localized: "\(term): \(meaning)"))
                }
            }

            Section(String(localized: "More help")) {
                Link(String(localized: "Apple's VoiceOver User Guide for Mac"), destination: URL(string: "https://support.apple.com/guide/voiceover/welcome/mac")!)
                Link(String(localized: "AppleVis: guides and a community of blind Apple users"), destination: URL(string: "https://www.applevis.com")!)
                Link(String(localized: "Apple Accessibility support"), destination: URL(string: "https://support.apple.com/accessibility")!)
                Text(String(localized: "VoiceOver has its own interactive tutorial too, VoiceOver Quick Start: VO Command F8 (add Fn on a laptop). The VoiceOver help menu, VO H, has the Getting Started guide."))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 600, height: 760)
    }
}

/// A small web page with headings, links, a form and a table, for lesson 6.
struct PracticeWebPage: NSViewRepresentable {
    func makeNSView(context: Context) -> WKWebView {
        let view = WKWebView(frame: .zero, configuration: WKWebViewConfiguration())
        view.loadHTMLString(Self.html, baseURL: nil)
        return view
    }

    func updateNSView(_ view: WKWebView, context: Context) {}

    static var html: String {
        let t = { (s: String) in s.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;") }
        return """
        <!doctype html><html lang="\(Locale.current.language.languageCode?.identifier ?? "en")"><head><meta charset="utf-8">
        <style>body{font:16px -apple-system,sans-serif;margin:16px;line-height:1.5}table{border-collapse:collapse}td,th{border:1px solid #999;padding:4px 8px}</style></head><body>
        <h1>\(t(String(localized: "Practice web page")))</h1>
        <p>\(t(String(localized: "Use the VoiceOver keys to jump between headings, links, form controls and the table.")))</p>
        <h2>\(t(String(localized: "Links")))</h2>
        <p><a href="#weather">\(t(String(localized: "Today's weather")))</a> · <a href="#news">\(t(String(localized: "Local news")))</a></p>
        <h2>\(t(String(localized: "A short form")))</h2>
        <form onsubmit="return false"><label>\(t(String(localized: "Your name"))) <input type="text"></label>
        <label><input type="checkbox"> \(t(String(localized: "Send me updates")))</label> <button>\(t(String(localized: "Send")))</button></form>
        <h2>\(t(String(localized: "Opening hours")))</h2>
        <table><tr><th>\(t(String(localized: "Day")))</th><th>\(t(String(localized: "Opens")))</th><th>\(t(String(localized: "Closes")))</th></tr>
        <tr><td>\(t(String(localized: "Monday")))</td><td>9:00</td><td>17:00</td></tr>
        <tr><td>\(t(String(localized: "Saturday")))</td><td>10:00</td><td>14:00</td></tr></table>
        <h2 id="weather">\(t(String(localized: "Today's weather")))</h2><p>\(t(String(localized: "Sunny and mild.")))</p>
        <h2 id="news">\(t(String(localized: "Local news")))</h2><p>\(t(String(localized: "The library has a new audiobook collection.")))</p>
        </body></html>
        """
    }
}
