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
    /// Control on its own (with `vo` off), as in Control Tab.
    var control = false

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
        return flags.contains(.maskControl) == control && flags.contains(.maskAlternate) == option
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
            18: "1", 19: "2", 20: "3", 21: "4", 23: "5", 22: "6", 26: "7", 28: "8", 25: "9",
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
        /// A question about what you've learned, answered with a number key.
        case question(prompt: String, options: [String], answer: Int, why: String)
    }
    let kind: Kind

    static func say(_ text: String) -> LessonStep { LessonStep(kind: .explain(text)) }
    static func press(_ task: String, _ keys: String, _ combo: KeyCombo, tip: String = "", real: Bool = false) -> LessonStep {
        LessonStep(kind: .practice(task: task, keys: keys, combo: combo, tip: tip, realKeys: real))
    }
    static func doIt(_ task: String, _ check: Mission, tip: String = "") -> LessonStep {
        LessonStep(kind: .mission(task: task, check: check, tip: tip))
    }
    static func ask(_ prompt: String, _ options: [String], answer: Int, why: String) -> LessonStep {
        LessonStep(kind: .question(prompt: prompt, options: options, answer: answer, why: why))
    }
}

/// What each lesson teaches, its recap, and notes for a trainer: the frame around the
/// steps that makes a lesson stick. Goals are said at the start, the recap at the end
/// (on your own), and trainer notes are shown in the window (with a trainer).
enum LessonGuide {
    struct Entry {
        let goals: String
        let recap: String
        let trainer: String
    }

    static func goals(_ id: String) -> String { entries[id]?.goals ?? "" }
    static func recap(_ id: String) -> String { entries[id]?.recap ?? "" }
    static func trainer(_ id: String) -> String { entries[id]?.trainer ?? "" }

    static let entries: [String: Entry] = [
        "start": Entry(
            goals: String(localized: "turning VoiceOver on and off, what the VO keys are, stopping speech, and exploring keys safely with keyboard help."),
            recap: String(localized: "VO means Control and Option held together. Command F5 turns VoiceOver on and off, Control stops speech, VO K is keyboard help, and VO H is the help menu."),
            trainer: String(localized: "Let the learner find Control and Option by touch first: Control is at the bottom left, with Option beside it; on many laptops Fn or the globe key is further left. Encourage free exploring in keyboard help, where nothing happens. If they press too many keys, have them hold the VO keys first, then press the last key slowly.")),
        "moving": Entry(
            goals: String(localized: "moving the VoiceOver cursor item by item, going into and out of groups, pressing buttons, and jumping to the top of a window."),
            recap: String(localized: "VO Right and Left Arrow move by item. VO Shift Down Arrow goes into a group and VO Shift Up Arrow comes out. VO Space presses, and VO Home goes to the top."),
            trainer: String(localized: "Describe the VoiceOver cursor as a finger pointing at one thing at a time. Groups are the hardest idea: compare them to boxes inside boxes, and have the learner listen for in and out. Let them explore the practice area freely between steps.")),
        "reading": Entry(
            goals: String(localized: "reading everything from the cursor, reading by line, paragraph, word and letter, and repeating or copying what VoiceOver said."),
            recap: String(localized: "VO A reads everything, and Control stops it. VO L, VO P, VO W and VO C read the line, paragraph, word and letter. VO Z repeats, and VO Shift C copies the last phrase."),
            trainer: String(localized: "Use the practice paragraph. Spelling a word with VO W twice builds confidence. Point out that reading keys never change anything, so they're always safe to try.")),
        "apps": Entry(
            goals: String(localized: "the menu bar and menu extras, the Dock, shortcut menus, and switching between apps and windows."),
            recap: String(localized: "VO M is the menu bar, VO M twice the menu extras, VO D the Dock, and VO Shift M the shortcut menu. Command Tab switches apps, and Command Grave Accent switches windows."),
            trainer: String(localized: "In the menu bar, have the learner open a menu, listen to a few commands and close it with Escape, so exploring feels safe. Command Tab means holding Command while tapping Tab: practise that hold-and-tap rhythm.")),
        "finding": Entry(
            goals: String(localized: "jumping around with the rotor, finding anything by name with the item chooser, and finding text."),
            recap: String(localized: "VO U opens the rotor: Left and Right Arrow choose a list, Up and Down Arrow an item, and Return goes there. VO I is the item chooser, and VO F finds text."),
            trainer: String(localized: "The rotor is a big step; it makes more sense on the practice web page in lesson 6. Typing to narrow the rotor or item chooser is the time-saver to stress.")),
        "web": Entry(
            goals: String(localized: "jumping through a web page by heading, link, form control and table, and back again, on a practice page."),
            recap: String(localized: "VO Command H, L, J and T go to the next heading, link, form control and table; add Shift to go back. In a table, VO and the arrow keys move from cell to cell."),
            trainer: String(localized: "Make sure the learner is inside the practice web page, with VO Shift Down Arrow on it, before the jumps; if a jump finds nothing, that's usually why. Compare headings to newspaper headlines.")),
        "quicknav": Entry(
            goals: String(localized: "moving with the arrow keys alone using Quick Nav, and with single letters on web pages."),
            recap: String(localized: "Left and Right Arrow together turn Quick Nav on and off. VO Q turns single-key Quick Nav on and off; then H, L and T jump by heading, link and table. Turn it off before typing."),
            trainer: String(localized: "Quick Nav confuses many learners when they try to type. Practise turning it on and off and listening for VoiceOver's announcement. Suggest single-key Quick Nav for reading the web.")),
        "text": Entry(
            goals: String(localized: "moving the text cursor by letter, word and line, selecting text, and copying, pasting and undoing."),
            recap: String(localized: "Option and the arrows move by word, Command and the arrows go to the ends of a line or the text, and Shift selects as you move. Command C copies, X cuts, V pastes and Z undoes."),
            trainer: String(localized: "Have the learner type a sentence with a mistake on purpose, then find and fix it using Option and the arrows. Listen together to what VoiceOver says while selecting: it says what was selected.")),
        "help": Entry(
            goals: String(localized: "bringing the VoiceOver cursor and keyboard focus together, finding out where you are, locking the VO keys, and opening VoiceOver Utility."),
            recap: String(localized: "VO Shift F4 and VO Command F4 bring the cursor and the focus together. VO F3, F2 and F1 describe the item, window and app. VO Semicolon locks the VO keys, and VO F8 opens VoiceOver Utility."),
            trainer: String(localized: "Show focus and the VoiceOver cursor separating with a real example: type in a field, move VoiceOver away, then come back with VO Shift F4. Remind laptop users to hold Fn for the F keys.")),
        "finder": Entry(
            goals: String(localized: "bringing Finder forward, moving through files, opening and going back, reaching common folders, and moving files to the Trash."),
            recap: String(localized: "Command Down Arrow opens and Command Up Arrow goes back. Command Shift A, Command Shift D and Option Command L open Applications, the Desktop and Downloads; Command Shift G goes to any folder. Command Delete moves to the Trash."),
            trainer: String(localized: "Set the Finder window to list view with Command 2 before starting; it reads more predictably than icons. Have the learner find a file they downloaded recently.")),
        "safari": Entry(
            goals: String(localized: "the address field, tabs, going back, finding text on a page, and Reader."),
            recap: String(localized: "Command L is the address field, Command T and Command W open and close tabs, Command Left Bracket goes back, Command F finds, and Command Shift R shows Reader."),
            trainer: String(localized: "Choose a simple, accessible site for the first visit. Show how VoiceOver starts reading as a page loads, how Control stops it, and how headings get past the menus.")),
        "dialogs": Entry(
            goals: String(localized: "moving between controls with Tab, using checkboxes and buttons, and confirming or cancelling dialogs."),
            recap: String(localized: "Tab and Shift Tab move between controls; turn on Keyboard navigation to reach them all. Space checks a box, Return presses the default button, and Escape or Command Period cancels."),
            trainer: String(localized: "Turn on Keyboard navigation in System Settings, Keyboard, before this lesson. Practise in a real dialog, such as TextEdit's save dialog, and cancel it.")),
        "windows": Entry(
            goals: String(localized: "opening apps with Spotlight; closing, minimizing, hiding and quitting; and force quitting an app that's stuck."),
            recap: String(localized: "Command Space opens Spotlight. Command W closes, Command M minimizes, Command H hides, Command Q quits, Command Comma opens settings, and Option Command Escape force quits."),
            trainer: String(localized: "Make closing versus quitting concrete: close a TextEdit window with Command W, notice TextEdit is still open, then quit it with Command Q.")),
        "mail": Entry(
            goals: String(localized: "moving through your messages, reading one, and writing, replying to and sending email."),
            recap: String(localized: "The arrow keys move through messages. Command N starts a message, Tab moves between its fields, Command Shift D sends, and Command R replies."),
            trainer: String(localized: "Use a practice account, or have the learner email themselves. Reading a message means moving from the list into the message: show this with VO Right Arrow.")),
        "customize": Entry(
            goals: String(localized: "changing VoiceOver's speech as you go, changing how much it says, and where to set up everything else."),
            recap: String(localized: "VO Command Left and Right Arrow choose a speech setting, and VO Command Up and Down Arrow change it. VO V opens the verbosity rotor, and VO F8 opens VoiceOver Utility, with Commanders, Activities and braille."),
            trainer: String(localized: "Help the learner find a speaking rate a little faster than comfortable; it speeds up everything else. Download a better-quality voice together in VoiceOver Utility, under Speech.")),
        "speech": Entry(
            goals: String(localized: "what VoiceOver's descriptions mean, so you can tell what an item is and what state it's in."),
            recap: String(localized: "VoiceOver says the name, then the kind of item, then its state. Dimmed means unavailable, collapsed means closed, selected means chosen, and row 2 of 40 is your place in a list."),
            trainer: String(localized: "Use real examples from apps the learner uses. Before they press VO Space, ask them to predict what will happen from what VoiceOver said.")),
        "textedit": Entry(
            goals: String(localized: "writing a short document, selecting and styling text, and saving it with a name."),
            recap: String(localized: "Type, then check your writing with VO A or the arrow keys. Command A selects everything, Command B makes it bold, and Command S saves."),
            trainer: String(localized: "Pick a short, meaningful text, such as a note to a friend. In the save dialog, check the name was typed before Return is pressed.")),
        "pages": Entry(
            goals: String(localized: "starting a document from a template, writing and styling it, checking spelling, saving it, and exporting it to Word or PDF."),
            recap: String(localized: "Choose Blank in the template chooser. Command Semicolon finds the next misspelling. Command S saves, and File, Export To makes a Word or PDF copy."),
            trainer: String(localized: "Pages has many areas; keep to the document and the Format sidebar. If the template chooser is confusing, VO I finds Blank by name.")),
        "numbers": Entry(
            goals: String(localized: "moving between cells, entering values and formulas, adding rows and columns, and saving a spreadsheet."),
            recap: String(localized: "The arrow keys move between cells; Return and Tab finish a cell. A formula starts with equals. Option and the arrows add rows and columns, and Command S saves."),
            trainer: String(localized: "Start with a tiny table, such as three items and their prices. Ask the learner to say each cell's name to build a picture of the rows and columns.")),
        "keynote": Entry(
            goals: String(localized: "adding slides, writing on them, playing a slideshow and moving through it, and saving a presentation."),
            recap: String(localized: "Command Shift N adds a slide. VO Space on a text box starts editing, and Escape stops. Option Command P plays the show, the arrows move through it, and Escape ends it."),
            trainer: String(localized: "Keep to two or three slides, and practise the slideshow controls, since presenting is usually the goal. Presenter notes are a good next step.")),
        "settings": Entry(
            goals: String(localized: "opening System Settings, finding a setting with the sidebar or search, and reaching the VoiceOver and Accessibility settings."),
            recap: String(localized: "Open System Settings with Spotlight. Move through the sidebar, or type in the search field. Accessibility, then VoiceOver, has VoiceOver's settings."),
            trainer: String(localized: "Searching is the fastest route: practise finding a few settings, such as Bluetooth and Display.")),
        "errand": Entry(
            goals: String(localized: "going to a real website, getting an overview with headings, and reading the part you need."),
            recap: String(localized: "Command L, type the address, and Return. Get an overview with the rotor's headings list, jump with VO Command H, and read with VO A."),
            trainer: String(localized: "Afterwards, do a second errand on a site the learner cares about. Talk about how most sites are laid out: menus at the top, then the main content after the first heading.")),
        "safarideep": Entry(
            goals: String(localized: "working with tabs; adding, finding, organizing and removing bookmarks; the Reading List and history; and private browsing."),
            recap: String(localized: "Control Tab moves between tabs and Command Shift T reopens one. Command D bookmarks a page, Control Command 1 shows bookmarks, and Option Command B edits them. Command Shift D adds to the Reading List, and Command Y shows history."),
            trainer: String(localized: "Bookmark two or three sites the learner uses, then put them in a folder together in Edit Bookmarks. Removing a bookmark and adding it back builds confidence.")),
        "review": Entry(
            goals: String(localized: "a mixed review of keys from every lesson, starting with any you've missed."),
            recap: "",
            trainer: String(localized: "Use the session report to choose which lesson to go back to.")),
    ]
}

