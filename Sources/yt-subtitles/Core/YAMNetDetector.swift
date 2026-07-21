import CoreML
import Foundation
import WhisperKit

struct SpeechRegion {
    let start: Float
    let end: Float
}

struct YAMNetDetector {
    let modelPath: URL
    let threshold: Float
    let segmentLength: Int = 15680 // 0.98s at 16kHz
    
    private let featureExtractor = LogMelFeatureExtractor()
    
    init(modelPath: URL, threshold: Float = 0.5) {
        self.modelPath = modelPath
        self.threshold = threshold
    }
    
    func detectSpeechSegments(wavPath: URL) async throws -> [SpeechRegion] {
        guard FileManager.default.fileExists(atPath: modelPath.path) else {
            debug("[yt-subtitles] YAMNet model not found at \(modelPath.path), skipping YAMNet detection")
            return []
        }
        
        let model = try MLModel(contentsOf: modelPath)
        let audioSamples = try AudioProcessor.loadAudioAsFloatArray(fromPath: wavPath.path)
        
        var speechRegions: [SpeechRegion] = []
        var currentRegionStart: Float? = nil
        
        let sampleRate = 16000
        var i = 0
        
        while i + segmentLength <= audioSamples.count {
            let segment = Array(audioSamples[i..<i+segmentLength])
            let isSpeech = try await predictSpeech(segment: segment, model: model)
            
            if isSpeech {
                if currentRegionStart == nil {
                    currentRegionStart = Float(i) / Float(sampleRate)
                }
            } else if let start = currentRegionStart {
                let end = Float(i) / Float(sampleRate)
                speechRegions.append(SpeechRegion(start: start, end: end))
                currentRegionStart = nil
            }
            
            i += segmentLength
        }
        
        if let start = currentRegionStart {
            let end = Float(audioSamples.count) / Float(sampleRate)
            speechRegions.append(SpeechRegion(start: start, end: end))
        }
        
        return mergeRegions(speechRegions)
    }
    
    private func predictSpeech(segment: [Float], model: MLModel) async throws -> Bool {
        let patches = featureExtractor.extractFeatures(from: segment)
        
        for patch in patches {
            let input = try MLDictionaryFeatureProvider(dictionary: [
                "features": MLFeatureValue(multiArray: patch)
            ])
            
            let output = try await model.prediction(from: input)
            guard let scores = output.featureValue(for: "Identity")?.multiArrayValue else {
                continue
            }
            
            var speechScore: Float = 0
            for classIdx in 0..<min(7, scores.count) {
                let score = scores[[0, NSNumber(value: classIdx)]].floatValue
                speechScore = max(speechScore, score)
            }
            
            if speechScore > threshold {
                return true
            }
        }
        
        return false
    }
    
    private func mergeRegions(_ regions: [SpeechRegion]) -> [SpeechRegion] {
        guard !regions.isEmpty else { return [] }
        
        let sorted = regions.sorted { $0.start < $1.start }
        var merged: [SpeechRegion] = [sorted[0]]
        
        for region in sorted.dropFirst() {
            if region.start <= merged.last!.end {
                merged[merged.count - 1] = SpeechRegion(
                    start: merged.last!.start,
                    end: max(merged.last!.end, region.end)
                )
            } else {
                merged.append(region)
            }
        }
        
        return merged
    }
}

private func debug(_ msg: String) {
    FileHandle.standardError.write(Data("[yt-subtitles] \(msg)\n".utf8))
}
