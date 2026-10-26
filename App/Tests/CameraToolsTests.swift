// CameraToolsTests.swift — checks the object finder's guidance and the accessible
// PDF maker without a camera: directions, matching, thresholds, heading guesses,
// and that a made PDF passes the Document Check.

import PDFKit
import XCTest
@testable import VoiceOverAudioSplit

final class ObjectFinderTests: XCTestCase {
    func testDirectionFromBox() {
        XCTAssertEqual(ObjectFinder.direction(for: CGRect(x: 0.05, y: 0.4, width: 0.2, height: 0.2)), .left)
        XCTAssertEqual(ObjectFinder.direction(for: CGRect(x: 0.4, y: 0.4, width: 0.2, height: 0.2)), .ahead)
        XCTAssertEqual(ObjectFinder.direction(for: CGRect(x: 0.75, y: 0.1, width: 0.2, height: 0.2)), .right)
    }

    func testDirectionSwapsWhenTheCameraFacesYou() {
        let pictureLeft = CGRect(x: 0.05, y: 0.4, width: 0.2, height: 0.2)
        XCTAssertEqual(ObjectFinder.direction(for: pictureLeft, facingYou: true), .right)
        XCTAssertEqual(ObjectFinder.direction(for: CGRect(x: 0.4, y: 0, width: 0.2, height: 1), facingYou: true), .ahead)
    }

    func testLabelsMatchWithSynonyms() {
        XCTAssertTrue(ObjectFinder.matches(label: "drinking_glass", target: "cup"))
        XCTAssertTrue(ObjectFinder.matches(label: "mug", target: "my mug"))
        XCTAssertTrue(ObjectFinder.matches(label: "Dog", target: "the puppy"))
        XCTAssertTrue(ObjectFinder.matches(label: "sunglasses", target: "glasses"))
        XCTAssertTrue(ObjectFinder.matches(label: "computer_mouse", target: "mouse"))
        XCTAssertTrue(ObjectFinder.matches(label: "phone", target: "find my iPhone"))
        XCTAssertFalse(ObjectFinder.matches(label: "cup", target: "door"))
        XCTAssertFalse(ObjectFinder.matches(label: "cat", target: "dog"))
    }

    func testRequestsBecomeTargets() {
        XCTAssertEqual(ObjectFinder.target(for: "find my phone")?.id, "phone")
        XCTAssertEqual(ObjectFinder.target(for: "Where are my shoes?")?.id, "shoes")
        XCTAssertEqual(ObjectFinder.target(for: "someone")?.method, .person)
        XCTAssertEqual(ObjectFinder.target(for: "dishes")?.id, "plate")
        let word = ObjectFinder.target(for: "find the word exit")
        XCTAssertEqual(word?.method, .text)
        XCTAssertEqual(word?.words, ["exit"])
        // Not a thing Vision knows: looked for as words.
        XCTAssertEqual(ObjectFinder.target(for: "my keys")?.method, .text)
        XCTAssertNil(ObjectFinder.target(for: "find the"))
        XCTAssertNil(ObjectFinder.target(for: "the word"))
    }

    func testTextTargetsMatchInsideLongerText() {
        let exit = ObjectFinder.Target.text("exit")
        XCTAssertTrue(ObjectFinder.matches(label: "Emergency EXIT only", target: exit))
        XCTAssertFalse(ObjectFinder.matches(label: "Entrance", target: exit))
    }

    func testThresholdsAndTone() {
        XCTAssertLessThan(ObjectFinder.threshold(for: .classify), ObjectFinder.threshold(for: .person))
        XCTAssertEqual(ObjectFinder.pitch(forConfidence: 0), 330, accuracy: 0.01)
        XCTAssertEqual(ObjectFinder.pitch(forConfidence: 1), 1320, accuracy: 0.01)
        XCTAssertEqual(ObjectFinder.pitch(forConfidence: 2), 1320, accuracy: 0.01)
        XCTAssertLessThan(ObjectFinder.beepRate(forConfidence: 0.2), ObjectFinder.beepRate(forConfidence: 0.8))
        // One confident frame isn't enough to cross the classifier's threshold from nothing.
        let once = ObjectFinder.smoothed(0, 0.6)
        XCTAssertLessThan(once, ObjectFinder.threshold(for: .classify))
        XCTAssertGreaterThan(ObjectFinder.smoothed(once, 0.6), ObjectFinder.threshold(for: .classify))
    }

    func testSpeechIsThrottled() {
        var throttle = ObjectFinder.SpeechThrottle()
        let start = Date()
        XCTAssertTrue(throttle.shouldSay("left", at: start))
        XCTAssertFalse(throttle.shouldSay("right", at: start.addingTimeInterval(1)))
        XCTAssertTrue(throttle.shouldSay("right", at: start.addingTimeInterval(2.5)))
        XCTAssertFalse(throttle.shouldSay("right", at: start.addingTimeInterval(5)))
        XCTAssertTrue(throttle.shouldSay("right", at: start.addingTimeInterval(9)))
    }

    func testPhrases() {
        let person = ObjectFinder.target(for: "person")!
        let cup = ObjectFinder.target(for: "cup")!
        XCTAssertEqual(ObjectFinder.phrase(for: cup, box: nil, first: true, facingYou: false), "I think I see a cup")
        XCTAssertEqual(ObjectFinder.phrase(for: person, box: CGRect(x: 0.4, y: 0.4, width: 0.2, height: 0.2), first: true, facingYou: false),
                       "Found a person, ahead")
        XCTAssertEqual(ObjectFinder.phrase(for: person, box: CGRect(x: 0, y: 0, width: 0.3, height: 0.9), first: false, facingYou: false),
                       "left")
        XCTAssertEqual(ObjectFinder.phrase(for: person, box: CGRect(x: 0.2, y: 0, width: 0.6, height: 0.9), first: false, facingYou: false),
                       "ahead, close")
    }