/// Names to save practice documents under. Kept the same in every language, so they
/// can be checked.
enum LessonNames {
    static let textEdit = "Practice"
    static let pages = "Practice Letter"
    static let numbers = "Practice Budget"
    static let keynote = "Practice Talk"
}

/// Something done for real, checked about once a second.
enum Mission: Hashable {
    case frontApp(String)
    case finderShowing(FinderPlace)
    case pressedPlay, checkedSubscribe, typedInField
    /// A document saved under a name: the app's front window is titled with it.
    case documentSaved(app: String, name: String)
    /// Safari showing an address containing all of these.
    case safariAt([String])
    /// A page of System Settings open, by its window title.
    case settingsPage(String)
    /// Safari's front window has more (or fewer) tabs than when the task began.
    case safariMoreTabs, safariFewerTabs
    /// Something the app can't see (such as Safari's bookmarks): Return says it's done.
    case yourWord

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
        case .documentSaved(let app, let name):
            return Self.frontWindowTitle(of: app).map { Self.title($0, isSavedAs: name) } ?? false
        case .safariAt(let parts):
            guard NSWorkspace.shared.frontmostApplication?.bundleIdentifier == "com.apple.Safari",
                  let script = SitePresets.browsers["com.apple.Safari"],
                  let address = AppleScriptRunner.run(script, logErrors: false)?.lowercased() else { return false }
            return parts.allSatisfy { address.contains($0.lowercased()) }
        case .settingsPage(let title):
            return Self.frontWindowTitle(of: "com.apple.systempreferences") == title
        case .safariMoreTabs, .safariFewerTabs:
            guard let now = Self.safariTabCount(), let start = runner.missionStart else { return false }
            return self == .safariMoreTabs ? now > start : now < start
        case .yourWord:
            return false
        }
    }

    /// Tabs in Safari's front window, or nil if Safari isn't open or can't be asked.
    static func safariTabCount() -> Int? {
        AppleScriptRunner.run("tell application id \"com.apple.Safari\" to if (count of windows) > 0 then return count of tabs of front window",
                              logErrors: false).flatMap { Int($0) }
    }

    /// "Practice", "Practice.rtf" or "Practice — Edited" all mean saved as Practice.
    static func title(_ title: String, isSavedAs name: String) -> Bool {
        let title = title.lowercased(), name = name.lowercased()
        // After the name, only an extension or the "— Edited" marker (in any language).
        return title == name || title.hasPrefix(name + ".") || title.hasPrefix(name + " \u{2014}") || title.hasPrefix(name + " -")
    }

    /// The title of an app's focused window, if that app is in front.
    private static func frontWindowTitle(of bundleID: String) -> String? {
        guard let app = NSWorkspace.shared.frontmostApplication, app.bundleIdentifier == bundleID,
              let window = AX.element(AX.application(app.processIdentifier), kAXFocusedWindowAttribute) else { return nil }
        return AX.string(window, kAXTitleAttribute)
    }

    /// Checks that ask another app (a window title, Safari's address) run off the main thread.
    var needsAccessibility: Bool {
        switch self {
        case .finderShowing, .documentSaved, .safariAt, .settingsPage, .safariMoreTabs, .safariFewerTabs: true
        default: false
        }
    }
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
        Lesson(id: "speech", title: String(localized: "16. Understanding what VoiceOver says"),
               summary: String(localized: "What VoiceOver's descriptions mean: dimmed, selected, collapsed, rows, hints and more."), steps: [
            .say(String(localized: "VoiceOver describes each item in a pattern: its name, then what kind of thing it is, then its state, and sometimes a hint after a short pause. For example: Play, button. Or: Subscribe, unchecked, checkbox.")),
            .ask(String(localized: "VoiceOver says: Save, dimmed, button. What does dimmed mean?"),
                 [String(localized: "The button is selected"), String(localized: "The button can't be used right now"), String(localized: "The button is hidden")], answer: 1,
                 why: String(localized: "Dimmed means unavailable: the button is there, but can't be used until something else changes, such as filling in a field.")),
            .say(String(localized: "Some items open to show more. Collapsed means closed and expanded means open; VO Space switches between them. Pop-up button means pressing it shows a menu or list to choose from.")),
            .ask(String(localized: "VoiceOver says: Advanced, collapsed, disclosure triangle. What happens when you press VO Space?"),
                 [String(localized: "It opens and shows more options"), String(localized: "It deletes the item"), String(localized: "Nothing, it's only a label")], answer: 0,
                 why: String(localized: "A collapsed disclosure triangle opens with VO Space and shows what's inside; VoiceOver then says expanded.")),
            .say(String(localized: "In lists and tables, VoiceOver says where you are, such as row 3 of 10. Selected means it's the chosen item. When you go into a group it may say in, and out when you leave.")),
            .ask(String(localized: "VoiceOver says: Inbox, row 2 of 40, selected. Where are you?"),
                 [String(localized: "On a button called row 2"), String(localized: "On the second of 40 rows, the one that's chosen"), String(localized: "In the 40th folder")], answer: 1,
                 why: String(localized: "Row 2 of 40 is your place in the list, and selected means it's the chosen row.")),
            .say(String(localized: "After a pause, VoiceOver may add a hint, such as how to press a button. Once you know your way around, you can turn hints off in VoiceOver Utility, under Verbosity.")),
            .ask(String(localized: "VoiceOver says: Name, edit text. What can you do there?"),
                 [String(localized: "Type into it"), String(localized: "Only read it"), String(localized: "Open a menu")], answer: 0,
                 why: String(localized: "Edit text is a text field: you can type into it, and VoiceOver says each letter.")),
        ]),
        Lesson(id: "textedit", title: String(localized: "17. Writing and saving in TextEdit"),
               summary: String(localized: "A real document: writing, selecting, styling and saving it."), steps: [
            .say(String(localized: "Let's write a real document in TextEdit, the Mac's simple word processor. Open it with Spotlight: Command Space, type TextEdit, and press Return. If it shows a list of files, press Command N for a new document.")),
            .doIt(String(localized: "Open TextEdit, for real."), .frontApp("com.apple.TextEdit"),
                  tip: String(localized: "Come back to the lessons with Command Tab when you hear Done.")),
            .say(String(localized: "Type a sentence or two. VoiceOver says each word as you finish it. To check what you wrote, press VO A to hear it all, or move through it with the arrow keys.")),
            .say(String(localized: "To style text, select it first: Command A selects everything. Then Command B makes it bold, Command I italic and Command U underlined. VoiceOver says what's selected.")),
            .press(String(localized: "Select all the text"), String(localized: "Command A"), KeyCombo(code: 0, vo: false, command: true)),
            .press(String(localized: "Make the selected text bold"), String(localized: "Command B"), KeyCombo(code: 11, vo: false, command: true)),
            .say(String(localized: "Command S saves. Type a name, choose where with Tab if you like, and press Return. Command O opens a document, and Command W closes the window; if you haven't saved, TextEdit asks.")),
            .press(String(localized: "Save the document"), String(localized: "Command S"), KeyCombo(code: 1, vo: false, command: true)),
            .doIt(String(localized: "Now for real: save your TextEdit document with the name \(LessonNames.textEdit)."),
                  .documentSaved(app: "com.apple.TextEdit", name: LessonNames.textEdit),
                  tip: String(localized: "In TextEdit, press Command S, type the name, and press Return.")),
        ]),
        Lesson(id: "pages", title: String(localized: "18. Pages: documents"),
               summary: String(localized: "Templates, writing and styling, spell checking, saving and exporting to Word or PDF."), steps: [
            .say(String(localized: "Pages is Apple's word processor, for letters, reports and flyers. It's free from the App Store if you don't have it. When you make a new document, Pages shows a template chooser: move through the templates with the arrow keys, choose Blank, and press Return.")),
            .doIt(String(localized: "Open Pages, for real."), .frontApp("com.apple.iWork.Pages"),
                  tip: String(localized: "Command Space, type Pages, press Return. If you don't have Pages, press Return here to skip.")),
            .say(String(localized: "The document is in the middle of the window, with a toolbar above it and the Format sidebar on the right. Type into the document as in TextEdit. Command B, I and U style selected text, and the Format sidebar's paragraph style pop-up turns a line into a title or heading.")),
            .say(String(localized: "Pages checks spelling as you type. Command Semicolon moves to the next misspelled word, and then VO Shift M offers suggestions. Command Shift Colon opens the full spelling and grammar window.")),
            .press(String(localized: "Go to the next misspelled word"), String(localized: "Command Semicolon"), KeyCombo(code: 41, vo: false, command: true)),
            .press(String(localized: "Make the selected text italic"), String(localized: "Command I"), KeyCombo(code: 34, vo: false, command: true)),
            .say(String(localized: "Save with Command S. To share with someone who uses Word, or as a PDF, use the File menu: File, Export To, then Word or PDF. VO M takes you to the menu bar.")),
            .doIt(String(localized: "Now for real: write a line in Pages and save the document with the name \(LessonNames.pages)."),
                  .documentSaved(app: "com.apple.iWork.Pages", name: LessonNames.pages),
                  tip: String(localized: "In Pages, press Command S, type the name, and press Return.")),
        ]),
        Lesson(id: "numbers", title: String(localized: "19. Numbers: spreadsheets"),
               summary: String(localized: "Moving between cells, entering values and formulas, adding rows and columns, and saving."), steps: [
            .say(String(localized: "Numbers is Apple's spreadsheet app, for budgets, lists and anything in rows and columns. Make a new spreadsheet with the Blank template. A spreadsheet is a table: columns have letters, rows have numbers, and each cell has a name such as B2.")),
            .doIt(String(localized: "Open Numbers, for real."), .frontApp("com.apple.iWork.Numbers"),
                  tip: String(localized: "Command Space, type Numbers, press Return. If you don't have Numbers, press Return here to skip.")),
            .say(String(localized: "Move between cells with the arrow keys; VoiceOver says the cell's name and what's in it. Type to put something in a cell, and press Return to finish and move down, or Tab to move right. Shift Return and Shift Tab go the other way.")),
            .press(String(localized: "Finish a cell and move right"), String(localized: "Tab"), KeyCombo(code: 48, vo: false)),
            .press(String(localized: "Finish a cell and move left"), String(localized: "Shift Tab"), KeyCombo(code: 48, vo: false, shift: true)),
            .say(String(localized: "A formula starts with an equals sign. To add up three cells, go to a cell under them and type equals SUM, open bracket, B2 colon B4, close bracket, then Return. VoiceOver reads the result.")),
            .say(String(localized: "Option Down Arrow adds a row below the selected cell, and Option Up Arrow one above. Option Right Arrow adds a column to the right, and Option Left Arrow one to the left. Shift and an arrow key selects more than one cell.")),
            .press(String(localized: "Add a row below"), String(localized: "Option Down Arrow"), KeyCombo(code: 125, vo: false, option: true)),
            .press(String(localized: "Add a column to the right"), String(localized: "Option Right Arrow"), KeyCombo(code: 124, vo: false, option: true)),
            .doIt(String(localized: "Now for real: put three numbers in a column, add them with a SUM formula, and save the spreadsheet with the name \(LessonNames.numbers)."),
                  .documentSaved(app: "com.apple.iWork.Numbers", name: LessonNames.numbers),
                  tip: String(localized: "Command S saves: type the name and press Return.")),
        ]),
        Lesson(id: "keynote", title: String(localized: "20. Keynote: presentations"),
               summary: String(localized: "Adding slides, writing on them, playing the slideshow, and saving."), steps: [
            .say(String(localized: "Keynote is Apple's presentation app. Choose a theme when you make a new presentation; the first slide has a title and a subtitle. On the left is the slide navigator, a list of slides, and in the middle is the slide itself.")),
            .doIt(String(localized: "Open Keynote, for real."), .frontApp("com.apple.iWork.Keynote"),
                  tip: String(localized: "Command Space, type Keynote, press Return. If you don't have Keynote, press Return here to skip.")),
            .say(String(localized: "To write on a slide, move the VoiceOver cursor into the slide, find the title's text box, press VO Space to start editing, and type. Press Escape when you're done with that box. Command Shift N adds a new slide after the current one.")),
            .press(String(localized: "Add a new slide"), String(localized: "Command Shift N"), KeyCombo(code: 45, vo: false, shift: true, command: true)),
            .say(String(localized: "In the slide navigator, Up and Down Arrow move between slides, and VoiceOver reads each slide's title. Option Command P plays the slideshow from the current slide. During it, Right Arrow or Space goes to the next slide, Left Arrow goes back, and Escape ends the show.")),
            .press(String(localized: "Play the slideshow"), String(localized: "Option Command P"), KeyCombo(code: 35, vo: false, command: true, option: true)),
            .doIt(String(localized: "Now for real: add a title to your first slide, add a second slide, and save the presentation with the name \(LessonNames.keynote)."),
                  .documentSaved(app: "com.apple.iWork.Keynote", name: LessonNames.keynote),
                  tip: String(localized: "Command S saves: type the name and press Return.")),
        ]),
        Lesson(id: "settings", title: String(localized: "21. Finding your way around System Settings"),
               summary: String(localized: "The sidebar, searching for a setting, and the VoiceOver and Accessibility pages."), steps: [
            .say(String(localized: "System Settings has everything from Wi-Fi to accessibility. Open it with Spotlight: Command Space, type System Settings, and press Return.")),
            .doIt(String(localized: "Open System Settings, for real."), .frontApp("com.apple.systempreferences"),
                  tip: String(localized: "Come back to the lessons with Command Tab when you hear Done.")),
            .say(String(localized: "The window has a sidebar on the left, with a search field at the top, and the settings on the right. Move through the sidebar with VO and the arrow keys and choose a category with VO Space, or type in the search field to find a setting by name.")),
            .doIt(String(localized: "Now for real: open the VoiceOver settings page. It's under Accessibility."), .settingsPage("VoiceOver"),
                  tip: String(localized: "In the sidebar, choose Accessibility, then VoiceOver. Or type VoiceOver in the search field.")),
            .say(String(localized: "On that page you can turn VoiceOver on and off and open VoiceOver Utility. Accessibility also has Zoom, Display options such as bigger text and less transparency, Spoken Content, and Keyboard options.")),
        ]),
        Lesson(id: "errand", title: String(localized: "22. A web errand in Safari"),
               summary: String(localized: "Going to a real page, getting an overview with headings, and reading a section."), steps: [
            .say(String(localized: "Time to use the web for real. In Safari, press Command L, type apple.com/accessibility, and press Return.")),
            .doIt(String(localized: "Go to apple.com/accessibility in Safari, for real."), .safariAt(["apple.com", "accessibility"]),
                  tip: String(localized: "The first time, your Mac may ask to let VoiceOver Audio Split see Safari's address; choose OK.")),
            .say(String(localized: "Now explore the page. VO Command H jumps from heading to heading, and the rotor, VO U, lists all the headings and links. Find a heading about vision, and read the text under it with VO A.")),
            .ask(String(localized: "On a long web page, what's usually the quickest way to get an overview?"),
                 [String(localized: "Read everything from the top with VO A"), String(localized: "The headings list in the rotor, with VO U"), String(localized: "Press Tab many times")], answer: 1,
                 why: String(localized: "The headings list shows the page's sections at a glance, and Return takes you to one.")),
            .say(String(localized: "Command D bookmarks a page, and Command Left Bracket goes back. You've done a real errand on the web: well done.")),
        ]),
        Lesson(id: "safarideep", title: String(localized: "23. Safari in depth: tabs, bookmarks, Reading List and history"),
               summary: String(localized: "Working with tabs, adding, organizing and removing bookmarks, the Reading List, history, downloads and private windows."), steps: [
            .say(String(localized: "This lesson goes deeper into Safari. Open Safari now, and leave it open: some tasks happen there. Tabs first. Command T opens a new tab and Command W closes one. Control Tab moves to the next tab, and Control Shift Tab to the previous one. Closed one by mistake? Command Shift T brings it back.")),
            .press(String(localized: "Move to the next tab"), String(localized: "Control Tab"), KeyCombo(code: 48, vo: false, control: true)),
            .press(String(localized: "Move to the previous tab"), String(localized: "Control Shift Tab"), KeyCombo(code: 48, vo: false, shift: true, control: true)),
            .press(String(localized: "Reopen the last closed tab"), String(localized: "Command Shift T"), KeyCombo(code: 17, vo: false, shift: true, command: true)),
            .doIt(String(localized: "Now for real: open a new tab in Safari."), .safariMoreTabs,
                  tip: String(localized: "Switch to Safari with Command Tab, then press Command T.")),
            .doIt(String(localized: "Now close that tab again."), .safariFewerTabs,
                  tip: String(localized: "In Safari, press Command W.")),
            .say(String(localized: "Bookmarks save pages to come back to. On a page, Command D adds a bookmark: a small window asks where to put it, such as Favorites or the Bookmarks Menu, and what to call it. Change them if you like, and press Return to add it.")),
            .press(String(localized: "Bookmark the page"), String(localized: "Command D"), KeyCombo(code: 2, vo: false, command: true)),
            .doIt(String(localized: "Now for real: go to apple.com/accessibility in Safari and bookmark it. Press Return here when you've done it."), .yourWord,
                  tip: String(localized: "Command L, type the address, Return. Then Command D, and Return to add the bookmark.")),
            .say(String(localized: "To use your bookmarks, Control Command 1 shows the bookmarks sidebar: move through it with VO and the arrow keys and open a bookmark with VO Space. To tidy them up, Option Command B opens Edit Bookmarks. There, move to a bookmark and press Return to rename it, or Delete to remove it. Folders work the same way: open one with VO Space or Right Arrow.")),
            .press(String(localized: "Show the bookmarks sidebar"), String(localized: "Control Command 1"), KeyCombo(code: 18, vo: false, command: true, control: true)),
            .press(String(localized: "Edit bookmarks"), String(localized: "Option Command B"), KeyCombo(code: 11, vo: false, command: true, option: true)),
            .doIt(String(localized: "Now for real: remove the bookmark you just made. Press Return here when it's gone."), .yourWord,
                  tip: String(localized: "In Safari, press Option Command B, find the bookmark, and press Delete.")),
            .say(String(localized: "The Reading List keeps articles to read later, even offline. Command Shift D adds the current page, and Control Command 2 shows the Reading List. To remove an item, find it in the list and press Delete.")),
            .press(String(localized: "Add the page to the Reading List"), String(localized: "Command Shift D"), KeyCombo(code: 2, vo: false, shift: true, command: true)),
            .say(String(localized: "Command Y shows your history, with a search field to find a page you visited. Command Left and Right Bracket go back and forward. Option Command L shows downloads. Command Plus and Command Minus make the page bigger or smaller, and Command 0 sets it back.")),
            .press(String(localized: "Show your history"), String(localized: "Command Y"), KeyCombo(code: 16, vo: false, command: true)),
            .press(String(localized: "Show downloads"), String(localized: "Option Command L"), KeyCombo(code: 37, vo: false, command: true, option: true)),
            .say(String(localized: "Command Shift N opens a private window, which doesn't keep history. And if a site won't work well with VoiceOver, Reader (Command Shift R) often helps, as can turning off Quick Nav while filling in forms.")),
            .ask(String(localized: "You want to read an article later, even without internet. What do you use?"),
                 [String(localized: "A private window"), String(localized: "The Reading List, with Command Shift D"), String(localized: "History, with Command Y")], answer: 1,
                 why: String(localized: "The Reading List saves the article to read later, and can keep it for offline reading.")),
        ]),
    ]

    /// The last lesson: a mixed review of everything, without the keys being said,
    /// starting with the keys you've missed before.
    static let review = Lesson(id: "review", title: String(localized: "24. Review: everything so far"),
                               summary: String(localized: "A mixed quiz from all the lessons, starting with what you've missed."), steps: [])
    static var course: [Lesson] { all + [review] }
    /// Keys due again, spaced out like flashcards: known keys come back less often.
    static let daily = Lesson(id: "daily", title: String(localized: "Daily practice"),
                              summary: String(localized: "The keys due for practice today."), steps: [])
    /// As many keys as you can in a minute.
    static let challenge = Lesson(id: "challenge", title: String(localized: "One-minute challenge"),
                                  summary: String(localized: "Answer as many as you can in 60 seconds."), steps: [])

    /// The course in levels, for the lesson list.
    static var levels: [(title: String, lessons: [Lesson])] {
        [(String(localized: "Basics"), Array(all.prefix(9))),
         (String(localized: "Everyday apps"), Array(all.dropFirst(9).prefix(6))),
         (String(localized: "Going further"), Array(all.dropFirst(15))),
         (String(localized: "Review"), [review])]
    }

    /// Every practice step in the course, by ID.
    static var allPractice: [(id: String, step: LessonStep)] { all.flatMap(\.practiceWithIDs) }
}

