import Foundation
import WhisperKit

struct ArtefactCleaner {
    static let knownArtefacts: Set<String> = [
        "Hvala što pratite kanal.",
        "Хвала што пратите канал.",
        "Subtitrujuće",
        "Субтитрујуће",
    ]

    /// Filter out segments whose text matches a known artefact.
    /// Comparison is case-insensitive, whitespace-trimmed.
    static func clean(segments: [TranscriptionSegment]) -> [TranscriptionSegment] {
        segments.filter { seg in
            let trimmed = seg.text.trimmingCharacters(in: .whitespaces)
                .lowercased()
            return !knownArtefacts.contains { artefact in
                artefact.lowercased() == trimmed
            }
        }
    }
}
