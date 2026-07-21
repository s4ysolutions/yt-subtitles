import CoreML
import Foundation
import WhisperKit

struct Transcriber {
    let model: String?
    let language: String?
    let modelDir: URL?
    let verbose: Bool
    let qualityChecker: QualityChecker
    let maxRetries: Int
    let retryGainDB: Float
    let retryTempo: Float
    
    init(
        model: String? = nil,
        language: String? = nil,
        modelDir: URL? = nil,
        verbose: Bool = false,
        qualityChecker: QualityChecker = QualityChecker(),
        maxRetries: Int = 1,
        retryGainDB: Float = 6.0,
        retryTempo: Float = 0.85
    ) {
        self.model = model
        self.language = language
        self.modelDir = modelDir
        self.verbose = verbose
        self.qualityChecker = qualityChecker
        self.maxRetries = maxRetries
        self.retryGainDB = retryGainDB
        self.retryTempo = retryTempo
    }

    /// Transcribe audio chunks sequentially, returning segments with absolute timestamps.
    func transcribe(chunks: [AudioChunk]) async throws -> [TranscriptionSegment] {
        let sd = stderr()
        let repo = "argmaxinc/whisperkit-coreml"
        let downloadBase = modelDir ?? defaultModelDir()

        // Resolve model variant (same logic as WhisperKit.setupModels)
        let modelVariant: String
        if let model {
            modelVariant = model
        } else {
            if verbose { sd.write("Querying recommended model...\n") }
            let support = await WhisperKit.recommendedRemoteModels(
                from: repo,
                downloadBase: downloadBase
            )
            modelVariant = support.default
        }

        // Pre-download. Hub API fires its progress callback once per completed file (not
        // per byte), so a spinner is more honest than a fake percentage bar.
        // First dot appears after 1 s — cached models return before that → no output.
        sd.write("Model: \(modelVariant)\n")
        let dotsPrinted = ProgressFlag()
        let dotTask = Task {
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            sd.write("  Downloading")
            dotsPrinted.mark()
            while !Task.isCancelled {
                sd.write(".")
                try? await Task.sleep(for: .seconds(1))
            }
        }
        let folder: URL
        do {
            folder = try await WhisperKit.download(
                variant: modelVariant,
                downloadBase: downloadBase,
                from: repo
            )
        } catch {
            dotTask.cancel()
            await dotTask.value
            if dotsPrinted.value { sd.write("\n") }
            throw error
        }
        dotTask.cancel()
        await dotTask.value
        if dotsPrinted.value { sd.write(" done\n") }

        sd.write("Model path: \(folder.path)\n")

        // Now init WhisperKit with cached model (download: false)
        let compileNote = (try? needsCompilation(folder)) == true
            ? "(first run: compiling for Core ML, ~1-2 min)"
            : "(cached)"
        sd.write("Loading model \(compileNote)\n")

        let t0 = CFAbsoluteTimeGetCurrent()
        let config = WhisperKitConfig(
            model: modelVariant,
            downloadBase: downloadBase,
            modelFolder: folder.path,
            verbose: false,
            logLevel: .info,
            download: false
        )
        let pipe = try await WhisperKit(config)
        let elapsed = CFAbsoluteTimeGetCurrent() - t0
        let cu = pipe.modelCompute
        sd.write("Model ready (\(String(format: "%.1f", elapsed))s). Compute: Mel=\(cu.melCompute.label), AudioEnc=\(cu.audioEncoderCompute.label), TextDec=\(cu.textDecoderCompute.label)\n")

        // Auto-detect language from mid-audio chunk (skip intros/jingles)
        let effectiveLang: String
        if let lang = language {
            effectiveLang = lang
        } else {
            let detectIdx = chunks.count / 3
            let detectChunk = chunks[detectIdx]
            sd.write("Detecting language (chunk \(detectIdx + 1)/\(chunks.count), \(String(format: "%.1f", Float(detectChunk.samples.count) / 16000.0))s)...")
            let detectResult = try await pipe.transcribe(
                audioArray: detectChunk.samples,
                decodeOptions: DecodingOptions(
                    temperature: 0.0,
                    usePrefillPrompt: false,
                    skipSpecialTokens: true,
                    wordTimestamps: false,
                    chunkingStrategy: ChunkingStrategy.none
                )
            )
            effectiveLang = detectResult.first?.language ?? "en"
            sd.write(" \(effectiveLang)\n")
        }

        let options = DecodingOptions(
            language: effectiveLang,
            temperature: 0.0,
            skipSpecialTokens: true,
            wordTimestamps: true,
            chunkingStrategy: ChunkingStrategy.none
        )

        let tempDir = try TempFileManager()
        var allSegments: [TranscriptionSegment] = []
        let total = chunks.count

        for (i, chunk) in chunks.enumerated() {
            var currentChunk = chunk
            var attempt = 0
            var chunkSegments: [TranscriptionSegment] = []
            
            while attempt <= maxRetries {
                let dur = Float(currentChunk.samples.count) / 16000.0
                sd.write("Transcribing chunk \(i + 1)/\(total) (\(String(format: "%.1f", dur))s)")
                if attempt > 0 {
                    sd.write(" [retry \(attempt)/\(maxRetries)]")
                }
                sd.write("...")
                let t0 = CFAbsoluteTimeGetCurrent()
                let results = try await pipe.transcribe(audioArray: currentChunk.samples, decodeOptions: options)
                let elapsed = CFAbsoluteTimeGetCurrent() - t0
                let speed = dur / Float(elapsed)
                let wallFmt = elapsed < 1.0
                    ? String(format: "%.0fms", elapsed * 1000)
                    : String(format: "%.1fs", elapsed)
                sd.write(" ok, \(wallFmt) wall, \(String(format: "%.1f", speed))x realtime\n")

                chunkSegments = []
                for result in results {
                    for segment in result.segments {
                        let shifted = TranscriptionSegment(
                            id: segment.id,
                            seek: segment.seek,
                            start: segment.start + chunk.offsetSeconds,
                            end: segment.end + chunk.offsetSeconds,
                            text: segment.text,
                            tokens: segment.tokens,
                            tokenLogProbs: segment.tokenLogProbs,
                            temperature: segment.temperature,
                            avgLogprob: segment.avgLogprob,
                            compressionRatio: segment.compressionRatio,
                            noSpeechProb: segment.noSpeechProb,
                            words: segment.words?.map { word in
                                WordTiming(
                                    word: word.word,
                                    tokens: word.tokens,
                                    start: word.start + chunk.offsetSeconds,
                                    end: word.end + chunk.offsetSeconds,
                                    probability: word.probability
                                )
                            }
                        )
                        chunkSegments.append(shifted)
                    }
                }
                
                let qualityResults = chunkSegments.map { qualityChecker.check($0) }
                let allPass = qualityResults.allSatisfy { $0.pass }
                
                if allPass || attempt == maxRetries {
                    break
                }
                
                let failedReasons = qualityResults.filter { !$0.pass }.flatMap { $0.reasons }
                sd.write("  Quality check failed: \(failedReasons.joined(separator: ", "))\n")
                
                let inputWAV = tempDir.path("chunk_\(chunk.offsetSeconds)_\(i).wav")
                let outputWAV = tempDir.path("chunk_\(chunk.offsetSeconds)_\(i)_retry_\(attempt).wav")
                
                try writeWAV(samples: currentChunk.samples, to: inputWAV.path)
                
                try await AudioModifier.modifyForRetry(
                    inputWAV: inputWAV,
                    outputWAV: outputWAV,
                    gainDB: retryGainDB,
                    tempo: retryTempo
                )
                
                let modifiedSamples = try AudioProcessor.loadAudioAsFloatArray(fromPath: outputWAV.path)
                currentChunk = AudioChunk(samples: modifiedSamples, offsetSeconds: chunk.offsetSeconds)
                
                attempt += 1
            }
            
            allSegments.append(contentsOf: chunkSegments)
        }

        return allSegments
    }
    