/// Spaced practice, like flashcards in boxes: a key answered right first time moves up a
/// box and comes back later (1, 3, 7, 14 and then 30 days); a miss goes back to box 1 and
/// is due again straight away.
enum LessonSchedule {
    static let days = [1.0, 3, 7, 14, 30]

    /// IDs due now, most overdue first.
    static func due(now: Date = Date(), in schedule: [String: [Double]] = Preferences.shared.lessonSchedule) -> [String] {
        schedule.filter { $0.value.count == 2 && $0.value[1] <= now.timeIntervalSince1970 }
            .sorted { $0.value[1] < $1.value[1] }.map(\.key)
    }

    /// The schedule after an answer.
    static func update(_ schedule: [String: [Double]], id: String, right: Bool, now: Date = Date()) -> [String: [Double]] {
        var schedule = schedule
        let box = right ? min(Int(schedule[id]?.first ?? 0) + 1, days.count) : 1
        let wait = right ? days[box - 1] * 86_400 : 0
        schedule[id] = [Double(box), now.timeIntervalSince1970 + wait]
        return schedule
    }
}

/// How lessons speak. While the lesson window is in front, it uses an accessibility
/// announcement: VoiceOver queues it with its own speech and shows it on a braille
/// display. A step's text interrupts; feedback after a real VoiceOver command waits its
/// turn, so it doesn't cut off what VoiceOver is saying. Elsewhere it uses the usual voice.
enum LessonVoice {
    static func say(_ text: String, waitForVoiceOver: Bool = false) {
        guard NSApp.isActive, NSWorkspace.shared.isVoiceOverEnabled,
              let window = LessonRunner.shared.window, window.isVisible else { return Announcer.say(text) }
        NSAccessibility.post(element: window, notification: .announcementRequested, userInfo: [
            .announcement: text,
            .priority: (waitForVoiceOver ? NSAccessibilityPriorityLevel.medium : .high).rawValue,
        ])
    }
}

