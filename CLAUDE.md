# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Current State
Swift CLI for YouTube subtitle generation. Full pipeline working end-to-end: YouTube URL or local video → transcribe → mux subtitled mp4. 28 unit tests pass.

Recent work: unified mp4 pipeline (yt-dlp `--merge-output-format mp4`); `--local-video` (any ffmpeg format, identical pipeline to YouTube minus download); `--no-mux`/`--srt`/`--vtt` flags replace old `--subtitle-only`/`--format`; `--model` aliases (tiny/base/small/large); auto-transliteration by lang (sr→cyr, hr→lat); output naming preserves source — model name or `.subtitle` suffix differentiates output from input; YouTube source video saved to CWD (persistent, re-used on subsequent runs to try different models).

## Build & Test Commands
```bash
swift build -c release                          # Release build
rm -rf .build/release && swift build -c release # Clean release (use if binary stale)
swift test                                       # 28 unit tests
swift test --filter <TestName>                   # Single test
```

## Usage
```bash
# YouTube → download + transcribe + mux → {title}.tiny.mp4 (source kept as {title}.mp4)
yt-subtitles "https://youtube.com/..." --lang sr --model tiny

# Re-run with different model — skips download, uses cached {title}.mp4
yt-subtitles "https://youtube.com/..." --lang sr --model small

# Local video — identical pipeline, no download step
yt-subtitles --local-video video.mp4 --lang sr --model tiny  # → video.tiny.mp4
yt-subtitles --local-video video.mp4 --lang sr               # → video.subtitle.mp4

# --srt/--vtt are additive: produce subtitle files AND mux (unless --no-mux)
yt-subtitles "https://youtube.com/..." --srt                  # → {title}.subtitle.mp4 + {title}.subtitle.srt
yt-subtitles "https://youtube.com/..." --srt --vtt            # → {title}.subtitle.mp4 + .srt + .vtt

# Subtitle files only, no remux (requires --no-mux)
yt-subtitles "https://youtube.com/..." --no-mux               # → {title}.subtitle.srt (default SRT)
yt-subtitles "https://youtube.com/..." --no-mux --srt --vtt   # → {title}.subtitle.srt + .vtt
yt-subtitles --local-audio audio.wav --lang sr                # → audio.subtitle.srt (audio-only, always no mux)

yt-subtitles --list-models                                    # list available Whisper models
```

## Output Naming
Source file is never modified. Output gets model name or `.subtitle` as suffix:
- YouTube `--model tiny` → `{title}.mp4` (source, kept) + `{title}.tiny.mp4` (output)
- YouTube no model   → `{title}.mp4` (source, kept) + `{title}.subtitle.mp4` (output)
- `--local-video f.mp4 --model tiny` → `f.mp4` (untouched) + `f.tiny.mp4`
- `--local-video f.mp4` (no model) → `f.mp4` (untouched) + `f.subtitle.mp4`
- `--output name` → overrides base name entirely, no suffix appended

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
4. SilenceDetector: 100ms RMS windows (tail samples < window classified separately), threshold 0.01, min-silence 1.5s, split at midpoints → [AudioChunk]
5. Guard: if chunks empty → print message + return. If --lang not set: auto-detect from mid-audio chunk (1/3 through)
6. WhisperKit transcribe each chunk, shift timestamps by chunk offset, report wall time + realtime speed
7. Auto-transliterate: sr→cyr, hr→lat unless `--translit` explicitly set. `--translit off` disables.
8. If `--srt` (or `--no-mux` with no `--vtt` chosen): write SRT to CWD as `{base}{modelSuffix}.srt`
9. If `--vtt`: write VTT to CWD as `{base}{modelSuffix}.vtt`
10. If mp4 output (not `--no-mux`, not audio-only): write SRT to tempDir (intermediate), `Muxer.muxLocal()` → `{base}{modelSuffix}.mp4`. Steps 8-9 may also run alongside this.

## CLI Flags
| Flag | Default | Notes |
|---|---|---|
| `<youtube-url>` | — | Optional if --local-audio/--local-video set |
| `--local-audio` | — | Path to local audio file; always subtitle-only (no video) |
| `--local-video` | — | Path to local video file (any ffmpeg format) |
| `--no-mux` | false | Skip video remux; produce subtitle file(s) only (default output: SRT) |
| `--srt` | false | Write SRT subtitle file (additive; combinable with mux or `--no-mux`) |
| `--vtt` | false | Write VTT subtitle file (additive; combinable with mux or `--no-mux`) |
| `--model` | auto | tiny, base, small, large, full name, or glob; omit for recommended |
| `--lang` | auto-detect | Language code (e.g. sr, hr, en); omit to detect from mid-audio |
| `--translit` | auto | off, lat, cyr; auto: sr→cyr, hr→lat |
| `--resolution` | 720p | 144p, 480p, 720p, 1080p |
| `--output` | derived | Override output base name; disables model suffix |
| `--subtitles-lang` | from --lang | Language tag embedded in mp4 subtitle track |
| `--clean-artefacts` | false | Filter known Whisper hallucinations |
| `--silence-threshold` | 0.01 | RMS threshold 0.0–1.0 |
| `--min-silence` | 1.5 | Minimum silence seconds |
| `--list-models` | — | Query HuggingFace, print models, exit |
| `--verbose` | false | Detailed progress |

## Model Cache
Models downloaded to `~/.yt-subtitles/models/`. First run downloads ~800MB + Core ML compiles (1-2 min). Subsequent runs load compiled models from cache (few seconds).

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
