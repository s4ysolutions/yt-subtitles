import Foundation
import WhisperKit

struct QualityChecker {
    var avgLogprobThreshold: Float = -1.0
    var noSpeechProbThreshold: Float = 0.5
    var compressionRatioThreshold: Float = 2.4
    var wordProbThreshold: Float = 0.5
    
    func check(_ segment: TranscriptionSegment) -> QualityResult {
        var reasons: [String] = []
        
        if segment.avgLogprob < avgLogprobThreshold {
            reasons.append("avgLogprob \(String(format: "%.2f", segment.avgLogprob)) < \(avgLogprobThreshold)")
        }
        
        if segment.noSpeechProb > noSpeechProbThreshold {
            reasons.append("noSpeechProb \(String(format: "%.2f", segment.noSpeechProb)) > \(noSpeechProbThreshold)")
        }
        
        if segment.compressionRatio > compressionRatioThreshold {
            reasons.append("compressionRatio \(String(format: "%.2f", segment.compressionRatio)) > \(compressionRatioThreshold)")
        }
        
        if let words = segment.words {
            for word in words {
                let trimmed = word.word.trimmingCharacters(in: .whitespaces).trimmingCharacters(in: .punctuationCharacters)
                if trimmed.count < 4 { continue }
                if word.probability < wordProbThreshold {
                    reasons.append("word '\(word.word)' prob \(String(format: "%.2f", word.probability)) < \(wordProbThreshold)")
                    break
                }
            }
        }
        
        return QualityResult(pass: reasons.isEmpty, reasons: reasons)
    }
}

struct QualityResult {
    let pass: Bool
    let reasons: [String]
}
