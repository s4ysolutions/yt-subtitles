import XCTest
@testable import yt_subtitles
import WhisperKit

final class QualityCheckerTests: XCTestCase {
    func testPassesGoodSegment() {
        let segment = TranscriptionSegment(
            id: 0, seek: 0, start: 0, end: 1, text: "Hello",
            tokens: [], tokenLogProbs: [[:]], temperature: 0,
            avgLogprob: -0.3, compressionRatio: 1.5, noSpeechProb: 0.1,
            words: [WordTiming(word: "Hello", tokens: [], start: 0, end: 1, probability: 0.9)]
        )
        let checker = QualityChecker()
        let result = checker.check(segment)
        XCTAssertTrue(result.pass)
        XCTAssertTrue(result.reasons.isEmpty)
    }
    
    func testFailsLowAvgLogprob() {
        let segment = TranscriptionSegment(
            id: 0, seek: 0, start: 0, end: 1, text: "Bad",
            tokens: [], tokenLogProbs: [[:]], temperature: 0,
            avgLogprob: -0.9, compressionRatio: 1.5, noSpeechProb: 0.1
        )
        let checker = QualityChecker()
        let result = checker.check(segment)
        XCTAssertFalse(result.pass)
        XCTAssertEqual(result.reasons.count, 1)
        XCTAssertTrue(result.reasons[0].contains("avgLogprob"))
    }
    
    func testFailsHighNoSpeechProb() {
        let segment = TranscriptionSegment(
            id: 0, seek: 0, start: 0, end: 1, text: "Silence",
            tokens: [], tokenLogProbs: [[:]], temperature: 0,
            avgLogprob: -0.3, compressionRatio: 1.5, noSpeechProb: 0.8
        )
        let checker = QualityChecker()
        let result = checker.check(segment)
        XCTAssertFalse(result.pass)
        XCTAssertTrue(result.reasons[0].contains("noSpeechProb"))
    }
    
    func testFailsHighCompressionRatio() {
        let segment = TranscriptionSegment(
            id: 0, seek: 0, start: 0, end: 1, text: "Repeated text",
            tokens: [], tokenLogProbs: [[:]], temperature: 0,
            avgLogprob: -0.3, compressionRatio: 3.0, noSpeechProb: 0.1
        )
        let checker = QualityChecker()
        let result = checker.check(segment)
        XCTAssertFalse(result.pass)
        XCTAssertTrue(result.reasons[0].contains("compressionRatio"))
    }
    
    func testFailsLowWordProbability() {
        let segment = TranscriptionSegment(
            id: 0, seek: 0, start: 0, end: 1, text: "Uncertain",
            tokens: [], tokenLogProbs: [[:]], temperature: 0,
            avgLogprob: -0.3, compressionRatio: 1.5, noSpeechProb: 0.1,
            words: [WordTiming(word: "Uncertain", tokens: [], start: 0, end: 1, probability: 0.5)]
        )
        let checker = QualityChecker()
        let result = checker.check(segment)
        XCTAssertFalse(result.pass)
        XCTAssertTrue(result.reasons[0].contains("word"))
    }
    
    func testMultipleFailures() {
        let segment = TranscriptionSegment(
            id: 0, seek: 0, start: 0, end: 1, text: "Bad",
            tokens: [], tokenLogProbs: [[:]], temperature: 0,
            avgLogprob: -0.9, compressionRatio: 3.0, noSpeechProb: 0.8
        )
        let checker = QualityChecker()
        let result = checker.check(segment)
        XCTAssertFalse(result.pass)
        XCTAssertGreaterThanOrEqual(result.reasons.count, 3)
    }
}