/// Learning with a trainer beside you, or on your own.
enum LessonMode: String, CaseIterable, Identifiable {
    /// More explanation, step numbers, exact feedback on mistakes, hints that build up,
    /// and a recap, so nobody else needs to be there.
    case onYourOwn
    /// Shorter: the trainer explains. Hints only on request, notes for the trainer,
    /// and a report at the end.
    case withTrainer

    var id: String { rawValue }

    var title: String {
        switch self {
        case .onYourOwn: String(localized: "On my own: more explanation, detailed feedback and hints")
        case .withTrainer: String(localized: "With a trainer: shorter prompts, hints when asked, notes and a report for the trainer")
        }
    }

    static var current: LessonMode { LessonMode(rawValue: Preferences.shared.lessonMode) ?? .onYourOwn }
}

/// One line of the session report: how a practice step went.
struct LessonResult: Identifiable, Hashable {
    let id = UUID()
    let task: String
    let keys: String
    var tries: Int
    var skipped = false

    var summary: String {
        if skipped { return String(localized: "\(task) (\(keys)): skipped") }
        return tries <= 1 ? String(localized: "\(task) (\(keys)): right first time")
                          : String(localized: "\(task) (\(keys)): right after \(tries) tries")
    }
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
    /// How each practice step went this time, for the trainer (and the learner).
    @Published private(set) var report: [LessonResult] = []

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
    /// The current step has been answered; further presses are ignored until the next.
    private var answered = false
    private var session = 0
    private var missionTimer: Timer?
    /// When the one-minute challenge ends.
    private var deadline: Date?
    /// Steps missed in this quick check, for one more round before the lesson ends.
    private var missedThisCheck: [(id: String, step: LessonStep)] = []
    private var inSecondRound = false

