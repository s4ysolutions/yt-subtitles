import ArgumentParser
import Foundation
import WhisperKit

@main
struct YTSubtitles: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Download, transcribe, and subtitle YouTube videos."
    )

    @Argument(help: "YouTube video URL (omit if using --local-audio)")
    var youtubeURL: String? = nil

    @Option(help: "Transcribe a local audio file instead of downloading from YouTube")
    var localAudio: String? = nil

    @Option(help: "Transcribe and subtitle a local video file (any format ffmpeg supports)")
    var localVideo: String? = nil

    @Option(help: "Whisper model: tiny, base, small, large, full name, or glob. Default: small")
    var model: String? = nil

    @Option(help: "Audio language code (e.g. en, sr). Omit for auto-detect")
    var lang: String? = nil

    @Option(help: "Output file path. Default: derived from video title or input filename")
    var output: String? = nil

    @Flag(help: "Skip video remux; produce subtitle files only (default: SRT unless --srt or --vtt specified)")
    var noMux = false

    @Flag(help: "Also write SRT subtitle file alongside any other output")
    var srt = false

    @Flag(help: "Also write VTT subtitle file alongside any other output")
    var vtt = false

    @Option(help: "Language tag embedded in mp4 subtitle track")
    var subtitlesLang: String? = nil

    @Option(help: "Script conversion: off, lat, cyr. Auto: sr→cyr, hr→lat unless overridden")
    var translit: TranslitMode? = nil

    @Option(help: "Video resolution for muxed output")
    var resolution: Resolution = .p720

    @Flag(help: "Remove known Whisper hallucination artefacts")
    var cleanArtefacts = false

    @Option(help: "Override model cache directory")
    var modelDir: String? = nil

    @Flag(help: "Print detailed progress")
    var verbose = false

    @Flag(help: "List available Whisper models from HuggingFace and exit")
    var listModels = false

    @Flag(help: "Manage cached models. Without --model: list downloaded models. With --model <name>: delete that model from cache.")
    var cleanModel = false

    @Flag(help: "Enable segment quality check with retry (default: off)")
    var qualityCheck = false

    @Option(help: "Word probability threshold for quality check (0.0–1.0)")
    var qualityThreshold: Float = 0.45

    @Option(help: "AvgLogprob threshold for quality check (negative)")
    var avgLogprobThreshold: Float = -0.7

    @Option(help: "NoSpeechProb threshold for quality check (0.0–1.0)")
    var noSpeechProbThreshold: Float = 0.5

    @Option(help: "Max retry attempts per segment (0 = disabled)")
    var maxRetries: Int = 1

    @Option(help: "Gain boost in dB for retry")
    var retryGainDB: Float = 6.0

    @Option(help: "Tempo factor for retry (0.5–1.0)")
    var retryTempo: Float = 0.85

    @Flag(help: "Use RMS-based chunking (default)")
    var rms = false

    // MARK: - Entry

    mutating func run() async throws {
        // --- list models shortcut ---
        if listModels {
            info("Fetching model list from HuggingFace...")
            let available = try await WhisperKit.fetchAvailableModels()
            print("Available models (\(available.count)):")
            for name in available.sorted() {
                print("  \(name)")
            }
            return
        }

        // --- clean model cache ---
        if cleanModel {
            let cacheDir = Transcriber.defaultModelCacheDir(override: modelDir)
            // WhisperKit stores models at: <downloadBase>/models/argmaxinc/whisperkit-coreml/<name>/
            let modelsBase = cacheDir.appendingPathComponent("models/argmaxinc/whisperkit-coreml")
            let fm = FileManager.default
            if let modelName = model {
                let resolved = Self.resolveModelAlias(modelName)
                let target = modelsBase.appendingPathComponent(resolved)
                guard fm.fileExists(atPath: target.path) else {
                    print("Model not cached: \(resolved)")
                    print("Models dir: \(modelsBase.path)")
                    return
                }
                let size = directorySize(at: target)
                print("Remove \(resolved) (\(formatBytes(size)))? [y/N] ", terminator: "")
                fflush(stdout)
                let answer = readLine()?.lowercased() ?? "n"
                guard answer == "y" || answer == "yes" else {
                    print("Cancelled.")
                    return
                }
                try fm.removeItem(at: target)
                print("Removed: \(target.path)")

                // Clean HuggingFace download metadata for this model
                let downloadCache = modelsBase
                    .appendingPathComponent(".cache/huggingface/download")
                    .appendingPathComponent(resolved)
                if fm.fileExists(atPath: downloadCache.path) {
                    try? fm.removeItem(at: downloadCache)
                    print("Removed: \(downloadCache.path)")
                }

                // Clean openai/ tokenizer dir — only if no remaining model maps to it
                let openaiRoot = cacheDir.appendingPathComponent("models/openai")
                let remaining = (try? fm.contentsOfDirectory(at: modelsBase, includingPropertiesForKeys: nil))?
                    .filter { $0.lastPathComponent != ".cache" } ?? []
                if let openaiDir = Self.resolveOpenaiDir(for: resolved, in: openaiRoot, fm: fm) {
                    let isShared = remaining.contains {
                        Self.resolveOpenaiDir(for: $0.lastPathComponent, in: openaiRoot, fm: fm)?.path == openaiDir.path
                    }
                    if !isShared {
                        try? fm.removeItem(at: openaiDir)
                        print("Removed: \(openaiDir.path)")
                    }
                }

                // If no model dirs remain, remove repo-level config.json and empty scaffold
                if remaining.isEmpty {
                    let repoConfig = modelsBase.appendingPathComponent("config.json")
                    if fm.fileExists(atPath: repoConfig.path) {
                        try? fm.removeItem(at: repoConfig)
                        print("Removed: \(repoConfig.path)")
                    }
                    // Remove .cache dir too (only download metadata, now all stale)
                    let cacheSubdir = modelsBase.appendingPathComponent(".cache")
                    if fm.fileExists(atPath: cacheSubdir.path) {
                        try? fm.removeItem(at: cacheSubdir)
                        print("Removed: \(cacheSubdir.path)")
                    }
                }
            } else {
                guard fm.fileExists(atPath: modelsBase.path) else {
                    print("No models cached yet (\(modelsBase.path))")
                    return
                }
                let contents = (try? fm.contentsOfDirectory(
                    at: modelsBase,
                    includingPropertiesForKeys: [.isDirectoryKey]
                )) ?? []
                let dirs = contents.filter {
                    $0.lastPathComponent != ".cache" &&
                    (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
                }.sorted { $0.lastPathComponent < $1.lastPathComponent }
                if dirs.isEmpty {
                    print("No models cached (\(modelsBase.path))")
                } else {
                    print("Cached models (\(modelsBase.path)):")
                    for dir in dirs {
                        let size = directorySize(at: dir)
                        print("  \(dir.lastPathComponent)  \(formatBytes(size))")
                    }
                    print("\nUse --clean-model --model <name> to remove one.")
                }
            }
            return
        }

        // --- preflight ---
        let isLocal = localAudio != nil || localVideo != nil
        var tools = ["ffmpeg"]
        if !isLocal { tools.append("yt-dlp") }
        for tool in tools {
            guard ProcessRunner.isOnPath(tool) else {
                throw ProcessError.missingExecutable(tool)
            }
        }

        // --- validate local file paths early ---
        if let path = localAudio, !FileManager.default.fileExists(atPath: path) {
            throw ValidationError("File not found: \(path)")
        }
        if let path = localVideo, !FileManager.default.fileExists(atPath: path) {
            throw ValidationError("File not found: \(path)")
        }

        let audioOnly = localAudio != nil
        // --srt/--vtt are additive output formats; they don't suppress mux.
        // Only --no-mux (or audio-only input) disables mux.
        let subtitleMode = noMux || audioOnly
        let wantMux = !subtitleMode
        // Default to SRT when subtitle mode active but no explicit format chosen
        let wantSRT = srt || (subtitleMode && !vtt)
        let wantVTT = vtt
        if audioOnly {
            info("--local-audio: no video stream; producing subtitle file only.")
        }

        let tempDir = try TempFileManager()
        defer { tempDir.cleanup() }

        // --- branch: local audio or YouTube ---
        var videoForMux: URL? = nil
        let wavPath: URL
        let baseName: String

        if let localPath = localAudio {
            let localURL = URL(fileURLWithPath: localPath)
            baseName = output ?? localURL.deletingPathExtension().lastPathComponent
            info("Launching ffmpeg to convert audio to 16kHz mono WAV...")
            wavPath = try await AudioExtractor.convertToWav(input: localURL, tempDir: tempDir)
        } else if let localPath = localVideo {
            let localURL = URL(fileURLWithPath: localPath)
            baseName = output ?? localURL.deletingPathExtension().lastPathComponent
            info("Extracting audio from local video...")
            wavPath = try await AudioExtractor.convertToWav(input: localURL, tempDir: tempDir)
            if wantMux { videoForMux = localURL }
        } else if let url = youtubeURL {
            let videoTitle = try await getVideoTitle(url: url)
            baseName = output ?? sanitizeFilename(videoTitle)
            if wantMux {
                let videoPath = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                    .appendingPathComponent(baseName)
                    .appendingPathExtension("mp4")
                if FileManager.default.fileExists(atPath: videoPath.path) {
                    info("Using cached video: \(videoPath.lastPathComponent)")
                } else {
                    info("Downloading video from YouTube (\(resolution.rawValue))...")
                    try await AudioExtractor.downloadVideo(url: url, resolution: resolution, to: videoPath)
                    info("Saved: \(videoPath.path)")
                }
                videoForMux = videoPath
                info("Extracting audio for transcription...")
                wavPath = try await AudioExtractor.convertToWav(input: videoPath, tempDir: tempDir)
            } else {
                info("Downloading audio from YouTube...")
                let extractor = AudioExtractor(tempDir: tempDir)
                wavPath = try await extractor.extract(url: url, baseName: baseName)
            }
        } else {
            throw ValidationError("Provide a YouTube URL, --local-audio <path>, or --local-video <path>.")
        }

        let outputDir = FileManager.default.currentDirectoryPath
        let effectiveModel = model ?? "small"
        // source always untouched; output gets model name or .subtitle to avoid conflict
        let modelSuffix: String
        if output != nil {
            modelSuffix = ""
        } else {
            modelSuffix = ".\(effectiveModel)"
        }
        let outputBase = URL(fileURLWithPath: outputDir).appendingPathComponent(baseName + modelSuffix)

        // --- pipeline ---
        debug("Loading audio...")
        let samples = try AudioProcessor.loadAudioAsFloatArray(fromPath: wavPath.path)

        debug("Running speech detection...")
        debug("Using RMS chunking strategy...")
        let finalChunks = SilenceDetector.rmsChunks(
            allSamples: samples,
            sampleRate: 16000
        )
        info("\(finalChunks.count) chunk(s) after splitting.")

        guard !finalChunks.isEmpty else {
            info("No speech detected — stopping. Provide --lang to skip auto-detection.")
            return
        }

        debug("Setting up model...")
        let modelDirURL = modelDir.map { URL(fileURLWithPath: $0) }
        let resolvedModel = Self.resolveModelAlias(effectiveModel)
        debug("Model alias resolved: \(resolvedModel)")
        
        let qualityChecker: QualityChecker?
        if qualityCheck {
            debug("Creating quality checker...")
            qualityChecker = QualityChecker(
                avgLogprobThreshold: avgLogprobThreshold,
                noSpeechProbThreshold: noSpeechProbThreshold,
                wordProbThreshold: qualityThreshold
            )
        } else {
            qualityChecker = nil
        }
        
        debug("Creating transcriber...")
        let transcriber = Transcriber(
            model: resolvedModel,
            language: lang,
            modelDir: modelDirURL,
            verbose: verbose,
            qualityChecker: qualityChecker,
            maxRetries: maxRetries,
            retryGainDB: retryGainDB,
            retryTempo: retryTempo
        )
        debug("Starting transcription...")
        var segments = try await transcriber.transcribe(chunks: finalChunks)

        if cleanArtefacts {
            let before = segments.count
            segments = ArtefactCleaner.clean(segments: segments)
            debug("Removed \(before - segments.count) artefact segment(s).")
        }

        let effectiveTranslit: TranslitMode = translit ?? {
            switch lang?.lowercased() {
            case "sr": return .cyr
            case "hr": return .lat
            default:   return .off
            }
        }()

        if effectiveTranslit != .off {
            segments = segments.map { seg in
                TranscriptionSegment(
                    id: seg.id, seek: seg.seek,
                    start: seg.start, end: seg.end,
                    text: Transliterator.transliterate(seg.text, mode: effectiveTranslit),
                    tokens: seg.tokens, tokenLogProbs: seg.tokenLogProbs,
                    temperature: seg.temperature, avgLogprob: seg.avgLogprob,
                    compressionRatio: seg.compressionRatio,
                    noSpeechProb: seg.noSpeechProb, words: seg.words
                )
            }
        }

        let srtLang = subtitlesLang ?? lang ?? "en"
        let writer = SubtitleWriter()

        // --- write subtitle files ---
        if wantSRT {
            let srtPath = outputBase.appendingPathExtension("srt")
            debug("Writing SRT...")
            try writer.writeSRT(segments: segments, to: srtPath)
            info("SRT: \(srtPath.path)")
        }
        if wantVTT {
            let vttPath = outputBase.appendingPathExtension("vtt")
            debug("Writing VTT...")
            try writer.writeVTT(segments: segments, to: vttPath)
            info("VTT: \(vttPath.path)")
        }

        // --- mux ---
        if wantMux, let videoPath = videoForMux {
            let mp4Path = outputBase.appendingPathExtension("mp4")
            // Write SRT to temp dir — intermediate only, not user output
            let tempSrtPath = tempDir.path("\(baseName).srt")
            try writer.writeSRT(segments: segments, to: tempSrtPath)
            let muxer = Muxer(
                tempDir: tempDir,
                subtitlesLang: srtLang,
                subtitlesTitle: subtitlesLang ?? lang ?? "en"
            )
            info("Muxing mp4...")
            try await muxer.muxLocal(
                videoPath: videoPath,
                subtitlesPath: tempSrtPath,
                output: mp4Path
            )
            info("MP4: \(mp4Path.path)")
        }
    }

    // MARK: - Helpers

    private func info(_ msg: String) {
        FileHandle.standardError.write(Data("[yt-subtitles] \(msg)\n".utf8))
    }

    private func debug(_ msg: String) {
        if verbose {
            FileHandle.standardError.write(Data("[yt-subtitles] \(msg)\n".utf8))
        }
    }

    private func getVideoTitle(url: String) async throws -> String {
        let result = try await ProcessRunner.run(
            executable: "yt-dlp",
            arguments: ["--get-title", "--no-playlist", url]
        )
        return result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func resolveModelAlias(_ name: String) -> String {
        switch name.lowercased() {
        case "tiny":  return "openai_whisper-tiny"
        case "base":  return "openai_whisper-base"
        case "small": return "openai_whisper-small"
        case "large": return "openai_whisper-large-v3-v20240930"
        default:      return name
        }
    }

    private func sanitizeFilename(_ title: String) -> String {
        let invalid = CharacterSet(charactersIn: "/\\?%*:|\"<>")
        var clean = title.components(separatedBy: invalid).joined(separator: "_")
        clean = clean.trimmingCharacters(in: .whitespaces)
        if clean.isEmpty { clean = "subtitles" }
        return clean
    }

    /// Maps `openai_whisper-<variant>` → `<openaiRoot>/whisper-<base>` by trying progressively
    /// shorter suffixes until a matching directory exists.
    /// e.g. "openai_whisper-large-v3-v20240930" → tries whisper-large-v3-v20240930,
    ///      whisper-large-v3 (found), whisper-large, ...
    private static func resolveOpenaiDir(for modelName: String, in openaiRoot: URL, fm: FileManager) -> URL? {
        guard modelName.hasPrefix("openai_whisper-") else { return nil }
        var parts = String(modelName.dropFirst("openai_whisper-".count)).components(separatedBy: "-")
        while !parts.isEmpty {
            let candidate = openaiRoot.appendingPathComponent("whisper-" + parts.joined(separator: "-"))
            if fm.fileExists(atPath: candidate.path) { return candidate }
            parts.removeLast()
        }
        return nil
    }

    private func directorySize(at url: URL) -> Int64 {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey]) else { return 0 }
        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            total += Int64((try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        }
        return total
    }

    private func formatBytes(_ bytes: Int64) -> String {
        let gb = Double(bytes) / 1_073_741_824
        if gb >= 1 { return String(format: "%.1f GB", gb) }
        let mb = Double(bytes) / 1_048_576
        if mb >= 1 { return String(format: "%.0f MB", mb) }
        return "\(bytes / 1024) KB"
    }
    
}
