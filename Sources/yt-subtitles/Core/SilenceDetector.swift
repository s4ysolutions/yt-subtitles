import Foundation

struct AudioChunk {
    /// Audio fed to Whisper. Its boundaries are extended *outward* to the
    /// nearest RMS silence so no word is cut and Whisper gets full context.
    let samples: [Float]
    /// Absolute time (seconds) of the first sample in `samples`. Whisper
    /// timestamps are relative to this.
    let offsetSeconds: Float
    /// Absolute time window (seconds) this chunk is *responsible* for. This is
    /// distinct from the audio window: neighbouring chunks overlap in audio for
    /// context, but each transcribed segment is kept only by the chunk whose
    /// keep-window contains the segment midpoint. The border between two
    /// neighbours sits in the middle of their overlap.
    let keepStart: Float
    let keepEnd: Float
}

struct SilenceDetector {

    /// Convert YAMNet speech regions to overlapping chunks.
    ///
    /// Two windows are tracked separately per chunk:
    ///
    /// 1. Transcribe window (audio): regions are tiled on a stride grid
    ///    (`windowSeconds` long, stepped by `strideSeconds`). Each tile is then
    ///    grown *outward* to the nearest RMS silence — start moves backward, end
    ///    moves forward — so chunks never begin or end mid-word and Whisper sees
    ///    generous context. Adjacent audio windows overlap heavily.
    ///
    /// 2. Keep window (subtitle ownership): the border between two neighbours is
    ///    the middle of their (nominal) overlap. Segments are assigned by
    ///    midpoint, so a boundary word may occasionally appear in both
    ///    neighbours — acceptable, and better than cutting it.
    ///
    /// The first region start also gets a `leadInSeconds` breath so Whisper can
    /// catch the very first sound.
    static func regionsToChunks(
        yamnetRegions: [SpeechRegion],
        allSamples: [Float],
        sampleRate: Int = 16000,
        leadInSeconds: Float = 0.3,
        tailPadSeconds: Float = 0.1,
        windowSeconds: Float = 9.0,
        strideSeconds: Float = 5.0,
        snapSearchSeconds: Float = 1.5,
        silenceFrameSeconds: Float = 0.02,
        silenceRMSThreshold: Float = 0.01
    ) -> [AudioChunk] {
        guard !yamnetRegions.isEmpty else {
            debug("regionsToChunks: no regions, returning empty.")
            return []
        }

        let sr = Float(sampleRate)
        let windowSamples = Int(windowSeconds * sr)
        let strideSamples = Int(strideSeconds * sr)
        let snapSearchSamples = Int(snapSearchSeconds * sr)
        let frameSamples = max(1, Int(silenceFrameSeconds * sr))

        var chunks: [AudioChunk] = []
        let logInterval = max(1, yamnetRegions.count / 10)

        for (idx, region) in yamnetRegions.enumerated() {
            if idx % logInterval == 0 {
                debug("regionsToChunks: processing region \(idx)/\(yamnetRegions.count)...")
            }
            let startSample = max(0, Int(region.start * sr) - Int(leadInSeconds * sr))
            let endSample = min(allSamples.count, Int(region.end * sr) + Int(tailPadSeconds * sr))
            guard endSample > startSample else { continue }

            // Short region: single chunk, owns everything it covers.
            if endSample - startSample <= windowSamples {
                chunks.append(makeChunk(
                    allSamples: allSamples, sr: sr,
                    start: startSample, end: endSample,
                    keepStart: Float(startSample) / sr - 0.25,
                    keepEnd: Float(endSample) / sr + 0.25
                ))
                continue
            }

            // Nominal overlapping windows on a stride grid (drives keep borders).
            var nominal: [(start: Int, end: Int)] = []
            var pos = startSample
            while true {
                let nominalEnd = pos + windowSamples
                if nominalEnd >= endSample {
                    nominal.append((pos, endSample))
                    break
                }
                nominal.append((pos, nominalEnd))
                pos += strideSamples
            }

            // Keep borders: middle of each nominal overlap. Subtitle ownership
            // is split here; segments are then assigned by midpoint.
            var borders: [Float] = []
            for i in 0..<(nominal.count - 1) {
                let overlapMid = (Float(nominal[i + 1].start) + Float(nominal[i].end)) / 2.0
                borders.append(overlapMid / sr)
            }

            for (i, n) in nominal.enumerated() {
                // Transcribe window: grow outward to nearest silence.
                // First region edge / last region edge stay put (already padded).
                let transStart = i == 0
                    ? n.start
                    : snapBackToSilence(
                        target: n.start,
                        floor: max(startSample, n.start - snapSearchSamples),
                        samples: allSamples,
                        frameSamples: frameSamples,
                        threshold: silenceRMSThreshold
                    )
                let transEnd = i == nominal.count - 1
                    ? n.end
                    : snapForwardToSilence(
                        target: n.end,
                        ceil: min(endSample, n.end + snapSearchSamples),
                        samples: allSamples,
                        frameSamples: frameSamples,
                        threshold: silenceRMSThreshold
                    )

                let keepStart = i == 0 ? Float(n.start) / sr - 0.25 : borders[i - 1]
                let keepEnd = i == nominal.count - 1 ? Float(n.end) / sr + 0.25 : borders[i]

                chunks.append(makeChunk(
                    allSamples: allSamples, sr: sr,
                    start: transStart, end: transEnd,
                    keepStart: keepStart, keepEnd: keepEnd
                ))
            }
        }

        debug("regionsToChunks: done, \(chunks.count) total chunks.")
        return chunks
    }