    private var mode: LessonMode { LessonMode.current }
    private var onYourOwn: Bool { mode == .onYourOwn }
    private var isChallenge: Bool { lesson?.id == Lesson.challenge.id }
    private var isDrill: Bool { [Lesson.daily.id, Lesson.challenge.id, Lesson.review.id].contains(lesson?.id) }

    // MARK: Running

    func start(_ lesson: Lesson, onlyMissed: Bool = false) {
        PracticeModel.shared.stop()
        TypingTrainer.shared.stop()
        stopMission()
        self.lesson = lesson
        session += 1
        index = 0
        checkRight = 0
        deadline = nil
        report = []
        score = ""
        missedThisCheck = []
        inSecondRound = false
        if lesson.id == Lesson.daily.id || lesson.id == Lesson.challenge.id {
            let all = Lesson.allPractice
            let chosen: [(id: String, step: LessonStep)]
            if lesson.id == Lesson.daily.id {
                let due = LessonSchedule.due()
                chosen = Array(due.compactMap { id in all.first { $0.id == id } }.prefix(20))
                guard !chosen.isEmpty else {
                    return say(String(localized: "Nothing is due today. Do a lesson, or come back tomorrow."))
                }
            } else {
                // From the lessons you've done, or everything if none yet.
                let done = Set(Preferences.shared.lessonsDone)
                let learned = all.filter { done.contains(String($0.id.split(separator: ".").first ?? "")) }
                chosen = Array((learned.isEmpty ? all : learned).shuffled().prefix(60))
                deadline = Date().addingTimeInterval(64.5) // 60 seconds after the introduction.
            }
            steps = chosen.map(\.step)
            stepIDs = chosen.map(\.id)
            phase = .checking
        } else if lesson.id == Lesson.review.id {
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
        say(introduction(for: lesson))
        let thisSession = session
        // Long introductions need longer before the first step.
        let wait = min(12, 3 + Double(text.split(separator: " ").count) / 3)
        DispatchQueue.main.asyncAfter(deadline: .now() + wait) { [weak self] in
            guard self?.session == thisSession else { return }
            self?.present()
        }
    }

    /// What the lesson is about, and how to control it: in full on your own, briefly with a trainer.
    private func introduction(for lesson: Lesson) -> String {
        if isChallenge {
            return String(localized: "One-minute challenge. I'll name a task; press its keys as fast as you can. Go after the tone.")
        }
        let goals = LessonGuide.goals(lesson.id)
        guard onYourOwn else { return [lesson.title + ".", goals].filter { !$0.isEmpty }.joined(separator: " ") }
        var parts = [lesson.title + "."]
        if !goals.isEmpty { parts.append(String(localized: "In this lesson: \(goals)")) }
        if !isDrill { parts.append(String(localized: "It has \(steps.count) steps.")) }
        parts.append(String(localized: "Return goes on, R repeats, B goes back, H gives a hint, S skips a step, and Escape stops."))
        return parts.joined(separator: " ")
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

    /// "Step 3 of 9." on your own, so you always know where you are.
    private var whereYouAre: String {
        guard onYourOwn, !isChallenge else { return "" }
        return phase == .checking ? String(localized: "Question \(stepNumber) of \(stepCount).")
                                  : String(localized: "Step \(stepNumber) of \(stepCount).")
    }

    private func present() {
        if let deadline, Date() >= deadline { return finish() }
        if isChallenge && index == 0 { Tones.play(.status) }
        guard let step = current else { return lessonPartDone() }
        stepNumber = index + 1
        wrongTries = 0
        answered = false
        say([whereYouAre, prompt(for: step)].filter { !$0.isEmpty }.joined(separator: " "))
        if case .mission(_, let check, _) = step.kind { watch(check) }
    }

    private func prompt(for step: LessonStep) -> String {
        switch step.kind {
        case .explain(let words):
            return onYourOwn && stepNumber == 1 ? words + " " + String(localized: "Press Return when you're ready to go on.") : words
        case .practice(let task, let keys, _, let tip, _):
            if isChallenge { return task }
            if phase == .checking { return String(localized: "\(task)?") }
            return [String(localized: "Try it: \(task). Press \(keys)."), onYourOwn ? tip : ""].filter { !$0.isEmpty }.joined(separator: " ")
        case .question(let prompt, let options, _, _):
            return Self.spoken(prompt, options)
        case .mission(let task, let check, let tip):
            let skip = check == .yourWord ? "" : String(localized: "Press Return here to skip it.")
            return [task, onYourOwn ? tip : "", skip].filter { !$0.isEmpty }.joined(separator: " ")
        }
    }

    /// "Question? 1: first answer. 2: second answer. Press the number of your answer."
    static func spoken(_ prompt: String, _ options: [String]) -> String {
        let choices = options.enumerated().map { String(localized: "\($0.offset + 1): \($0.element).") }.joined(separator: " ")
        return "\(prompt) \(choices) " + String(localized: "Press the number of your answer.")
    }

    // MARK: Real tasks

    /// For tasks that count something (Safari's tabs): the count when the task began.
    private(set) var missionStart: Int?

    private func watch(_ mission: Mission) {
        stopMission()
        let thisSession = session
        let step = index
        missionStart = nil
        guard mission != .yourWord else { return }
        if mission == .safariMoreTabs || mission == .safariFewerTabs {
            DispatchQueue.global(qos: .userInitiated).async {
                let count = Mission.safariTabCount()
                DispatchQueue.main.async { if self.session == thisSession, self.index == step { self.missionStart = count } }
            }
        }
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
        guard !answered else { return }
        answered = true
        stopMission()
        Tones.play(.device)
        // Probably in another app now: say how to get back.
        say(onYourOwn ? String(localized: "Done! Well done. Come back to the lessons window with Command Tab, then press Return.")
                      : String(localized: "Done!"))
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

    /// Back one step (B), for hearing an explanation again or trying a key once more.
    private func goBack() {
        stopMission()
        session += 1 // Cancels anything scheduled for the step we're leaving.
        index = max(0, index - 1)
        present()
    }

    /// Skip a step (S): it counts as missed, so it comes back in practice.
    private func skip() {
        guard current != nil else { return }
        stopMission()
        if case .practice(let task, let keys, _, _, _) = current?.kind {
            remember(currentID, missed: true)
            note(task: task, keys: keys, skipped: true)
            if phase == .checking, let step = current { missedThisCheck.append((currentID, step)) }
        }
        answered = true
        session += 1
        say(onYourOwn ? String(localized: "Skipped. It will come back in Practice What I Missed.") : String(localized: "Skipped."))
        let thisSession = session
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            guard let self, self.session == thisSession else { return }
            self.index += 1
            self.present()
        }
    }

    /// The lesson's steps are done: on to its quick check, then one more round on
    /// anything missed, then the end.
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
            missedThisCheck = []
            say(onYourOwn
                ? String(localized: "Now a quick check, to make it stick. I'll name each task without the keys; press them. If you're not sure, press H for a hint, or R to hear the task again.")
                : String(localized: "Quick check."))
            return startAfterSpeaking()
        }
        // Mastery: what was missed gets one more go, so the lesson ends on success.
        if phase == .checking && !inSecondRound && !missedThisCheck.isEmpty && !isChallenge {
            inSecondRound = true
            let again = missedThisCheck
            missedThisCheck = []
            steps = again.map(\.step)
            stepIDs = again.map(\.id)
            stepCount = steps.count
            index = 0
            say(onYourOwn
                ? String(localized: "Let's go over the tricky ones once more. Take your time.")
                : String(localized: "Once more, the ones that were missed."))
            return startAfterSpeaking()
        }
        finish()
    }

