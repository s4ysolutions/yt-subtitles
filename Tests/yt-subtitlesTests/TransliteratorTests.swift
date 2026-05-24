import XCTest
@testable import yt_subtitles

final class TransliteratorTests: XCTestCase {

    // MARK: - Latin → Cyrillic

    func testLatinToCyrillicSimple() {
        let result = Transliterator.transliterate("Dobro jutro", mode: .cyr)
        XCTAssertEqual(result, "Добро јутро")
    }

    func testLatinDigraphDz() {
        let result = Transliterator.transliterate("džemper", mode: .cyr)
        XCTAssertEqual(result, "џемпер")
    }

    func testLatinDigraphLj() {
        let result = Transliterator.transliterate("ljubav", mode: .cyr)
        XCTAssertEqual(result, "љубав")
    }

    func testLatinDigraphNj() {
        let result = Transliterator.transliterate("njiva", mode: .cyr)
        XCTAssertEqual(result, "њива")
    }

    func testLatinDigraphTitleDz() {
        let result = Transliterator.transliterate("Džemper", mode: .cyr)
        XCTAssertEqual(result, "Џемпер")
    }

    func testLatinDigraphUpperDz() {
        let result = Transliterator.transliterate("DŽEMPER", mode: .cyr)
        XCTAssertEqual(result, "ЏЕМПЕР")
    }

    func testLatinDigraphTitleLj() {
        let result = Transliterator.transliterate("Ljubav", mode: .cyr)
        XCTAssertEqual(result, "Љубав")
    }

    func testLatinDigraphUpperNj() {
        let result = Transliterator.transliterate("NJIVA", mode: .cyr)
        XCTAssertEqual(result, "ЊИВА")
    }

    // MARK: - Cyrillic → Latin

    func testCyrillicToLatinSimple() {
        let result = Transliterator.transliterate("Добро јутро", mode: .lat)
        XCTAssertEqual(result, "Dobro jutro")
    }

    func testCyrillicDigraphDz() {
        let result = Transliterator.transliterate("џемпер", mode: .lat)
        XCTAssertEqual(result, "džemper")
    }

    func testCyrillicDigraphLj() {
        let result = Transliterator.transliterate("љубав", mode: .lat)
        XCTAssertEqual(result, "ljubav")
    }

    func testCyrillicDigraphNj() {
        let result = Transliterator.transliterate("њива", mode: .lat)
        XCTAssertEqual(result, "njiva")
    }

    func testCyrillicUpperDz() {
        let result = Transliterator.transliterate("Џемпер", mode: .lat)
        XCTAssertEqual(result, "Džemper")
    }

    // MARK: - Round-trip

    func testRoundTrip() {
        let original = "Džemper ljubav njiva"
        let cyr = Transliterator.transliterate(original, mode: .cyr)
        let back = Transliterator.transliterate(cyr, mode: .lat)
        XCTAssertEqual(back, original)
    }

    // MARK: - Pass-through

    func testOffMode() {
        let text = "Hello world! 123"
        let result = Transliterator.transliterate(text, mode: .off)
        XCTAssertEqual(result, text)
    }

    func testPunctuationPreservedLatinToCyrillic() {
        let result = Transliterator.transliterate("Zdravo, svete!", mode: .cyr)
        XCTAssertEqual(result, "Здраво, свете!")
    }

    func testPunctuationPreservedCyrillicToLatin() {
        let result = Transliterator.transliterate("Здраво, свете!", mode: .lat)
        XCTAssertEqual(result, "Zdravo, svete!")
    }
}
