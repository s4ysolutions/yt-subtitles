import Foundation

struct AudioChunk {
    /// Audio fed to Whisper. May include context padding beyond subtitle boundaries.
    let samples: [Float]
    /// Absolute time (seconds) of the original chunk start (before padding).
    /// Whisper timestamps are relative to this.
    let offsetSeconds: Float
    /// Absolute time window (seconds) this chunk is *responsible* for subtitles.
    /// Segments are kept only if their midpoint falls within this window.
    let keepStart: Float
    let keepEnd: Float
}

struct SilenceDetector {

    /// Simple RMS-based chunking: accumulate speech up to `maxDuration` seconds.
    /// When maxDuration reached, cut at a silence boundary — backward first, forward fallback.
    /// Audio fed to Whisper is padded outward by `contextPadSeconds` for better context,
    /// but subtitle boundaries (keepStart/keepEnd) remain at the original speech edges.
    static func rmsChunks(
        allSamples: [Float],
        sampleRate: Int = 16000,
        maxDuration: Float = 9.0,
        minChunkSeconds: Float = 2.0,
        rmsThreshold: Float = 0.01,
        frameSeconds: Float = 0.02,
        silenceGapSeconds: Float = 0.5,
        contextPadSeconds: Float = 0.45
    ) -> [AudioChunk] {
        let sr = Float(sampleRate)
        let frameSamples = max(1, Int(frameSeconds * sr))
        let maxSamples = Int(maxDuration * sr)
        let minChunkSamples = Int(minChunkSeconds * sr)
        let silenceGapFrames = max(1, Int(silenceGapSeconds / frameSeconds))
        let padSamples = Int(contextPadSeconds * sr)

        var chunks: [AudioChunk] = []
        var chunkStart: Int = 0
        var silenceStartFrame: Int = -1
        var lastSilenceMiddleFrame: Int = -1
        var exceededMax = false

        func emitChunk(end: Int) {
            guard end > chunkStart else { return }

            // Pad audio window outward for Whisper context (subtitle boundaries unchanged).
            let audioStart = max(0, chunkStart - padSamples)
            let audioEnd = min(allSamples.count, end + padSamples)

            chunks.append(AudioChunk(
                samples: Array(allSamples[audioStart..<audioEnd]),
                offsetSeconds: Float(audioStart) / sr,
                keepStart: Float(chunkStart) / sr,
                keepEnd: Float(end) / sr
            ))

            chunkStart = end
            silenceStartFrame = -1
            lastSilenceMiddleFrame = -1
            exceededMax = false
        }

        var i = 0
        while i < allSamples.count {
            let frameEnd = min(i + frameSamples, allSamples.count)
            let rms = frameRMS(allSamples, i, frameEnd, frameEnd - i)
            let frameIndex = i / frameSamples
            let isSpeech = rms > rmsThreshold

            if isSpeech {
                if silenceStartFrame >= 0 {
                    lastSilenceMiddleFrame = silenceStartFrame + (frameIndex - silenceStartFrame) / 2
                }
                silenceStartFrame = -1

                if exceededMax {
                    if lastSilenceMiddleFrame >= 0 {
                        let cutSample = lastSilenceMiddleFrame * frameSamples
                        let chunkLen = cutSample - chunkStart
                        if chunkLen >= minChunkSamples {
                            emitChunk(end: cutSample)
                            continue
                        }
                    }
                }
            } else {
                if silenceStartFrame < 0 {
                    silenceStartFrame = frameIndex
                }

                let currentDuration = i - chunkStart
                if currentDuration >= maxSamples {
                    exceededMax = true

                    let silenceLen = frameIndex - silenceStartFrame
                    if silenceLen >= silenceGapFrames {
                        let cutFrame = silenceStartFrame + silenceLen / 2
                        let cutSample = min(cutFrame * frameSamples, allSamples.count)
                        emitChunk(end: cutSample)
                    }
                }
            }

            i += frameSamples
        }

        let end = allSamples.count
        if end > chunkStart {
            emitChunk(end: end)
        }

        debug("rmsChunks: done, \(chunks.count) total chunks.")
        return chunks
    }

    private static func frameRMS(_ samples: [Float], _ start: Int, _ end: Int, _ count: Int) -> Float {
        var sumSq: Float = 0
        for s in samples[start..<end] {
            sumSq += s * s
        }
        return sqrtf(sumSq / Float(count))
    }

    private static func debug(_ msg: String) {
        FileHandle.standardError.write(Data("[yt-subtitles] \(msg)\n".utf8))
    }
}
