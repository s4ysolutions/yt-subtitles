import ArgumentParser
import Foundation

enum Resolution: String, ExpressibleByArgument, CaseIterable {
    case p144 = "144p"
    case p480 = "480p"
    case p720 = "720p"
    case p1080 = "1080p"

    var height: Int {
        switch self {
        case .p144: 144
        case .p480: 480
        case .p720: 720
        case .p1080: 1080
        }
    }
}

struct Muxer {
    let tempDir: TempFileManager
    let subtitlesLang: String
    let subtitlesTitle: String

    /// Mux a local video file with subtitles into mp4 (audio taken from the source video).
    func muxLocal(videoPath: URL, subtitlesPath: URL, output: URL) async throws {
        try await ProcessRunner.run(
            executable: "ffmpeg",
            arguments: [
                "-i", videoPath.path,
                "-f", "srt", "-i", subtitlesPath.path,
                "-c:v", "copy",
                "-c:a", "copy",
                "-c:s", "mov_text",
                "-map", "0:v:0",
                "-map", "0:a:0",
                "-map", "1:s:0",
                "-metadata:s:s:0", "language=\(subtitlesLang)",
                "-metadata:s:s:0", "title=\(subtitlesTitle)",
                "-y",
                output.path,
            ]
        )
    }
}
