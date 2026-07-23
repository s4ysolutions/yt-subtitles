import Foundation

struct AudioModifier {
    static func modifyForRetry(
        inputWAV: URL,
        outputWAV: URL,
        gainDB: Float = 6.0,
        tempo: Float = 0.85
    ) async throws {
        let filter = "volume=\(gainDB)dB,atempo=\(tempo)"
        try await ProcessRunner.run(
            executable: "ffmpeg",
            arguments: [
                "-loglevel", "error",
                "-i", inputWAV.path,
                "-af", filter,
                "-ar", "16000",
                "-ac", "1",
                "-f", "wav",
                "-y",
                outputWAV.path
            ]
        )
    }
}