    private func startAfterSpeaking() {
        let thisSession = session
        DispatchQueue.main.asyncAfter(deadline: .now() + (onYourOwn ? 6 : 2.5)) { [weak self] in
            guard let self, self.session == thisSession else { return }
            self.present()
        }
    }

    private func finish() {
        guard let lesson else { return }
        Hotkeys.keyObserver = nil
        stopMission()
        session += 1
        phase = .done
        let checked = report.filter { !$0.skipped }.count
        if isChallenge {
            let best = Preferences.shared.lessonChallengeBest
            score = String(localized: "\(checkRight) right in a minute")
            var message = String(localized: "Time's up! \(score).")
            if checkRight > best {
                Preferences.shared.lessonChallengeBest = checkRight
                message += " " + String(localized: "That's your best yet.")
            } else {
                message += " " + String(localized: "Your best is \(best).")
            }
            Tones.play(.device)
            return say(message)
        }
        score = String(localized: "\(checkRight) of \(max(checked, checkRight)) right first time")
        if lesson.id == Lesson.daily.id {
            Tones.play(.device)
            let left = LessonSchedule.due().count
            return say(String(localized: "Daily practice done. \(score).") + (left > 0 ? " " + String(localized: "\(left) still due; they'll come back in today's next practice.") : ""))
        }
        if !isDrill {
            var done = Preferences.shared.lessonsDone
            if !done.contains(lesson.id) { done.append(lesson.id) }
            Preferences.shared.lessonsDone = done
        }
        let course = Lesson.course
        let next = course.firstIndex(of: lesson).flatMap { $0 + 1 < course.count ? course[$0 + 1] : nil }
        var parts = [String(localized: "Lesson finished. \(score).")]
        if onYourOwn {
            let recap = LessonGuide.recap(lesson.id)
            if !recap.isEmpty { parts.append(String(localized: "To sum up: \(recap)")) }
            let share = checked == 0 ? 1 : Double(checkRight) / Double(checked)
            if share < 0.7 && checked > 0 {
                parts.append(String(localized: "Some of these are still new to you, which is normal. Do this lesson again tomorrow, or use Practice What I Missed."))
            } else if checked > 0 {
                parts.append(String(localized: "You've got the hang of it."))
            }
        } else {
            parts.append(String(localized: "The session report is in the window."))
        }
        if let next { parts.append(String(localized: "Next: \(next.title).")) }
        else if !isDrill { parts.append(String(localized: "That's the whole course. Well done!")) }
        Tones.play(.device)
        say(parts.joined(separator: " "))
    }

