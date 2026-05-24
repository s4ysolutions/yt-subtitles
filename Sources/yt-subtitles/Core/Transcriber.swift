import CoreML
import Foundation
import WhisperKit

struct Transcriber {
    let model: String?
    let language: String?
    let modelDir: URL?
    let verbose: Bool

    init(model: String? = nil, language: String? = nil, modelDir: URL? = nil, verbose: Bool = false) {
        self.model = model
        self.language = language
        self.modelDir = modelDir
        self.verbose = verbose
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

        var allSegments: [TranscriptionSegment] = []
        let total = chunks.count

        for (i, chunk) in chunks.enumerated() {
            let dur = Float(chunk.samples.count) / 16000.0
            sd.write("Transcribing chunk \(i + 1)/\(total) (\(String(format: "%.1f", dur))s)...")
            let t0 = CFAbsoluteTimeGetCurrent()
            let results = try await pipe.transcribe(audioArray: chunk.samples, decodeOptions: options)
            let elapsed = CFAbsoluteTimeGetCurrent() - t0
            let speed = dur / Float(elapsed)
            let wallFmt = elapsed < 1.0
                ? String(format: "%.0fms", elapsed * 1000)
                : String(format: "%.1fs", elapsed)
            sd.write(" ok, \(wallFmt) wall, \(String(format: "%.1f", speed))x realtime\n")

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
                    allSegments.append(shifted)
                }
            }
        }

        return allSegments
    }
}

private func defaultModelDir() -> URL {
    let dir = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".yt-subtitles/models")
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir
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

