// ObjectFinder.swift — "find my cup / phone / door / a person / the word exit":
// point the camera around and a tone rises in pitch and speed as the thing comes
// into view, with spoken "left", "ahead" or "right" where the camera can tell
// where it is. People and pets are located with Apple's detectors, words with
// text recognition, and everyday objects with Apple's image classifier, which
// only says whether something is in the picture, not where. Everything runs on
// the Mac with the Vision framework; no picture is saved or sent anywhere.

import AppKit
import AVFoundation
import SwiftUI
import VideoToolbox
import Vision

enum ObjectFinder {
    enum Direction: Equatable {
        case left, ahead, right

        var spoken: String {
            switch self {
            case .left: String(localized: "left")
            case .ahead: String(localized: "ahead")
            case .right: String(localized: "right")
            }
        }
    }

    /// How a target is looked for.
    enum Method: Hashable {
        /// Vision's human detector: gives a box.
        case person
        /// Vision's cat and dog recognizer: gives a box.
        case animal
        /// Vision's image classifier: is it in the picture, no box.
        case classify
        /// Text recognition, for "find the word exit": gives a box.
        case text
    }

    struct Target: Identifiable, Hashable {
        /// English key, also used for matching.
        let id: String
        /// Shown in the list, such as "Cup".
        let name: String
        /// Spoken in a sentence, such as "a cup".
        let thing: String
        let method: Method
        /// Vision labels that count as this target (classifier identifiers, or "dog" and "cat").
        let labels: [String]
        /// English words people use for it, besides its key.
        let words: [String]

        /// A target for the words on a sign or page, such as "exit".
        static func text(_ words: String) -> Target {
            Target(id: "text:" + words, name: String(localized: "The words \"\(words)\""),
                   thing: String(localized: "the words \"\(words)\""), method: .text, labels: [], words: [words])
        }
    }

    // MARK: Targets

