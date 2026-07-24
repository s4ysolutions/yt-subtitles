# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Current State
Swift CLI for YouTube subtitle generation. Full pipeline working end-to-end: YouTube URL or local video → transcribe → mux subtitled mp4. 28 unit tests pass.

Recent work: unified mp4 pipeline (yt-dlp `--merge-output-format mp4`); `--local-video` (any ffmpeg format, identical pipeline to YouTube minus download); `--no-mux`/`--srt`/`--vtt` flags replace old `--subtitle-only`/`--format`; `--model` aliases (tiny/base/small/large); auto-transliteration by lang (sr→cyr, hr→lat); output naming preserves source — model name suffix differentiates output from input (default: .small); YouTube source video saved to CWD (persistent, re-used on subsequent runs to try different models).

## Build & Test Commands
```bash
swift build -c release                          # Release build
rm -rf .build/release && swift build -c release # Clean release (use if binary stale)
swift test                                       # 28 unit tests
swift test --filter <TestName>                   # Single test
```

## Usage & Output Naming
See README.md. Key implementation detail: `--srt`/`--vtt` are additive (produce files AND mux unless `--no-mux`). `--no-mux` or audio-only input disables mux entirely.

## Language & Tooling
- Swift only. SPM only. macOS 14+.
- Dependencies: `WhisperKit` (argmaxinc/argmax-oss-swift), `swift-argument-parser` (apple/swift-argument-parser).
- External: `yt-dlp` and `ffmpeg` on PATH (brew install). Checked at startup.

## Code Style
- `async/await`, `throws` over optionals, no force-unwraps outside tests.
- User-facing output to stdout, progress/diagnostics to stderr (`[yt-subtitles]` prefix).
- `info()` always shown, `debug()` only with `--verbose`.

## Project Structure
```
Sources/yt-subtitles/
  Entry.swift                    — @main AsyncParsableCommand, all CLI args + pipeline orchestration
  Core/
    AudioExtractor.swift         — yt-dlp download + ffmpeg WAV conversion (YouTube + local)
    SilenceDetector.swift        — RMS-based silence detection, chunk splitting
    Transcriber.swift            — WhisperKit wrapper, model download/load, per-chunk transcription
    SubtitleWriter.swift         — SRT/VTT formatter (500ms padding, midpoint overlap)
    Muxer.swift                  — ffmpeg video+subtitle muxing (muxLocal only)
    Transliterator.swift         — Serbian Latin↔Cyrillic, digraph-aware
    ArtefactCleaner.swift        — filter known Whisper hallucination phrases
  Utilities/
    ProcessRunner.swift          — async Process() via withCheckedContinuation + DispatchQueue
    TempFileManager.swift        — temporary file lifecycle with defer cleanup
Tests/yt-subtitlesTests/
  TransliteratorTests.swift      — 17 tests
  SubtitleWriterTests.swift      — 11 tests
```

## Pipeline
1. YouTube + mp4: `AudioExtractor.downloadVideo()` → yt-dlp `--merge-output-format mp4` saved to CWD as `{title}.mp4`; skip if already exists. YouTube + subtitle-only: audio-only download to tempDir.
2. `--local-video`: use file directly, no download. `--local-audio`: audio file, implies subtitle-only.
3. ffmpeg → 16kHz mono WAV in tempDir (from downloaded video, local video, or local audio)
4. Chunking: RMS-based accumulation. Speech regions detected by RMS energy, accumulated into chunks up to 9s. When limit reached, cut at silence boundary — backward first (most recent silence midpoint), forward fallback if backward would produce <2s chunk. Audio fed to Whisper padded 0.45s outward for context; subtitle boundaries unchanged.
5. Guard: if chunks empty → print message + return. If --lang not set: auto-detect from mid-audio chunk (1/3 through)
6. WhisperKit transcribe each chunk, drop segments whose midpoint falls outside the chunk's keep-window (overlap dedup), shift timestamps by chunk offset, report wall time + realtime speed
7. Auto-transliterate: sr→cyr, hr→lat unless `--translit` explicitly set. `--translit off` disables.
8. If `--srt` (or `--no-mux` with no `--vtt` chosen): write SRT to CWD as `{base}{modelSuffix}.srt`
9. If `--vtt`: write VTT to CWD as `{base}{modelSuffix}.vtt`
10. If mp4 output (not `--no-mux`, not audio-only): write SRT to tempDir (intermediate), `Muxer.muxLocal()` → `{base}{modelSuffix}.mp4`. Steps 8-9 may also run alongside this.

## CLI Flags
Full option list in README.md. Non-obvious implementation details:
- `--model` aliases resolved in `Entry.resolveModelAlias()`: tiny→`openai_whisper-tiny`, base→`openai_whisper-base`, small→`openai_whisper-small`, large→`openai_whisper-large-v3-v20240930`
- `--translit auto`: sr→cyr, hr→lat; explicit `--translit off/lat/cyr` overrides
- `--clean-model` (no `--model`): lists local cache; with `--model <name>`: confirm-delete
- `--list-models`: queries HuggingFace (network); `--clean-model`: local cache only

## Model Cache
`downloadBase` = `~/.yt-subtitles/models/`; WhisperKit appends `models/<repo>/` internally. Full structure:
```
~/.yt-subtitles/models/models/
  argmaxinc/whisperkit-coreml/
    <model-name>/          ← main model (hundreds MB–GB)
    .cache/huggingface/download/<model-name>/   ← download metadata (tiny)
  openai/
    whisper-<base>/        ← tokenizer files ~2.7MB each
                             shared across variants:
                             openai_whisper-large-v3-v20240930 → openai/whisper-large-v3
```
`--clean-model --model <name>` deletes all three layers. `resolveOpenaiDir()` in Entry.swift maps variant→base by progressively stripping trailing name components until a dir match is found; skips openai/ delete if another installed model still references the same dir.

Download progress: dots spinner (one dot/sec) shown only while downloading; disappears for cached models. "Querying recommended model..." logged only with `--verbose`.

## ProcessRunner Notes
- Uses `withCheckedThrowingContinuation` + `DispatchQueue.global()` to avoid blocking Swift concurrency pool.
- Pipes read concurrently via `DispatchGroup` to prevent buffer deadlock.
- `standardInput = FileHandle.nullDevice` to prevent ffmpeg/yt-dlp from blocking on stdin.

## Error Handling
- Missing yt-dlp/ffmpeg: exit with brew install message.
- External process non-zero exit: surface stderr in error.
- Model download/load failure: surface WhisperKit error.

## Testing
- Transliterator (17 tests): Latin↔Cyrillic, digraph cases, round-trip, punctuation.
- SubtitleWriter (11 tests): timestamp formatting, padding, overlap resolution, SRT/VTT output.
- Integration tests: gated behind `YT_SUBTITLES_INTEGRATION_TESTS=1`.