    func testEveryTargetHasLabelsOrIsText() {
        for target in ObjectFinder.catalog {
            XCTAssertFalse(target.labels.isEmpty, target.id)
            XCTAssertEqual(ObjectFinder.target(for: target.id)?.id, target.id)
        }
        XCTAssertFalse(ObjectFinder.targets.isEmpty)
    }
}

final class AccessiblePDFTests: XCTestCase {
    private func line(_ text: String, top: CGFloat, height: CGFloat = 0.02, x: CGFloat = 0.1, width: CGFloat = 0.8) -> AccessiblePDF.Line {
        AccessiblePDF.Line(text: text, box: CGRect(x: x, y: top - height, width: width, height: height))
    }

    func testHeadingLevelsFromSize() {
        XCTAssertEqual(AccessiblePDF.headingLevel(height: 0.04, bodyHeight: 0.02, text: "Welcome"), 1)
        XCTAssertEqual(AccessiblePDF.headingLevel(height: 0.027, bodyHeight: 0.02, text: "Your account"), 2)
        XCTAssertNil(AccessiblePDF.headingLevel(height: 0.021, bodyHeight: 0.02, text: "Normal text"))
        XCTAssertNil(AccessiblePDF.headingLevel(height: 0.04, bodyHeight: 0.02, text: "A big sentence."))
        XCTAssertNil(AccessiblePDF.headingLevel(height: 0.04, bodyHeight: 0.02, text: "2026"))
    }

    func testReadingOrderTopToBottomThenLeftToRight() {
        let lines = [
            line("Second", top: 0.7),
            line("Right", top: 0.9, x: 0.6, width: 0.3),
            line("Left", top: 0.9, x: 0.1, width: 0.3),
        ]
        XCTAssertEqual(AccessiblePDF.readingOrder(lines).map(\.text), ["Left", "Right", "Second"])
    }

    func testBlocksGroupHeadingsAndParagraphs() {
        let lines = [
            line("Water bill", top: 0.95, height: 0.05),
            line("Your bill for March is ready. The amount due is", top: 0.85),
            line("42 dollars, payable by April 10.", top: 0.825, width: 0.5),
            line("How to pay", top: 0.75, height: 0.03),
            line("Pay online or by phone. Keep this letter for your", top: 0.7),
            line("records and call us with ques-", top: 0.675),
            line("tions.", top: 0.65, width: 0.1),
        ]
        XCTAssertEqual(AccessiblePDF.blocks(from: lines), [
            .heading(level: 1, text: "Water bill"),
            .paragraph("Your bill for March is ready. The amount due is 42 dollars, payable by April 10."),
            .heading(level: 2, text: "How to pay"),
            .paragraph("Pay online or by phone. Keep this letter for your records and call us with questions."),
        ])
    }

    func testPlainTextAndTitles() {
        let blocks = AccessiblePDF.blocks(fromPlainText: "First line\nsecond line\n\nNew paragraph")
        XCTAssertEqual(blocks, [.paragraph("First line second line"), .paragraph("New paragraph")])
        XCTAssertEqual(AccessiblePDF.title(for: [blocks]), "First line second line")
        XCTAssertEqual(AccessiblePDF.title(for: [[.paragraph("x"), .heading(level: 2, text: "Menu")]]), "Menu")
        XCTAssertEqual(AccessiblePDF.normalizedLevels([[.heading(level: 2, text: "A")]]), [[.heading(level: 1, text: "A")]])
        XCTAssertEqual(AccessiblePDF.language(of: "This is a letter about your water bill and how to pay it."), "en")
        XCTAssertEqual(AccessiblePDF.language(of: "Ceci est une lettre au sujet de votre facture d'eau."), "fr")
    }

    func testMadePDFHasTextTagsTitleLanguageAndBookmarks() throws {
        let body = String(repeating: "The quick brown fox jumps over the lazy dog. ", count: 60)
        let pages: [[AccessiblePDF.Block]] = [
            [.heading(level: 1, text: "Report"), .paragraph(body), .heading(level: 2, text: "Details"), .paragraph(body)],
            [.paragraph("Second page text that is long enough to count as real text.")],
        ]
        let data = try XCTUnwrap(AccessiblePDF.document(pages: pages, title: "Report"))
        let pdf = try XCTUnwrap(PDFDocument(data: data))
        XCTAssertGreaterThanOrEqual(pdf.pageCount, 2)
        XCTAssertTrue(pdf.string?.contains("Second page text") == true)
        XCTAssertEqual(pdf.documentAttributes?[PDFDocumentAttribute.titleAttribute] as? String, "Report")
        XCTAssertEqual(pdf.outlineRoot?.numberOfChildren, 2)
        XCTAssertEqual(DocumentCheck.checkPDF(pdf), [], DocumentCheck.checkPDF(pdf).map(\.problem).joined(separator: " "))
        var language: CGPDFStringRef?
        XCTAssertTrue(CGPDFDictionaryGetString(try XCTUnwrap(pdf.documentRef?.catalog), "Lang", &language))
        XCTAssertEqual(language.flatMap(CGPDFStringCopyTextString) as String?, "en")
    }

    func testLanguageIsNotAddedTwice() throws {
        let data = try XCTUnwrap(AccessiblePDF.document(pages: [[.paragraph("Some text to check twice over here.")]], title: "T"))
        XCTAssertEqual(AccessiblePDF.addingLanguage("de", to: data), data)
        XCTAssertNil(AccessiblePDF.addingLanguage("en", to: Data("not a pdf".utf8)))
    }
}