    /// Everything the finder can look for. Classifier targets whose labels this Mac's
    /// Vision doesn't know are left out by `targets`. Apple's classifier has no label
    /// for keys or remote controls, so those can only be found by text.
    static let catalog: [Target] = [
        Target(id: "person", name: String(localized: "Person"), thing: String(localized: "a person"), method: .person,
               labels: ["people", "adult", "child", "baby"], words: ["people", "someone", "somebody", "human", "man", "woman", "anyone"]),
        Target(id: "dog", name: String(localized: "Dog"), thing: String(localized: "a dog"), method: .animal,
               labels: ["dog"], words: ["puppy", "doggy"]),
        Target(id: "cat", name: String(localized: "Cat"), thing: String(localized: "a cat"), method: .animal,
               labels: ["cat"], words: ["kitten", "kitty"]),
        Target(id: "phone", name: String(localized: "Phone"), thing: String(localized: "a phone"), method: .classify,
               labels: ["phone"], words: ["cell phone", "cellphone", "mobile", "mobile phone", "iphone", "smartphone"]),
        Target(id: "cup", name: String(localized: "Cup or mug"), thing: String(localized: "a cup"), method: .classify,
               labels: ["cup", "mug", "drinking_glass"], words: ["mug", "glass", "coffee cup", "tea cup", "teacup"]),
        Target(id: "bottle", name: String(localized: "Bottle"), thing: String(localized: "a bottle"), method: .classify,
               labels: ["bottle", "wine_bottle"], words: ["water bottle"]),
        Target(id: "glasses", name: String(localized: "Glasses"), thing: String(localized: "glasses"), method: .classify,
               labels: ["eyeglasses", "sunglasses"], words: ["eyeglasses", "sunglasses", "spectacles", "specs"]),
        Target(id: "wallet", name: String(localized: "Wallet or purse"), thing: String(localized: "a wallet"), method: .classify,
               labels: ["wallet", "purse"], words: ["purse"]),
        Target(id: "bag", name: String(localized: "Bag or backpack"), thing: String(localized: "a bag"), method: .classify,
               labels: ["bag", "backpack", "purse", "paper_bag"], words: ["backpack", "handbag", "rucksack"]),
        Target(id: "laptop", name: String(localized: "Laptop"), thing: String(localized: "a laptop"), method: .classify,
               labels: ["laptop"], words: ["notebook computer", "macbook"]),
        Target(id: "keyboard", name: String(localized: "Keyboard"), thing: String(localized: "a keyboard"), method: .classify,
               labels: ["computer_keyboard"], words: ["computer keyboard"]),
        Target(id: "mouse", name: String(localized: "Computer mouse"), thing: String(localized: "a mouse"), method: .classify,
               labels: ["computer_mouse"], words: ["computer mouse"]),
        Target(id: "headphones", name: String(localized: "Headphones"), thing: String(localized: "headphones"), method: .classify,
               labels: ["headphones"], words: ["earphones", "headset", "earbuds"]),
        Target(id: "watch", name: String(localized: "Watch"), thing: String(localized: "a watch"), method: .classify,
               labels: ["watch"], words: ["wristwatch"]),
        Target(id: "book", name: String(localized: "Book"), thing: String(localized: "a book"), method: .classify,
               labels: ["book"], words: []),
        Target(id: "medicine", name: String(localized: "Medicine"), thing: String(localized: "medicine"), method: .classify,
               labels: ["medicine"], words: ["pills", "pill bottle", "tablets"]),
        Target(id: "shoes", name: String(localized: "Shoes"), thing: String(localized: "shoes"), method: .classify,
               labels: ["shoes"], words: ["shoe", "sneakers", "trainers", "boots"]),
        Target(id: "plate", name: String(localized: "Plate"), thing: String(localized: "a plate"), method: .classify,
               labels: ["plate"], words: ["dish"]),
        Target(id: "bowl", name: String(localized: "Bowl"), thing: String(localized: "a bowl"), method: .classify,
               labels: ["bowl"], words: []),
        Target(id: "door", name: String(localized: "Door"), thing: String(localized: "a door"), method: .classify,
               labels: ["door"], words: ["doorway"]),
        Target(id: "window", name: String(localized: "Window"), thing: String(localized: "a window"), method: .classify,
               labels: ["window"], words: []),
        Target(id: "stairs", name: String(localized: "Stairs"), thing: String(localized: "stairs"), method: .classify,
               labels: ["stairs"], words: ["steps", "staircase", "stairway"]),
        Target(id: "chair", name: String(localized: "Chair"), thing: String(localized: "a chair"), method: .classify,
               labels: ["chair", "armchair", "swivel_chair", "folding_chair", "chair_other"], words: ["seat", "armchair"]),
        Target(id: "sofa", name: String(localized: "Sofa"), thing: String(localized: "a sofa"), method: .classify,
               labels: ["sofa"], words: ["couch", "settee"]),
        Target(id: "table", name: String(localized: "Table"), thing: String(localized: "a table"), method: .classify,
               labels: ["table"], words: ["desk"]),
        Target(id: "bed", name: String(localized: "Bed"), thing: String(localized: "a bed"), method: .classify,
               labels: ["bed"], words: []),
        Target(id: "toilet", name: String(localized: "Toilet"), thing: String(localized: "a toilet"), method: .classify,
               labels: ["toilet_seat"], words: ["loo", "restroom", "lavatory"]),
        Target(id: "sink", name: String(localized: "Sink"), thing: String(localized: "a sink"), method: .classify,
               labels: ["kitchen_sink"], words: ["basin"]),
        Target(id: "refrigerator", name: String(localized: "Fridge"), thing: String(localized: "a fridge"), method: .classify,
               labels: ["refrigerator"], words: ["fridge"]),
        Target(id: "television", name: String(localized: "TV"), thing: String(localized: "a TV"), method: .classify,
               labels: ["television"], words: ["tv", "telly"]),
        Target(id: "trash can", name: String(localized: "Trash can"), thing: String(localized: "a trash can"), method: .classify,
               labels: ["trash_can"], words: ["trash", "bin", "garbage", "garbage can", "rubbish bin", "wastebasket"]),
        Target(id: "umbrella", name: String(localized: "Umbrella"), thing: String(localized: "an umbrella"), method: .classify,
               labels: ["umbrella"], words: []),
        Target(id: "car", name: String(localized: "Car"), thing: String(localized: "a car"), method: .classify,
               labels: ["car"], words: []),
        Target(id: "bench", name: String(localized: "Bench"), thing: String(localized: "a bench"), method: .classify,
               labels: ["bench"], words: []),
    ]