    /// Walk backwards from `target` (but not below `floor`) for the closest
    /// frame whose RMS is below `threshold`. Falls back to the quietest frame
    /// seen. Returns the sample index of the chosen frame start.
    private static func snapBackToSilence(
        target: Int,
        floor: Int,
        samples: [Float],
        frameSamples: Int,
        threshold: Float
    ) -> Int {
        guard target - frameSamples >= floor else { return target }

        var quietestPos = target
        var quietestRMS = Float.greatestFiniteMagnitude

        var frameEnd = target
        while frameEnd - frameSamples >= floor {
            let frameStart = frameEnd - frameSamples
            let rms = frameRMS(samples, frameStart, frameEnd, frameSamples)
            if rms < threshold {
                return frameStart  // closest silence to the target
            }
            if rms < quietestRMS {
                quietestRMS = rms
                quietestPos = frameStart
            }
            frameEnd = frameStart
        }
        return quietestPos
    }

    /// Walk forwards from `target` (but not above `ceil`) for the closest frame
    /// whose RMS is below `threshold`. Falls back to the quietest frame seen.
    /// Returns the sample index of the chosen frame end.
    private static func snapForwardToSilence(
        target: Int,
        ceil: Int,
        samples: [Float],
        frameSamples: Int,
        threshold: Float
    ) -> Int {
        guard target + frameSamples <= ceil else { return target }

        var quietestPos = target
        var quietestRMS = Float.greatestFiniteMagnitude

        var frameStart = target
        while frameStart + frameSamples <= ceil {
            let frameEnd = frameStart + frameSamples
            let rms = frameRMS(samples, frameStart, frameEnd, frameSamples)
            if rms < threshold {
                return frameEnd  // closest silence to the target
            }
            if rms < quietestRMS {
                quietestRMS = rms
                quietestPos = frameEnd
            }
            frameStart = frameEnd
        }
        return quietestPos
    }

    private static func frameRMS(_ samples: [Float], _ start: Int, _ end: Int, _ count: Int) -> Float {
        var sumSq: Float = 0
        for s in samples[start..<end] {
            sumSq += s * s
        }
        return sqrtf(sumSq / Float(count))
    }

    private static func makeChunk(
        allSamples: [Float],
        sr: Float,
        start: Int,
        end: Int,
        keepStart: Float,
        keepEnd: Float
    ) -> AudioChunk {
        AudioChunk(
            samples: Array(allSamples[start..<end]),
            offsetSeconds: Float(start) / sr,
            keepStart: keepStart,
            keepEnd: keepEnd
        )
    }

    private static func debug(_ msg: String) {
        FileHandle.standardError.write(Data("[yt-subtitles] \(msg)\n".utf8))
    }
}