    // MARK: Keys

    /// Return, R, B, H, S and Escape steer the lesson; while practicing, the answer is
    /// checked. Everything else goes through, so VoiceOver works normally in explanations.
    private func handle(_ keyCode: Int64, _ flags: CGEventFlags, letter: Character?) -> Bool {
        guard NSApp.isActive, window == nil || NSApp.keyWindow === window else { return false }
        let plain = flags.intersection([.maskCommand, .maskControl, .maskAlternate, .maskShift]).isEmpty && !flags.contains(.maskAlphaShift)
        if keyCode == Key.escape && plain {
            DispatchQueue.main.async { self.stop() }
            return true
        }
        // Typing in the practice text field: letters go to the field; Return still steers the lesson.
        if plain && keyCode != 36 && NSApp.keyWindow?.firstResponder is NSTextView { return false }
        // On the practice web page, letters are single-key Quick Nav (H for headings), not lesson keys.
        let inWebPage = (NSApp.keyWindow?.firstResponder as? NSView).map { view in
            sequence(first: view, next: { $0.superview }).contains { $0 is WKWebView }
        } ?? false
        if plain, let letter, !isChallenge, !inWebPage, ["r", "b", "h", "s"].contains(letter) {
            DispatchQueue.main.async {
                switch letter {
                case "r": self.repeatCurrent()
                case "b": self.goBack()
                case "h": self.hint()
                default: self.skip()
                }
            }
            return true
        }
        guard let step = current else { return false }
        switch step.kind {
        case .explain:
            guard plain && keyCode == 36 else { return false } // Return
            DispatchQueue.main.async { self.index += 1; self.present() }
            return true
        case .question(_, let options, let answer, let why):
            // Number keys 1 to 4, wherever they are on the keyboard.
            let numbers: [Int64: Int] = [18: 0, 19: 1, 20: 2, 21: 3, 83: 0, 84: 1, 85: 2, 86: 3]
            guard let choice = numbers[keyCode], choice < options.count else { return plain && keyCode == 36 }
            DispatchQueue.main.async {
                guard !self.answered else { return }
                if choice == answer {
                    self.answered = true
                    Tones.play(.louder)
                    self.say(Self.praise() + " " + why)
                    self.advance(after: self.onYourOwn ? 5 : 3)
                } else {
                    self.wrongTries += 1
                    Tones.play(.quieter)
                    let picked = options[choice]
                    self.say(self.onYourOwn
                             ? String(localized: "Not quite: \(picked) isn't it. Think about it once more, and try another number.") + " " + Self.spoken("", options)
                             : String(localized: "Not quite. Try another answer."))
                }
            }
            return true
        case .mission:
            guard plain && keyCode == 36 else { return false } // Return skips the task, or says it's done.
            DispatchQueue.main.async {
                guard !self.answered else { return }
                self.answered = true
                self.stopMission()
                if case .mission(_, .yourWord, _) = step.kind {
                    Tones.play(.device)
                    self.say(Self.praise())
                    self.advance(after: 2)
                } else {
                    self.say(String(localized: "Skipped."))
                    self.advance(after: 1)
                }
            }
            return true
        case .practice(let task, let keys, let combo, _, let real):
            if plain && keyCode == 36 {
                DispatchQueue.main.async { self.repeatCurrent() }
                return true
            }
            // Only judge real attempts: something held with the key, or the keys asked for.
            let attempt = KeyCombo.isVO(flags) || flags.contains(.maskCommand) || flags.contains(.maskAlternate)
                || flags.contains(.maskShift) || flags.contains(.maskControl)
                || combo.matches(keyCode: keyCode, flags: flags, letter: letter) || keyCode == 48
            guard attempt else { return false }
            if combo.matches(keyCode: keyCode, flags: flags, letter: letter) {
                DispatchQueue.main.async { self.right(task: task, keys: keys, real: real && self.phase == .explaining) }
                // Let VoiceOver really do it, where that's safe.
                return !(real && phase == .explaining)
            }
            let pressed = KeyCombo.describe(keyCode: keyCode, flags: flags, letter: letter)
            let why = Self.diagnose(expected: combo, keyCode: keyCode, flags: flags, letter: letter)
            DispatchQueue.main.async { self.wrong(pressed: pressed, why: why, task: task, keys: keys, combo: combo) }
            return true
        }
    }

    private func right(task: String, keys: String, real: Bool) {
        // A quick second press of the right keys mustn't skip the next step.
        guard current != nil, !answered else { return }
        answered = true
        if wrongTries == 0 && phase == .checking {
            checkRight += 1
            remember(currentID, missed: false)
        }
        if phase == .checking || isDrill { note(task: task, keys: keys, skipped: false) }
        Tones.play(.louder)
        if isChallenge { return advance(after: 0.3) }
        if real {
            // VoiceOver is saying the result; praise waits its turn after it.
            say(Self.praise(), waitForVoiceOver: true)
            advance(after: 3.5)
        } else if onYourOwn {
            say(Self.praise() + " " + String(localized: "\(keys): \(task)."))
            advance(after: 2.5)
        } else {
            say(Self.praise())
            advance(after: 1.2)
        }
    }

    private func wrong(pressed: String, why: String, task: String, keys: String, combo: KeyCombo) {
        guard !answered else { return }
        wrongTries += 1
        remember(currentID, missed: true)
        if phase == .checking, wrongTries == 1, let step = current { missedThisCheck.append((currentID, step)) }
        Tones.play(.quieter)
        if isChallenge {
            // No second tries against the clock: hear the keys and keep going.
            answered = true
            say(keys)
            return advance(after: 1.5)
        }
        guard onYourOwn else {
            // With a trainer: just what happened. The trainer explains, or H gives a hint.
            return say(String(localized: "Not yet: that was \(pressed)."))
        }
        // On your own: what was pressed, exactly what was wrong, then more help each time.
        var parts = [String(localized: "Not yet. You pressed \(pressed)."), why]
        switch wrongTries {
        case 1: parts.append(String(localized: "\(task): press \(keys)."))
        case 2: parts.append(Self.howToPress(combo))
        default:
            parts.append(Self.howToPress(combo))
            parts.append(String(localized: "Take your time. If it's not working, press S to skip it for now; it will come back later."))
        }
        say(parts.filter { !$0.isEmpty }.joined(separator: " "))
    }