    /// The labels this Mac's image classifier knows, read once.
    private static let classifierLabels: Set<String> = Set((try? VNClassifyImageRequest().supportedIdentifiers()) ?? [])

    /// What can be looked for on this Mac, in list order.
    static var targets: [Target] {
        catalog.filter { $0.method != .classify || $0.labels.contains(where: classifierLabels.contains) }
    }

    /// Lowercase letters, numbers and single spaces; underscores count as spaces.
    static func normalized(_ text: String) -> String {
        text.lowercased().replacingOccurrences(of: "_", with: " ")
            .map { $0.isLetter || $0.isNumber ? $0 : " " }
            .reduce(into: "") { $0.append($1) }
            .split(separator: " ").joined(separator: " ")
    }

    /// What a request such as "find my keys", "the phone" or "the word exit" means:
    /// a known thing, or else the words to look for. Nil when nothing is left to find.
    static func target(for request: String, in list: [Target] = catalog) -> Target? {
        var words = normalized(request).split(separator: " ").map(String.init)
        let fillers: Set<String> = ["find", "look", "for", "where", "is", "are", "my", "the", "a", "an", "some", "me", "please"]
        while let first = words.first, fillers.contains(first) { words.removeFirst() }
        if let first = words.first, ["word", "words", "text", "sign"].contains(first) {
            words.removeFirst()
            return words.isEmpty ? nil : .text(words.joined(separator: " "))
        }
        let query = words.joined(separator: " ")
        guard !query.isEmpty else { return nil }
        if let known = list.first(where: { names(of: $0).contains(query) }) { return known }
        // "keys" for "key", "dishes" for "dish".
        for ending in ["es", "s"] where query.hasSuffix(ending) {
            let single = String(query.dropLast(ending.count))
            if let known = list.first(where: { names(of: $0).contains(single) }) { return known }
        }
        return .text(query)
    }

    /// Everything a target answers to: its key, its English words and its shown name.
    private static func names(of target: Target) -> Set<String> {
        Set(([target.id, target.name] + target.words).map(normalized))
    }

    /// Whether a label from Vision ("drinking_glass", "Dog") counts as what was asked for ("cup", "my dog").
    static func matches(label: String, target: String) -> Bool {
        guard let wanted = self.target(for: target) else { return false }
        return matches(label: label, target: wanted)
    }

    static func matches(label: String, target: Target) -> Bool {
        let label = normalized(label)
        if target.method == .text { return label.contains(normalized(target.words.first ?? "")) }
        return target.labels.map(normalized).contains(label)
    }

    // MARK: Guidance logic

    /// Where something is, from its box (normalised, origin bottom left). The camera
    /// picture isn't mirrored, so when the camera faces you, something at the picture's
    /// left is on your right.
    static func direction(for box: CGRect, facingYou: Bool = false) -> Direction {
        let middle = box.midX
        let side: Direction = middle < 0.38 ? .left : middle > 0.62 ? .right : .ahead
        guard facingYou else { return side }
        return side == .left ? .right : side == .right ? .left : .ahead
    }

    /// Something filling a third of the picture is close.
    static func isClose(_ box: CGRect) -> Bool {
        box.width * box.height > 0.33
    }

    /// How sure a method must be before it's said out loud. The classifier's scores are
    /// shared among many labels, so they run lower than the detectors'.
    static func threshold(for method: Method) -> Double {
        switch method {
        case .person, .animal: 0.6
        case .classify: 0.3
        case .text: 0.5
        }
    }

    /// Smooths confidence over frames, so one odd frame doesn't make the tone jump.
    static func smoothed(_ previous: Double, _ new: Double) -> Double {
        previous * 0.6 + min(max(new, 0), 1) * 0.4
    }

    /// The tone's pitch: 330 Hz when unsure, up to 1320 Hz when sure.
    static func pitch(forConfidence confidence: Double) -> Double {
        330 * pow(4, min(max(confidence, 0), 1))
    }

    /// Beeps per second: one when unsure, up to eight when sure.
    static func beepRate(forConfidence confidence: Double) -> Double {
        1 + 7 * min(max(confidence, 0), 1)
    }

    /// Decides when to speak, so speech doesn't pile up: a new phrase after 2 seconds,
    /// the same phrase again only after 6.
    struct SpeechThrottle {
        private(set) var lastPhrase: String?
        private(set) var lastTime = Date.distantPast

