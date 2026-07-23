import XCTest
@testable import yt_subtitles

final class YAMNetDetectorTests: XCTestCase {
    func testSilentAudioReturnsEmpty() async throws {
        let tempDir = try TempFileManager()
        defer { tempDir.cleanup() }

        let wavPath = tempDir.path("silence.wav")
        let samples = [Int16](repeating: 0, count: 32000)
        let data = Data(bytes: samples, count: samples.count * MemoryLayout<Int16>.size)
        let header = wavHeader(dataCount: data.count, sampleRate: 16000)
        try (header + data).write(to: wavPath)

        let detector = YAMNetDetector()
        let result = try await detector.detectSpeechSegments(wavPath: wavPath)
        XCTAssertTrue(result.isEmpty)
    }

    func testSpeechAudioReturnsRegions() async throws {
        let tempDir = try TempFileManager()
        defer { tempDir.cleanup() }

        let wavPath = tempDir.path("speech.wav")
        var samples = [Int16](repeating: 0, count: 16000)
        for i in 0..<16000 {
            let t = Float(i) / 16000.0
            let amplitude = Int16(sinf(t * 2 * .pi * 440) * 16000)
            samples[i] = amplitude
        }
        let data = Data(bytes: samples, count: samples.count * MemoryLayout<Int16>.size)
        let header = wavHeader(dataCount: data.count, sampleRate: 16000)
        try (header + data).write(to: wavPath)

        let detector = YAMNetDetector()
        let result = try await detector.detectSpeechSegments(wavPath: wavPath)
        XCTAssertFalse(result.isEmpty)
    }
}

/// Write a minimal WAV header for 16-bit mono PCM.
private func wavHeader(dataCount: Int, sampleRate: Int) -> Data {
    var header = Data()
    let channels: UInt16 = 1
    let bitsPerSample: UInt16 = 16
    let byteRate = sampleRate * Int(channels) * Int(bitsPerSample) / 8
    let blockAlign = channels * bitsPerSample / 8
    let dataSize = UInt32(dataCount)
    let fileSize = UInt32(dataCount) + 36

    header.append("RIFF".data(using: .ascii)!)
    header.append(withUnsafeBytes(of: fileSize) { Data($0) })
    header.append("WAVE".data(using: .ascii)!)
    header.append("fmt ".data(using: .ascii)!)
    let fmtChunkSize: UInt32 = 16
    let audioFormat: UInt16 = 1
    header.append(withUnsafeBytes(of: fmtChunkSize) { Data($0) })
    header.append(withUnsafeBytes(of: audioFormat) { Data($0) })
    header.append(withUnsafeBytes(of: UInt16(channels)) { Data($0) })
    header.append(withUnsafeBytes(of: UInt32(sampleRate)) { Data($0) })
    header.append(withUnsafeBytes(of: UInt32(byteRate)) { Data($0) })
    header.append(withUnsafeBytes(of: UInt16(blockAlign)) { Data($0) })
    header.append(withUnsafeBytes(of: UInt16(bitsPerSample)) { Data($0) })
    header.append("data".data(using: .ascii)!)
    header.append(withUnsafeBytes(of: dataSize) { Data($0) })
    return header
}
