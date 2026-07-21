import XCTest
@testable import yt_subtitles

final class YAMNetDetectorTests: XCTestCase {
    func testMissingModelReturnsEmpty() async throws {
        let tempDir = try TempFileManager()
        defer { tempDir.cleanup() }
        
        let fakeModelPath = tempDir.path("nonexistent.mlmodel")
        let detector = YAMNetDetector(modelPath: fakeModelPath, threshold: 0.5)
        
        let result = try await detector.detectSpeechSegments(wavPath: tempDir.path("test.wav"))
        XCTAssertTrue(result.isEmpty)
    }
}