        mutating func shouldSay(_ phrase: String, at now: Date = Date()) -> Bool {
            let gap = phrase == lastPhrase ? 6.0 : 2.0
            guard now.timeIntervalSince(lastTime) >= gap else { return false }
            lastPhrase = phrase
            lastTime = now
            return true
        }
    }

    /// What to say for a sighting: where it is when there's a box, otherwise just that it's there.
    static func phrase(for target: Target, box: CGRect?, first: Bool, facingYou: Bool) -> String {
        guard let box else { return String(localized: "I think I see \(target.thing)") }
        var place = direction(for: box, facingYou: facingYou).spoken
        if isClose(box) { place = String(localized: "\(place), close", comment: "A direction, such as: ahead, close") }
        return first ? String(localized: "Found \(target.thing), \(place)") : place
    }

    // MARK: Running

    /// One frame's best match: how sure (0 to 1) and where, if the method can tell.
    struct Sighting {
        let confidence: Double
        let box: CGRect?
    }

    /// Settings key: whether the camera faces you (Mac and Continuity cameras usually do),
    /// which swaps left and right.
    static let facesYouKey = "objectFinderCameraFacesYou"
    static var cameraFacesYou: Bool {
        UserDefaults.standard.object(forKey: facesYouKey) as? Bool ?? true
    }

    private static let feed = CameraFeed()
    private static var stopWork: DispatchWorkItem?
    /// Counts runs, so a result from one that has stopped is ignored.
    private static var run = 0
    private static var current: Target?
    private static var seen = false
    private static var throttle = SpeechThrottle()

    static var isRunning: Bool { feed.isRunning }

    /// Stops if running, otherwise starts looking for `target`.
    static func toggle(target: String) {
        isRunning ? stop(announce: true) : start(target: target)
    }

    /// Starts looking for something by name, such as "keys", "a cup" or "the word exit".
    /// If already looking, switches to the new target.
    static func start(target request: String) {
        guard let target = ObjectFinder.target(for: request, in: targets) else {
            return Announcer.say(String(localized: "Say what to find, such as a cup, a door or the word exit."))
        }
        // Not a thing the finder knows, such as keys: say it will look for the words instead.
        let asked = normalized(request).split(separator: " ")
        let wantedWords = asked.contains { ["word", "words", "text", "sign"].contains($0) }
        if target.method == .text && !wantedWords {
            return start(target, intro: String(localized: "I can't recognize \(target.words.first ?? "") as an object, so I'll look for the words. Turn the camera slowly. The tone gets higher and faster as they come into view."))
        }
        start(target)
    }