    /// The hint for the current step (H), at any time.
    private func hint() {
        guard let step = current else { return }
        switch step.kind {
        case .practice(let task, let keys, let combo, let tip, _):
            say([String(localized: "\(task): press \(keys)."), Self.howToPress(combo), tip].filter { !$0.isEmpty }.joined(separator: " "))
        case .mission(_, _, let tip):
            say(tip.isEmpty ? String(localized: "Do the task, then come back here. Press Return to skip it.") : tip)
        case .question(_, let options, _, _):
            say(String(localized: "Think about what each answer would mean, then pick the one that fits.") + " " + Self.spoken("", options))
        case .explain:
            say(String(localized: "Press Return to go on, or R to hear this again."))
        }
    }

    /// What's wrong with a key press, in words: missing or extra keys held, or the wrong key.
    static func diagnose(expected: KeyCombo, keyCode: Int64, flags: CGEventFlags, letter: Character?) -> String {
        var problems: [String] = []
        let heldVO = KeyCombo.isVO(flags)
        if expected.vo && !heldVO {
            problems.append(String(localized: "You weren't holding the VO keys, Control and Option."))
        } else if !expected.vo && heldVO {
            problems.append(String(localized: "This one doesn't use the VO keys."))
        }
        if !expected.vo && !heldVO {
            if expected.control && !flags.contains(.maskControl) { problems.append(String(localized: "Control is needed too.")) }
            if !expected.control && flags.contains(.maskControl) { problems.append(String(localized: "Control isn't needed.")) }
            if expected.option && !flags.contains(.maskAlternate) { problems.append(String(localized: "Option is needed too.")) }
            if !expected.option && flags.contains(.maskAlternate) { problems.append(String(localized: "Option isn't needed.")) }
        }
        if expected.command && !flags.contains(.maskCommand) { problems.append(String(localized: "Command is needed too.")) }
        if !expected.command && flags.contains(.maskCommand) { problems.append(String(localized: "Command isn't needed.")) }
        if expected.shift && !flags.contains(.maskShift) { problems.append(String(localized: "Shift is needed too.")) }
        if !expected.shift && flags.contains(.maskShift) { problems.append(String(localized: "Shift isn't needed.")) }
        let rightKey = if let want = expected.letter, let letter { letter == want } else { keyCode == expected.code }
        if !rightKey {
            let wanted = KeyCombo.name(of: expected.code)
            let got = letter.map { String($0).uppercased() } ?? KeyCombo.name(of: keyCode)
            problems.append(String(localized: "The key is \(wanted), not \(got)."))
        }
        return problems.joined(separator: " ")
    }

    /// A little variety in praise.
    static func praise() -> String {
        [String(localized: "Right!"), String(localized: "Well done."), String(localized: "That's it."), String(localized: "Correct."),
         String(localized: "Nice work.")].randomElement()!
    }

    /// "Hold Control, Option and Command, then press H."
    static func howToPress(_ combo: KeyCombo) -> String {
        var held: [String] = []
        if combo.vo { held += [String(localized: "Control"), String(localized: "Option")] }
        if combo.control && !combo.vo { held.append(String(localized: "Control")) }
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

    /// Adds or updates this step's line in the session report.
    private func note(task: String, keys: String, skipped: Bool) {
        let tries = wrongTries + (skipped ? 0 : 1)
        if inSecondRound, let line = report.firstIndex(where: { $0.task == task }) {
            report[line].tries += tries
            report[line].skipped = skipped
        } else {
            report.append(LessonResult(task: task, keys: keys, tries: tries, skipped: skipped))
        }
    }

    private func remember(_ id: String, missed: Bool) {
        guard !id.isEmpty else { return }
        // Keys checked in quick checks, reviews and daily practice go on the practice schedule.
        if phase == .checking {
            Preferences.shared.lessonSchedule = LessonSchedule.update(Preferences.shared.lessonSchedule, id: id, right: !missed)
        }
        var list = Preferences.shared.lessonsMissed
        if missed { if !list.contains(id) { list.append(id) } } else { list.removeAll { $0 == id } }
        if list != Preferences.shared.lessonsMissed { Preferences.shared.lessonsMissed = list }
    }

    func repeatCurrent() {
        guard let step = current else { return say(text) }
        if case .practice(let task, let keys, _, let tip, _) = step.kind, phase == .checking {
            // In a check, R repeats the task; the keys come with H.
            _ = keys; _ = tip
            return say(String(localized: "\(task)?") + (onYourOwn ? " " + String(localized: "Press H if you'd like a hint.") : ""))
        }
        say(prompt(for: step))
    }

    /// The report, as text to copy for a trainer's notes.
    var reportText: String {
        ([lesson?.title ?? "", score] + report.map(\.summary)).filter { !$0.isEmpty }.joined(separator: "\n")
    }

    private func say(_ words: String, waitForVoiceOver: Bool = false) {
        text = words
        LessonVoice.say(words, waitForVoiceOver: waitForVoiceOver)
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
                    Text(String(localized: "A course for learning VoiceOver from the beginning, in four levels. Each lesson explains a skill, then you try the keys, answer questions and do tasks for real. Start with lesson 1, or pick any lesson."))
                        .font(.caption).foregroundStyle(.secondary)
                    Text(String(localized: "\(preferences.lessonsDone.filter { id in Lesson.course.contains { $0.id == id } }.count) of \(Lesson.course.count) lessons done"))
                    Picker(String(localized: "How are you learning?"), selection: $preferences.lessonMode) {
                        ForEach(LessonMode.allCases) { Text($0.title).tag($0.rawValue) }
                    }
                    if !runner.score.isEmpty { Text(runner.text) }
                }
                if !runner.report.isEmpty {
                    Section(String(localized: "Session report: \(runner.lesson?.title ?? "")")) {
                        Text(runner.score)
                        ForEach(runner.report) { Text($0.summary) }
                        Button(String(localized: "Copy Report")) {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(runner.reportText, forType: .string)
                            Announcer.say(String(localized: "Report copied"))
                        }
                    }
                }
                ForEach(Lesson.levels, id: \.title) { level in
                    Section(level.title) {
                        ForEach(level.lessons) { lesson in
                            let done = preferences.lessonsDone.contains(lesson.id)
                            Button(done ? String(localized: "\(lesson.title), done") : lesson.title) { runner.start(lesson) }
                                .accessibilityHint(lesson.summary)
                        }
                    }
                }
                Section(String(localized: "Keep practicing")) {
                    let due = LessonSchedule.due(in: preferences.lessonSchedule).count
                    Button(String(localized: "Daily Practice (\(due) due)")) { runner.start(Lesson.daily) }
                        .accessibilityHint(String(localized: "Keys come back for practice on a schedule: soon after a miss, and less often once you know them."))
                    Button(preferences.lessonChallengeBest > 0
                           ? String(localized: "One-Minute Challenge (best \(preferences.lessonChallengeBest))")
                           : String(localized: "One-Minute Challenge")) { runner.start(Lesson.challenge) }
                    if !preferences.lessonsMissed.isEmpty {
                        Button(String(localized: "Practice What I Missed (\(preferences.lessonsMissed.count))")) {
                            runner.start(Lesson.review, onlyMissed: true)
                        }
                    }
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
                    Text(String(localized: "Return goes on, R repeats, B goes back, H gives a hint, S skips, Escape stops."))
                        .font(.caption).foregroundStyle(.secondary)
                }
                if LessonMode.current == .withTrainer, let lesson = runner.lesson, !LessonGuide.trainer(lesson.id).isEmpty {
                    Section(String(localized: "Notes for the trainer")) {
                        Text(String(localized: "Goals: \(LessonGuide.goals(lesson.id))"))
                        Text(LessonGuide.trainer(lesson.id))
                        if !runner.report.isEmpty {
                            Text(String(localized: "So far: \(runner.report.filter { $0.tries <= 1 && !$0.skipped }.count) of \(runner.report.count) right first time"))
                        }
                    }
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
