import ArgumentParser
import Foundation
import WhisperKit

struct SubtitleWriter {

    /// Padding added to each side of a segment, in seconds.
    let padding: TimeInterval

    init(padding: TimeInterval = 0.5) {
        self.padding = padding
    }

    /// Write SRT file from transcription segments.
    func writeSRT(segments: [TranscriptionSegment], to url: URL) throws {
        let entries = buildEntries(segments: segments)
        var output = ""
        for (i, entry) in entries.enumerated() {
            // Numbered in steps of 10 (10, 20, 30…) so manual edits can insert
            // new entries between existing ones without renumbering the whole file.
            let index = (i + 1) * 10
            output += "\(index)\n"
            output += "\(formatTimestampSRT(entry.start)) --> \(formatTimestampSRT(entry.end))\n"
            output += "\(entry.text)\n\n"
        }
        try output.write(to: url, atomically: true, encoding: .utf8)
    }

    /// Write VTT file from transcription segments.
    func writeVTT(segments: [TranscriptionSegment], to url: URL) throws {
        let entries = buildEntries(segments: segments)
        var output = "WEBVTT\n\n"
        for entry in entries {
            output += "\(formatTimestampVTT(entry.start)) --> \(formatTimestampVTT(entry.end))\n"
            output += "\(entry.text)\n\n"
        }
        try output.write(to: url, atomically: true, encoding: .utf8)
    }

    // MARK: - Internal

    struct Entry {
        let start: TimeInterval
        let end: TimeInterval
        let text: String
    }

    /// Apply 500ms padding and resolve overlaps at midpoints.
    func buildEntries(segments: [TranscriptionSegment]) -> [Entry] {
        guard !segments.isEmpty else { return [] }

        // Apply padding
        var entries = segments.map { seg in
            let s = max(0, Double(seg.start) - padding)
            let e = Double(seg.end) + padding
            return Entry(start: s, end: e, text: seg.text.trimmingCharacters(in: .whitespaces))
        }

        // Resolve overlaps: if entry[i].end > entry[i+1].start, split at midpoint
        for i in 0..<(entries.count - 1) {
            if entries[i].end > entries[i + 1].start {
                let midpoint = (entries[i].end + entries[i + 1].start) / 2.0
                entries[i] = Entry(start: entries[i].start, end: midpoint, text: entries[i].text)
                entries[i + 1] = Entry(start: midpoint, end: entries[i + 1].end, text: entries[i + 1].text)
            }
        }

        // Drop entries with non-positive duration
        return entries.filter { $0.end > $0.start && !$0.text.isEmpty }
    }

    func formatTimestampSRT(_ t: TimeInterval) -> String {
        let h = Int(t) / 3600
        let m = (Int(t) % 3600) / 60
        let s = Int(t) % 60
        let ms = min(999, Int((t - Double(Int(t))) * 1000))
        return String(format: "%02d:%02d:%02d,%03d", h, m, s, ms)
    }

    func formatTimestampVTT(_ t: TimeInterval) -> String {
        let h = Int(t) / 3600
        let m = (Int(t) % 3600) / 60
        let s = Int(t) % 60
        let ms = min(999, Int((t - Double(Int(t))) * 1000))
        return String(format: "%02d:%02d:%02d.%03d", h, m, s, ms)
    }
}
