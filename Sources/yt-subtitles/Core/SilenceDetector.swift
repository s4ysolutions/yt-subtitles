import Foundation

struct AudioChunk {
    let samples: [Float]
    let offsetSeconds: Float
}

private struct SilenceRegion {
    var startWindow: Int
    var endWindow: Int
}

struct SilenceDetector {

    /// Split float32 PCM samples into chunks at silence gaps.
    ///
    /// Algorithm:
    /// - Scan with non-overlapping RMS windows (100ms at 16kHz)
    /// - Mark windows as silent where RMS < threshold
    /// - Merge consecutive silent windows into silence regions
    /// - Keep regions with duration >= minSilence
    /// - Split at midpoint of each qualifying silence region
    /// - Expand each chunk by paddingSeconds on each side (clamped to bounds)
    static func detectChunks(
        samples: [Float],
        sampleRate: Int = 16000,
        windowSize: Int = 1600,
        threshold: Float = 0.01,
        minSilence: Float = 1.5,
        paddingSeconds: Float = 0.1
    ) -> [AudioChunk] {
        guard !samples.isEmpty else { return [] }

        let windowDuration = Float(windowSize) / Float(sampleRate)
        let paddingSamples = Int(paddingSeconds * Float(sampleRate))

        // Pass 1: classify each window as silent or speech
        var isSilent: [Bool] = []
        var i = 0
        while i + windowSize <= samples.count {
            let window = samples[i..<(i + windowSize)]
            let sumSq = window.reduce(0) { $0 + $1 * $1 }
            let rms = sqrtf(sumSq / Float(windowSize))
            isSilent.append(rms < threshold)
            i += windowSize
        }
        // Classify any remaining tail samples shorter than one full window
        if i < samples.count {
            let tail = samples[i...]
            let sumSq = tail.reduce(0) { $0 + $1 * $1 }
            let rms = sqrtf(sumSq / Float(tail.count))
            isSilent.append(rms < threshold)
        }

        guard !isSilent.isEmpty else { return [] }

        // Pass 2: merge consecutive silent windows into regions
        var regions: [SilenceRegion] = []
        var regionStart: Int? = nil

        for (j, silent) in isSilent.enumerated() {
            if silent {
                if regionStart == nil { regionStart = j }
            } else if let start = regionStart {
                regions.append(SilenceRegion(startWindow: start, endWindow: j - 1))
                regionStart = nil
            }
        }
        if let start = regionStart {
            regions.append(SilenceRegion(startWindow: start, endWindow: isSilent.count - 1))
        }

        // Filter to qualifying regions (duration >= minSilence)
        let qualified = regions.filter {
            let dur = Float($0.endWindow - $0.startWindow + 1) * windowDuration
            return dur >= minSilence
        }

        // Pass 3: compute split points (midpoints of qualified silence regions, in samples)
        let splitSamples = qualified.map { region -> Int in
            let windowMid = Float(region.startWindow + region.endWindow + 1) / 2.0
            return Int(windowMid * Float(windowSize))
        }

        // Pass 4: slice chunks with padding
        var chunks: [AudioChunk] = []
        var prevEnd = 0

        for split in splitSamples {
            let end = min(split, samples.count)
            if end > prevEnd {
                let padStart = max(0, prevEnd - paddingSamples)
                let padEnd = min(samples.count, end + paddingSamples)
                let padded = Array(samples[padStart..<padEnd])
                let offset = Float(padStart) / Float(sampleRate)
                chunks.append(AudioChunk(samples: padded, offsetSeconds: offset))
            }
            prevEnd = split
        }

        // Final chunk: remaining audio after last split
        if prevEnd < samples.count {
            let padStart = max(0, prevEnd - paddingSamples)
            let padded = Array(samples[padStart..<samples.count])
            let offset = Float(padStart) / Float(sampleRate)
            chunks.append(AudioChunk(samples: padded, offsetSeconds: offset))
        }

        return chunks
    }
    
    /// Merge YAMNet speech regions with RMS-detected chunks.
    ///
    /// This combines the strengths of both approaches:
    /// - YAMNet: precise speech boundaries, catches quiet speech
    /// - RMS: fine-grained splitting within speech regions
    static func mergeWithYAMNet(
        yamnetRegions: [SpeechRegion],
        rmsChunks: [AudioChunk],
        allSamples: [Float],
        sampleRate: Int = 16000,
        paddingSeconds: Float = 0.1
    ) -> [AudioChunk] {
        guard !yamnetRegions.isEmpty else {
            return rmsChunks
        }
        
        let paddingSamples = Int(paddingSeconds * Float(sampleRate))
        var mergedChunks: [AudioChunk] = []
        
        for region in yamnetRegions {
            let startSample = Int(region.start * Float(sampleRate))
            let endSample = Int(region.end * Float(sampleRate))
            
            let clampedStart = max(0, startSample - paddingSamples)
            let clampedEnd = min(allSamples.count, endSample + paddingSamples)
            
            guard clampedEnd > clampedStart else { continue }
            
            let regionSamples = Array(allSamples[clampedStart..<clampedEnd])
            let offset = Float(clampedStart) / Float(sampleRate)
            
            let regionChunk = AudioChunk(samples: regionSamples, offsetSeconds: offset)
            
            let subChunks = detectChunks(
                samples: regionSamples,
                sampleRate: sampleRate,
                threshold: 0.01,
                minSilence: 0.5,
                paddingSeconds: 0
            )
            
            if subChunks.isEmpty {
                mergedChunks.append(regionChunk)
            } else {
                for subChunk in subChunks {
                    let absoluteOffset = offset + subChunk.offsetSeconds
                    mergedChunks.append(AudioChunk(
                        samples: subChunk.samples,
                        offsetSeconds: absoluteOffset
                    ))
                }
            }
        }
        
        return mergedChunks.sorted { $0.offsetSeconds < $1.offsetSeconds }
    }
}