    static func start(_ target: Target, intro: String? = nil) {
        if isRunning { stop(announce: false) }
        run += 1
        let thisRun = run
        current = target
        seen = false
        throttle = SpeechThrottle()
        let facingYou = cameraFacesYou
        FinderTone.reset()
        ObjectFinderModel.shared.update(running: true, status: String(localized: "Looking for \(target.thing)"))
        Tones.play(.status)
        Announcer.say(intro ?? String(localized: "Looking for \(target.thing). Turn the camera slowly. The tone gets higher and faster as it comes into view."))

        var frame = 0
        var confidence = 0.0
        feed.start({ pixels in
            frame += 1
            // Text recognition is slower, so look at fewer frames for it.
            guard frame % (target.method == .text ? 10 : 6) == 0 else { return }
            let sighting = look(for: target, in: pixels)
            confidence = smoothed(confidence, sighting?.confidence ?? 0)
            FinderTone.set(confidence: confidence, pan: sighting?.box.map { pan(for: $0, facingYou: facingYou) } ?? 0)
            guard confidence >= threshold(for: target.method) else { return }
            let box = sighting?.box
            DispatchQueue.main.async { spoke(box: box, thisRun: thisRun, facingYou: facingYou) }
        }, started: {
            // Start the tone once pictures arrive, after the announcement.
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                guard run == thisRun, isRunning else { return }
                FinderTone.start()
            }
        }, failed: { message in
            stop(announce: false)
            Announcer.say(message)
        })
        let work = DispatchWorkItem { if run == thisRun, isRunning { stop(announce: true) } }
        stopWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 60, execute: work)
    }

    private static func spoke(box: CGRect?, thisRun: Int, facingYou: Bool) {
        guard run == thisRun, isRunning, let target = current else { return }
        let text = phrase(for: target, box: box, first: !seen, facingYou: facingYou)
        guard throttle.shouldSay(text) else { return }
        seen = true
        ObjectFinderModel.shared.update(running: true, status: text)
        Announcer.say(text)
    }

    static func stop() { stop(announce: true) }

    private static func stop(announce: Bool) {
        run += 1
        stopWork?.cancel()
        feed.stop()
        FinderTone.stop()
        let message: String
        if let target = current, !seen {
            message = String(localized: "Object finder off. I didn't find \(target.thing).")
        } else {
            message = String(localized: "Object finder off.")
        }
        current = nil
        ObjectFinderModel.shared.update(running: false, status: message)
        if announce { Announcer.say(message) }
    }

    /// The tone moves toward the side the thing is on.
    private static func pan(for box: CGRect, facingYou: Bool) -> Float {
        switch direction(for: box, facingYou: facingYou) {
        case .left: -0.7
        case .ahead: 0
        case .right: 0.7
        }
    }

    /// Runs the right Vision request on one camera frame. Camera queue.
    private static func look(for target: Target, in pixels: CVPixelBuffer) -> Sighting? {
        let handler = VNImageRequestHandler(cvPixelBuffer: pixels)
        switch target.method {
        case .person:
            let request = VNDetectHumanRectanglesRequest()
            request.upperBodyOnly = false
            try? handler.perform([request])
            return (request.results ?? []).max { $0.confidence < $1.confidence }
                .map { Sighting(confidence: Double($0.confidence), box: $0.boundingBox) }
        case .animal:
            let request = VNRecognizeAnimalsRequest()
            try? handler.perform([request])
            return (request.results ?? []).compactMap { observation -> Sighting? in
                guard let label = observation.labels.first(where: { matches(label: $0.identifier, target: target) }) else { return nil }
                return Sighting(confidence: Double(label.confidence), box: observation.boundingBox)
            }.max { $0.confidence < $1.confidence }
        case .classify:
            let request = VNClassifyImageRequest()
            try? handler.perform([request])
            let best = (request.results ?? []).filter { matches(label: $0.identifier, target: target) }.map(\.confidence).max()
            return best.map { Sighting(confidence: Double($0), box: nil) }
        case .text:
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            try? handler.perform([request])
            let wanted = normalized(target.words.first ?? "")
            return (request.results ?? []).compactMap { observation -> Sighting? in
                guard let candidate = observation.topCandidates(1).first,
                      normalized(candidate.string).contains(wanted) else { return nil }
                // The box of just the words, when Vision can give it.
                let range = candidate.string.range(of: target.words.first ?? "", options: [.caseInsensitive, .diacriticInsensitive])
                let box = range.flatMap { try? candidate.boundingBox(for: $0)?.boundingBox } ?? observation.boundingBox
                return Sighting(confidence: Double(candidate.confidence), box: box)
            }.max { $0.confidence < $1.confidence }
        }
    }
}

// MARK: - Tone

/// A beeping tone that rises in pitch and speed with confidence. Like the light
/// detector's tone, it's made as it plays, so it changes smoothly.
private enum FinderTone {
    private static let engine = AVAudioEngine()
    nonisolated(unsafe) private static var frequency: Double = 330
    nonisolated(unsafe) private static var rate: Double = 1
    nonisolated(unsafe) private static var level: Float = 0.04
    nonisolated(unsafe) private static var pan: Float = 0
    nonisolated(unsafe) private static var phase: Double = 0
    nonisolated(unsafe) private static var beat: Double = 0

    static func reset() {
        set(confidence: 0, pan: 0)
    }

    /// Camera queue: the tone follows the latest confidence.
    static func set(confidence: Double, pan newPan: Float) {
        frequency = ObjectFinder.pitch(forConfidence: confidence)
        rate = ObjectFinder.beepRate(forConfidence: confidence)
        // Quiet ticking while nothing is seen, so you can tell it's still looking.
        level = confidence < 0.1 ? 0.04 : 0.12
        // In one-ear mode, the tone plays in that ear.
        pan = switch Preferences.shared.oneEar { case .off: newPan; case .left: -1; case .right: 1 }
    }

