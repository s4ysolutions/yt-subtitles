# YAMNet Speech Detection + Quality Retry Design

**Date:** 2026-07-21  
**Project:** yt-subtitles (Swift CLI)  
**Status:** Approved for implementation

---

## Problem Statement

Serbian (and other) videos have two failure modes with current RMS-based silence detection:
1. **Missed speech** — YAMNet (Google's audio event classifier) detects speech that RMS misses, especially quiet/far-field speech
2. **Low-quality transcriptions** — Whisper sometimes produces low-confidence segments (low `avgLogprob`, high `noSpeechProb`, low word probabilities); retrying with audio modification (louder/slower) often fixes this

Reference: `~/Downloads/youtubesubtitles.py` uses YAMNet via TensorFlow Hub for speech segment extraction.

---

## Design Overview

### New Components

| File | Purpose |
|------|---------|
| `Core/YAMNetDetector.swift` | Core ML YAMNet wrapper; returns speech segments `[start, end]` |
| `Core/QualityChecker.swift` | Evaluates `TranscriptionSegment` quality metrics; returns pass/fail + reasons |
| `Core/AudioModifier.swift` | ffmpeg-based audio modification for retry (+gain, tempo change) |
| `Entry.swift` additions | CLI flags; pipeline integration |

### Pipeline Integration Points

```
Audio (WAV) 
    │
    ├─▶ [YAMNetDetector] ──▶ speechSegments [(start, end)]
    │
    ├─▶ [SilenceDetector] ──▶ rmsChunks [(offset, samples)]
    │
    └─▶ merge: union of YAMNet + RMS segments → final chunks
    
    For each chunk:
        Transcriber.transcribe(chunk) → segments
        │
        ├─▶ QualityChecker.check(segment) → pass/fail
        │       │
        │       └─▶ if fail && retries < max: AudioModifier.modify() → retry
        │
        └─▶ collect passing segments
```

---

## Detailed Design

### 1. YAMNetDetector.swift

```swift
struct YAMNetDetector {
    let modelPath: URL
    let threshold: Float = 0.5    // speech class probability threshold
    let segmentLength: Int = 15680 // 0.98s at 16kHz (YAMNet standard)
    
    func detectSpeechSegments(wavPath: URL) async throws -> [(start: Float, end: Float)]
}
```

- **Model source:** `yamnet.mlmodel` from TF Hub (converted to Core ML) — bundled in `~/.yt-subtitles/models/`
- **Classes 0-6** = speech classes in YAMNet taxonomy (indices 0-6 cover "Speech", "Conversation", "Narration", etc.)
- **Algorithm:** Slide 0.98s windows, average class scores, threshold at 0.5, merge adjacent speech windows, expand by 0.5s on each side
- **Fallback:** If model missing or inference fails → log warning, return empty array (RMS-only mode)

### 2. QualityChecker.swift

```swift
struct QualityChecker {
    var avgLogprobThreshold: Float = -0.7      // segment-level
    var noSpeechProbThreshold: Float = 0.5     // segment-level
    var compressionRatioThreshold: Float = 2.4 // segment-level
    var wordProbThreshold: Float = 0.7         // word-level; fail if ANY word below
    
    func check(_ segment: TranscriptionSegment) -> QualityResult
}

struct QualityResult {
    let pass: Bool
    let reasons: [String]  // e.g. ["avgLogprob -0.9 < -0.7", "word 'srpski' prob 0.62 < 0.7"]
}
```

**Thresholds based on Whisper literature:**
- `avgLogprob < -0.7` → likely hallucination/low quality
- `noSpeechProb > 0.5` → model thinks it's silence
- `compressionRatio > 2.4` → repetitive text
- `word.probability < 0.7` → unreliable word timing

### 3. AudioModifier.swift

```swift
struct AudioModifier {
    static func modifyForRetry(
        inputWAV: URL,
        outputWAV: URL,
        gainDB: Float = 6.0,      // +6dB = 2× amplitude
        tempo: Float = 0.85       // 15% slower
    ) async throws
}
```

- Uses `ffmpeg -af "volume=6dB,atempo=0.85"`
- Preserves 16kHz mono WAV format
- Creates temp file; caller manages cleanup

### 4. CLI Flags (Entry.swift)

| Flag | Type | Default | Description |
|------|------|---------|-------------|
| `--yamnet` / `--no-yamnet` | Flag | `true` | Enable/disable YAMNet speech detection |
| `--yamnet-threshold` | Float | `0.5` | Speech class probability threshold |
| `--yamnet-model` | String | `~/.yt-subtitles/models/yamnet.mlmodel` | Path to Core ML model |
| `--quality-threshold` | Float | `0.7` | Word probability threshold |
| `--avg-logprob-threshold` | Float | `-0.7` | Segment avgLogprob threshold |
| `--no-speech-prob-threshold` | Float | `0.5` | Segment noSpeechProb threshold |
| `--max-retries` | Int | `1` | Max retry attempts per segment (0 = disabled) |
| `--retry-gain-db` | Float | `6.0` | Gain boost for retry |
| `--retry-tempo` | Float | `0.85` | Tempo factor for retry |

### 5. Chunk Merging Logic

```swift
func mergeSegments(yamnet: [(Float, Float)], rms: [AudioChunk]) -> [AudioChunk] {
    // Convert RMS chunks to (start, end) ranges
    // Union with YAMNet segments
    // Split at boundaries, apply padding
    // Return merged AudioChunk array
}
```

- YAMNet segments: precise speech boundaries but may be long
- RMS chunks: shorter, may miss quiet speech
- Union → best of both worlds
- Guard: max chunk duration ~30s (Whisper limit)

### 6. Retry Logic in Transcriber

```swift
func transcribe(chunks: [AudioChunk]) async throws -> [TranscriptionSegment] {
    var allSegments: [TranscriptionSegment] = []
    
    for chunk in chunks {
        var currentChunk = chunk
        var attempt = 0
        var segments: [TranscriptionSegment] = []
        
        while attempt <= maxRetries {
            segments = try await pipe.transcribe(audioArray: currentChunk.samples, ...)
            
            let qualityResults = segments.map { QualityChecker.check($0) }
            let allPass = qualityResults.allSatisfy { $0.pass }
            
            if allPass || attempt == maxRetries {
                // Shift timestamps by currentChunk.offsetSeconds
                allSegments.append(contentsOf: segments)
                break
            }
            
            // Modify audio and retry
            let modifiedWAV = try await AudioModifier.modifyForRetry(
                inputWAV: chunkWAVPath,
                outputWAV: tempDir.path("retry_\(attempt).wav"),
                gainDB: retryGainDB,
                tempo: retryTempo
            )
            currentChunk = try AudioProcessor.loadAudioAsFloatArray(fromPath: modifiedWAV.path)
            attempt += 1
        }
    }
    return allSegments
}
```

---

## Implementation Plan (High-Level)

1. **Add YAMNet Core ML model** — download/convert `yamnet.tflite` → `yamnet.mlmodel`; bundle in repo or download on first use
2. **Create `YAMNetDetector.swift`** — Core ML inference, sliding window, segment merging
3. **Create `QualityChecker.swift`** — thresholds, evaluation logic
4. **Create `AudioModifier.swift`** — ffmpeg wrapper
4. **Update `SilenceDetector.swift`** — add `mergeWithYAMNet(segments:)` method
5. **Update `Transcriber.swift`** — integrate quality check + retry loop
6. **Update `Entry.swift`** — add CLI flags, wire pipeline
7. **Add tests** — `QualityCheckerTests.swift`, `YAMNetDetectorTests.swift` (mock model)
8. **Verify** — `swift test`, manual test on Serbian video

---

## Risks & Mitigations

| Risk | Mitigation |
|------|------------|
| Core ML model not available on user machine | Bundle in repo (`Resources/yamnet.mlmodel`); copy to `~/.yt-subtitles/models/` on first run |
| YAMNet inference slow on CPU | Model is ~5MB, ~0.98s/window; 1hr audio = ~3700 windows ≈ 10-15s on Apple Silicon |
| ffmpeg tempo/gain changes sample rate | Use `-ar 16000` explicitly; verify output format |
| Retry loop infinite on persistent failure | Hard cap `maxRetries` (default 1); log failures clearly |
| YAMNet misses speech RMS catches | Union merge preserves both; no regression |

---

## Acceptance Criteria

1. `--yamnet` flag enables YAMNet speech detection (default ON)
2. `--no-yamnet` falls back to RMS-only (current behavior)
3. Low-quality segments (per thresholds) retry once with +6dB / 0.85x tempo
4. Retry count limited by `--max-retries` (default 1)
5. All existing tests pass (`swift test`)
6. Manual test: Serbian video with quiet speech → more segments detected, fewer artefacts

---

## File Structure After Implementation

```
Sources/yt-subtitles/Core/
  YAMNetDetector.swift      ← NEW
  QualityChecker.swift      ← NEW
  AudioModifier.swift       ← NEW
  SilenceDetector.swift     ← MODIFIED (merge method)
  Transcriber.swift         ← MODIFIED (retry loop)
  AudioExtractor.swift      ← UNCHANGED
  ...
Entry.swift                 ← MODIFIED (flags + pipeline)
Tests/
  QualityCheckerTests.swift ← NEW
  YAMNetDetectorTests.swift ← NEW (mock)
```