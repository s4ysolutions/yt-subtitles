import XCTest
@testable import yt_subtitles

final class AudioModifierTests: XCTestCase {
    func testModifyCreatesFile() async throws {
        let tempDir = try TempFileManager()
        defer { tempDir.cleanup() }
        
        let inputWAV = tempDir.path("input.wav")
        let outputWAV = tempDir.path("output.wav")
        
        try await ProcessRunner.run(
            executable: "ffmpeg",
            arguments: [
                "-f", "lavfi",
                "-i", "sine=frequency=440:duration=0.1",
                "-ar", "16000",
                "-ac", "1",
                "-f", "wav",
                "-y",
                inputWAV.path
            ]
        )
        
        try await AudioModifier.modifyForRetry(
            inputWAV: inputWAV,
            outputWAV: outputWAV,
            gainDB: 6.0,
            tempo: 0.85
        )
        
        XCTAssertTrue(FileManager.default.fileExists(atPath: outputWAV.path))
        
        let attrs = try FileManager.default.attributesOfItem(atPath: outputWAV.path)
        let fileSize = attrs[.size] as! Int
        XCTAssertGreaterThan(fileSize, 0)
    }
}