    static func start() {
        guard !engine.isRunning else { return }
        let sampleRate = 44100.0
        let source = AVAudioSourceNode { _, _, frameCount, bufferList in
            let buffers = UnsafeMutableAudioBufferListPointer(bufferList)
            let step = 2 * Double.pi * frequency / sampleRate
            let side = pan
            for frame in 0..<Int(frameCount) {
                beat += rate / sampleRate
                if beat >= 1 { beat -= 1 }
                // Each beep is the first third of a beat, faded in and out so it doesn't click.
                let envelope = beat < 0.33 ? sin(Double.pi * beat / 0.33) : 0
                let sample = Float(sin(phase) * envelope) * level
                phase += step
                if phase > 2 * Double.pi { phase -= 2 * Double.pi }
                for (index, buffer) in buffers.enumerated() {
                    let gain = index == 0 ? min(1, 1 - side) : min(1, 1 + side)
                    buffer.mData?.assumingMemoryBound(to: Float.self)[frame] = sample * gain
                }
            }
            return noErr
        }
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2)!
        engine.attach(source)
        engine.connect(source, to: engine.mainMixerNode, format: format)
        try? engine.start()
    }

    static func stop() {
        engine.stop()
        for node in engine.attachedNodes where node is AVAudioSourceNode { engine.detach(node) }
    }
}

// MARK: - Window

final class ObjectFinderModel: ObservableObject {
    static let shared = ObjectFinderModel()
    @Published private(set) var running = false
    @Published private(set) var status = String(localized: "Choose what to find, then press Find.")

    func update(running: Bool, status: String) {
        self.running = running
        self.status = status
    }
}

struct ObjectFinderView: View {
    @ObservedObject var model = ObjectFinderModel.shared
    @AppStorage(ObjectFinder.facesYouKey) private var facesYou = true
    @State private var search = ""
    @State private var selection: String?

    private var choices: [ObjectFinder.Target] {
        let all = ObjectFinder.targets
        let query = ObjectFinder.normalized(search)
        guard !query.isEmpty else { return all }
        let found = all.filter {
            ObjectFinder.normalized($0.name).contains(query) || $0.words.contains { ObjectFinder.normalized($0).contains(query) }
        }
        // Anything else is looked for as words, such as a sign.
        return found + [.text(search.trimmingCharacters(in: .whitespaces))]
    }

    var body: some View {
        Form {
            Section {
                TextField(String(localized: "Search, or type words to find"), text: $search)
                List(choices, selection: $selection) { target in
                    Text(target.name).tag(target.id)
                }
                .frame(minHeight: 220)
                .accessibilityLabel(String(localized: "Things to find"))
                HStack {
                    Button(model.running ? String(localized: "Stop") : String(localized: "Find")) {
                        if model.running { return ObjectFinder.stop() }
                        let target = choices.first { $0.id == selection } ?? (choices.count == 1 ? choices.first : nil)
                        guard let target else { return Announcer.say(String(localized: "Choose something to find first")) }
                        ObjectFinder.start(target)
                    }
                    .keyboardShortcut(.defaultAction)
                }
                Text(model.status)
            }
            Section {
                Toggle(String(localized: "The camera faces me"), isOn: $facesYou)
                Text(String(localized: "Leave this on for a Mac camera or an iPhone on the Mac. Turn it off if you point the camera away from you, so left and right are the right way round."))
                    .font(.caption).foregroundStyle(.secondary)
                Text(String(localized: "People, pets and words are found with a direction. Other things are only recognized in the picture, without a direction. Pictures are checked on your Mac and never saved or sent anywhere. The finder stops after a minute."))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 480, height: 560)
        .onChange(of: search) { _, _ in
            if !choices.contains(where: { $0.id == selection }) { selection = choices.first?.id }
        }
        .onDisappear { if model.running { ObjectFinder.stop() } }
    }
}

extension ObjectFinder {
    private static var window: NSWindow?

    /// Opens the finder's window, or brings it forward.
    static func showWindow() {
        let window = self.window ?? {
            let window = NSWindow(contentViewController: NSHostingController(rootView: ObjectFinderView()))
            window.title = String(localized: "Find an Object")
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            window.center()
            return window
        }()
        self.window = window
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }
}
