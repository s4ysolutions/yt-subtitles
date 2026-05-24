import XCTest
@testable import yt_subtitles
import WhisperKit

final class SubtitleWriterTests: XCTestCase {

    // Helper: create a minimal TranscriptionSegment
    func makeSegment(id: Int = 0, start: Float, end: Float, text: String) -> TranscriptionSegment {
        TranscriptionSegment(
            id: id,
            seek: 0,
            start: start,
            end: end,
            text: text,
            tokens: [],
            tokenLogProbs: [],
            temperature: 0,
            avgLogprob: 0,
            compressionRatio: 0,
            noSpeechProb: 0,
            words: nil
        )
    }

    // MARK: - Timestamp formatting

    func testFormatSRT() {
        let writer = SubtitleWriter()
        let result = writer.formatTimestampSRT(3661.5)
        XCTAssertEqual(result, "01:01:01,500")
    }

    func testFormatSRTZeroPadding() {
        let writer = SubtitleWriter()
        let result = writer.formatTimestampSRT(5.0)
        XCTAssertEqual(result, "00:00:05,000")
    }

    func testFormatVTT() {
        let writer = SubtitleWriter()
        let result = writer.formatTimestampVTT(3661.5)
        XCTAssertEqual(result, "01:01:01.500")
    }

    // MARK: - Padding

    func testPaddingApplied() {
        let writer = SubtitleWriter(padding: 0.5)
        let segs = [makeSegment(start: 1.0, end: 2.0, text: "Hello")]
        let entries = writer.buildEntries(segments: segs)
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries[0].start, 0.5)
        XCTAssertEqual(entries[0].end, 2.5)
    }

    func testPaddingClampedToZero() {
        let writer = SubtitleWriter(padding: 0.5)
        let segs = [makeSegment(start: 0.2, end: 1.0, text: "Hello")]
        let entries = writer.buildEntries(segments: segs)
        XCTAssertEqual(entries[0].start, 0.0)
    }

    // MARK: - Overlap resolution

    func testOverlapMidpointResolution() {
        let writer = SubtitleWriter(padding: 0.5)
        let segs = [
            makeSegment(start: 0.0, end: 1.0, text: "First"),
            makeSegment(start: 1.0, end: 2.0, text: "Second"),
        ]
        let entries = writer.buildEntries(segments: segs)
        // Padded: [0.0, 1.5], [0.5, 2.5] -> overlap 0.5..1.5
        // midpoint = (1.5 + 0.5) / 2 = 1.0
        XCTAssertEqual(entries.count, 2)
        XCTAssertEqual(entries[0].start, 0.0)
        XCTAssertEqual(entries[0].end, 1.0)
        XCTAssertEqual(entries[1].start, 1.0)
        XCTAssertEqual(entries[1].end, 2.5)
    }

    func testNoOverlap() {
        let writer = SubtitleWriter(padding: 0.5)
        let segs = [
            makeSegment(start: 0.0, end: 1.0, text: "First"),
            makeSegment(start: 3.0, end: 4.0, text: "Second"),
        ]
        let entries = writer.buildEntries(segments: segs)
        // Padded: [0.0, 1.5], [2.5, 4.5] -> no overlap
        XCTAssertEqual(entries.count, 2)
        XCTAssertEqual(entries[0].start, 0.0)
        XCTAssertEqual(entries[0].end, 1.5)
        XCTAssertEqual(entries[1].start, 2.5)
        XCTAssertEqual(entries[1].end, 4.5)
    }

    // MARK: - Filtering

    func testEmptyTextFiltered() {
        let writer = SubtitleWriter()
        let segs = [
            makeSegment(start: 0.0, end: 1.0, text: ""),
            makeSegment(start: 1.0, end: 2.0, text: "Valid"),
        ]
        let entries = writer.buildEntries(segments: segs)
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries[0].text, "Valid")
    }

    func testWhitespaceOnlyFiltered() {
        let writer = SubtitleWriter()
        let segs = [makeSegment(start: 0.0, end: 1.0, text: "   ")]
        let entries = writer.buildEntries(segments: segs)
        XCTAssertEqual(entries.count, 0)
    }

    // MARK: - SRT output

    func testSRTOutput() throws {
        let writer = SubtitleWriter(padding: 0.5)
        let segs = [makeSegment(start: 1.0, end: 2.0, text: "Hello world")]
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("test.srt")
        try writer.writeSRT(segments: segs, to: tmp)
        let content = try String(contentsOf: tmp, encoding: .utf8)
        XCTAssertTrue(content.contains("10\n"))
        XCTAssertTrue(content.contains("00:00:00,500 --> 00:00:02,500"))
        XCTAssertTrue(content.contains("Hello world"))
        try? FileManager.default.removeItem(at: tmp)
    }

    // MARK: - VTT output

    func testVTTOutput() throws {
        let writer = SubtitleWriter(padding: 0.5)
        let segs = [makeSegment(start: 1.0, end: 2.0, text: "Hello world")]
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("test.vtt")
        try writer.writeVTT(segments: segs, to: tmp)
        let content = try String(contentsOf: tmp, encoding: .utf8)
        XCTAssertTrue(content.hasPrefix("WEBVTT\n"))
        XCTAssertTrue(content.contains("00:00:00.500 --> 00:00:02.500"))
        XCTAssertTrue(content.contains("Hello world"))
        try? FileManager.default.removeItem(at: tmp)
    }
}