    private func writeWAV(samples: [Float], to path: String) throws {
        let url = URL(fileURLWithPath: path)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["ffmpeg", "-f", "s16le", "-ar", "16000", "-ac", "1", "-i", "pipe:0", "-y", path]
        
        let pipe = Pipe()
        process.standardInput = pipe
        
        try process.run()
        
        var int16Samples = samples.map { Int16(max(-32768, min(32767, $0 * 32767))) }
        let data = Data(bytes: &int16Samples, count: int16Samples.count * MemoryLayout<Int16>.size)
        pipe.fileHandleForWriting.write(data)
        pipe.fileHandleForWriting.closeFile()
        
        process.waitUntilExit()
    }
}

private func defaultModelDir() -> URL {
    let dir = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".yt-subtitles/models")
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir
}

extension Transcriber {
    /// Returns the model cache directory. Respects an explicit override path if provided.
    static func defaultModelCacheDir(override: String? = nil) -> URL {
        if let override {
            return URL(fileURLWithPath: override)
        }
        return defaultModelDir()
    }
}

private func stderr() -> FileHandle { FileHandle.standardError }
private extension FileHandle {
    func write(_ string: String) {
        write(Data(string.utf8))
    }
}

/// Sendable flag for tracking whether the download progress callback fired at least once.
private final class ProgressFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var _value = false
    func mark() { lock.withLock { _value = true } }
    var value: Bool { lock.withLock { _value } }
}

private func needsCompilation(_ folder: URL) throws -> Bool {
    let fm = FileManager.default
    let contents = try fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
    let hasPackage = contents.contains { $0.pathExtension == "mlpackage" }
    let hasCompiled = contents.contains { $0.pathExtension == "mlmodelc" }
    return hasPackage && !hasCompiled
}

private extension MLComputeUnits {
    var label: String {
        switch self {
        case .cpuOnly: "CPU"
        case .cpuAndGPU: "CPU+GPU"
        case .all: "CPU+GPU+ANE"
        case .cpuAndNeuralEngine: "CPU+ANE"
        default: "unknown"
        }
    }
}

