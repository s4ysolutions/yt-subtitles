import Foundation

struct TempFileManager {
    let directory: URL

    init() throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("yt-subtitles-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        self.directory = tmp
    }

    func path(_ filename: String) -> URL {
        directory.appendingPathComponent(filename)
    }

    func cleanup() {
        try? FileManager.default.removeItem(at: directory)
    }
}
