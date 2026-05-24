import Foundation

struct AudioExtractor {
    let tempDir: TempFileManager

    /// Download audio from YouTube URL and convert to 16kHz mono WAV.
    /// Returns the path to the WAV file.
    func extract(url: String, baseName: String) async throws -> URL {
        let audioM4A = tempDir.path("\(baseName).m4a")
        let wav = tempDir.path("\(baseName).wav")

        try await ProcessRunner.run(
            executable: "yt-dlp",
            arguments: [
                "-f", "bestaudio[ext=m4a]",
                "-o", audioM4A.path,
                "--no-playlist",
                url,
            ]
        )

        try await ProcessRunner.run(
            executable: "ffmpeg",
            arguments: [
                "-i", audioM4A.path,
                "-ac", "1",
                "-ar", "16000",
                "-f", "wav",
                "-y",
                wav.path,
            ]
        )

        return wav
    }

    /// Download YouTube video+audio merged as mp4 at the requested resolution.
    /// Writes to `outputPath`; caller controls location (typically output dir, not temp).
    static func downloadVideo(url: String, resolution: Resolution, to outputPath: URL) async throws {
        try await ProcessRunner.run(
            executable: "yt-dlp",
            arguments: [
                // prefer mp4+m4a (copy-compatible); fall back to any format at height; then best overall
                "-f", "bestvideo[ext=mp4][height<=\(resolution.height)]+bestaudio[ext=m4a]/bestvideo[height<=\(resolution.height)]+bestaudio/best[height<=\(resolution.height)]",
                "--merge-output-format", "mp4",
                "-o", outputPath.path,
                "--no-playlist",
                url,
            ]
        )
    }

    /// Convert a local audio or video file to 16kHz mono WAV.
    /// Returns the path to the converted WAV file.
    static func convertToWav(input: URL, tempDir: TempFileManager) async throws -> URL {
        let name = input.deletingPathExtension().lastPathComponent
        let wav = tempDir.path("\(name).wav")

        try await ProcessRunner.run(
            executable: "ffmpeg",
            arguments: [
                "-i", input.path,
                "-ac", "1",
                "-ar", "16000",
                "-f", "wav",
                "-y",
                wav.path,
            ]
        )

        return wav
    }
}
