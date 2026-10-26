import XCTest
@testable import VoiceOverAudioSplit

/// Contracted (grade 2) UEB through liblouis, and the uncontracted translator beside it.
final class BrailleGrade2Tests: XCTestCase {
    private func contracted(_ text: String) -> String { Braille.translate(text, grade: .contracted) }

    func testWholeWordContractions() {
        XCTAssertEqual(contracted("the"), "!")
        XCTAssertEqual(contracted("and"), "&")
        XCTAssertEqual(contracted("with"), ")")
        XCTAssertEqual(contracted("for"), "=")
        XCTAssertEqual(contracted("of"), "(")
        XCTAssertEqual(contracted("knowledge"), "k")
        XCTAssertEqual(contracted("people"), "p")
        XCTAssertEqual(contracted("about"), "ab")
        XCTAssertEqual(contracted("this is it"), "? is x")
        XCTAssertEqual(contracted("for children"), "= *n")
    }

    func testCapitalsNumbersAndPunctuation() {
        XCTAssertEqual(contracted("The cat and the dog."), ",! cat & ! dog4")
        XCTAssertEqual(contracted("Hello, world."), ",hello1 _w4")
        XCTAssertEqual(contracted("NASA 2026"), ",,nasa #bjbf")
        XCTAssertEqual(contracted("3.5 or 2a"), "#c4e or #b;a")
        XCTAssertEqual(contracted("1st of 10"), "#ast ( #aj")
        XCTAssertEqual(contracted("\"Yes\" (no)"), "8,yes0 \"<no\">")
        XCTAssertEqual(contracted("don\u{2019}t"), "don't")
        XCTAssertEqual(contracted("wait\u{2026}"), "wait444")
    }

    func testContractedOutputIsBrailleAscii() {
        let braille = contracted("Café au lait, with 2 sugars: 100% sure! 中 😀")
        XCTAssertFalse(braille.isEmpty)
        XCTAssertTrue(braille.allSatisfy { $0 == " " || (" a1b'k2l@cif/msp\"e3h9o6r^djg>ntq,*5<-u8v.%[$+x!&;:4\\0z7(_?w]#y)=").contains($0) })
        // Characters with no braille are left out, and counted.
        XCTAssertEqual(Braille.unsupported(in: "中 and 😀", grade: .contracted), 2)
        XCTAssertEqual(Braille.unsupported(in: "plain text, 3.5!", grade: .contracted), 0)
        XCTAssertEqual(contracted(""), "")
        XCTAssertEqual(contracted("tab\tx"), "tab ;x")
    }

    func testUncontractedIsUnchanged() {
        XCTAssertEqual(Braille.translate("Hello, world.", grade: .uncontracted), ",hello1 world4")
        XCTAssertEqual(Braille.translate("the and with", grade: .uncontracted), "the and with")
        XCTAssertEqual(Braille.translate("NASA 2026", grade: .uncontracted), ",,nasa #bjbf")
        XCTAssertEqual(Braille.translate("3D"), "#c,d")
        XCTAssertEqual(Braille.translate("knowledge"), "knowledge")
        XCTAssertEqual(Braille.unsupported(in: "ß and Ω"), 2)
    }

    func testContractedBrfPages() {
        let text = Array(repeating: "the people and their knowledge", count: 120).joined(separator: " ")
            + "\n\nWith 42 friends."
        let brf = Braille.brf(text, grade: .contracted, width: 40, height: 25)
        let pages = brf.components(separatedBy: "\u{0C}")
        XCTAssertGreaterThan(pages.count, 1)
        for page in pages {
            let lines = page.components(separatedBy: "\r\n").filter { !$0.isEmpty }
            XCTAssertLessThanOrEqual(lines.count, 25)
            XCTAssertTrue(lines.allSatisfy { $0.count <= 40 })
        }
        XCTAssertTrue(pages[0].hasPrefix(String(repeating: " ", count: 38) + "#a"))
        XCTAssertTrue(pages[1].hasPrefix(String(repeating: " ", count: 38) + "#b"))
        XCTAssertTrue(pages[0].contains("! p & _! k"))
        XCTAssertTrue(brf.hasSuffix(",) #db frs4"))
        XCTAssertTrue(brf.allSatisfy(\.isASCII))
        // Contracted braille takes fewer cells than uncontracted.
        XCTAssertLessThan(Braille.brf(text, grade: .contracted).count, Braille.brf(text).count)
    }
}
