# yt-subtitles

macOS CLI — download YouTube videos, transcribe audio with WhisperKit (Core ML), produce SRT subtitles or muxed mp4.

## Prerequisites

```bash
brew install yt-dlp ffmpeg
```

macOS 14+ required (WhisperKit constraint).

## Build

```bash
swift build -c release
```

Binary at `.build/release/yt-subtitles`.

## Install

```bash
cp .build/release/yt-subtitles /usr/local/bin/
```

## Usage

```bash
# YouTube → download + transcribe + mux → {title}.tiny.mp4 (source kept as {title}.mp4)
yt-subtitles "https://youtube.com/..." --lang sr --model tiny

# Re-run with different model — skips download, uses cached {title}.mp4
yt-subtitles "https://youtube.com/..." --lang sr --model small

# Local video — identical pipeline, no download
yt-subtitles --local-video video.mp4 --lang sr --model tiny        # → video.tiny.mp4 (muxed)
yt-subtitles --local-video video.mp4 --lang sr --srt               # → video.subtitle.mp4 + video.subtitle.srt
yt-subtitles --local-video video.mp4 --lang sr --srt --vtt         # → video.subtitle.mp4 + .srt + .vtt

# Subtitle files only, no remux (--no-mux required to skip muxing)
yt-subtitles "https://youtube.com/..." --no-mux                    # → {title}.subtitle.srt (default SRT)
yt-subtitles "https://youtube.com/..." --no-mux --srt              # → {title}.subtitle.srt
yt-subtitles "https://youtube.com/..." --no-mux --vtt              # → {title}.subtitle.vtt
yt-subtitles "https://youtube.com/..." --no-mux --srt --vtt        # → both .srt and .vtt

# Local audio — no video stream, always produces subtitle file
yt-subtitles --local-audio audio.wav --lang sr               # → audio.subtitle.srt
```

## Options

| Option | Default | Description |
|---|---|---|
| `<youtube-url>` | — | YouTube video URL; omit if using `--local-audio` or `--local-video` |
| `--local-audio` | — | Transcribe a local audio file; no video stream, produces subtitle file |
| `--local-video` | — | Transcribe and subtitle a local video (any ffmpeg format) |
| `--no-mux` | false | Skip video remux; produce subtitle file(s) only (default: SRT) |
| `--srt` | false | Also write SRT subtitle file (combinable with mux or `--no-mux`) |
| `--vtt` | false | Also write VTT subtitle file (combinable with mux or `--no-mux`) |
| `--model` | small | Whisper model: `tiny`, `base`, `small`, `large`, full name, or glob |
| `--lang` | auto-detect | Audio language code (e.g. `en`, `sr`); omit to detect from audio |
| `--output` | derived | Override output base path; disables model suffix |
| `--subtitles-lang` | from `--lang` | Language tag embedded in mp4 subtitle track |
| `--translit` | auto | Script conversion: `off`, `lat`, `cyr`; auto: sr→cyr, hr→lat |
| `--resolution` | `720p` | Video resolution: `144p`, `480p`, `720p`, `1080p` |
| `--clean-artefacts` | false | Filter known Whisper hallucination phrases |
| `--rms` | false | Use RMS-based chunking (default) |
| `--yamnet` | false | Use YAMNet speech-detection chunking |
| `--silence-threshold` | `0.01` | RMS threshold for silence detection (0.0–1.0) |
| `--min-silence` | `1.5` | Minimum silence duration in seconds to split on |
| `--model-dir` | `~/.yt-subtitles/models` | Override model cache directory |
| `--list-models` | — | List available Whisper models and exit |
| `--clean-model` | — | List cached models; with `--model <name>`: confirm + delete from cache |
| `--verbose` | false | Detailed progress output |

### YAMNet Speech Detection

| Option | Default | Description |
|---|---|---|
| `--yamnet` / `--no-yamnet` | true | Enable/disable YAMNet speech detection |
| `--yamnet-threshold` | `0.5` | Speech class probability threshold (0.0–1.0) |
| `--yamnet-model` | `~/.yt-subtitles/models/yamnet.mlmodel` | Path to YAMNet Core ML model |

### Quality Retry

| Option | Default | Description |
|---|---|---|
| `--quality-threshold` | `0.45` | Word probability threshold for quality check |
| `--avg-logprob-threshold` | `-0.7` | Segment avgLogprob threshold |
| `--no-speech-prob-threshold` | `0.5` | Segment noSpeechProb threshold |
| `--max-retries` | `1` | Max retry attempts per segment (0 = disabled) |
| `--retry-gain-db` | `6.0` | Gain boost in dB for retry |
| `--retry-tempo` | `0.85` | Tempo factor for retry (0.5–1.0) |

## Audio Chunking Strategy

Two strategies are available, selected by `--rms` (default) or `--yamnet`:

### RMS (default)
Simple silence detection using RMS energy. Speech regions are accumulated into chunks up to 9 seconds. Each chunk's transcribe duration equals its subtitle duration — no overlap, no complex ownership logic.

### YAMNet (`--yamnet`)
Speech detection via RMS-based analysis, then complex tiling:
- 9s windows with 7s stride (2s overlap)
- Audio boundaries extended to nearest silence frame (≤1.5s search)
- Separate "keep windows" for subtitle ownership assignment

## Output Naming

Source file is never modified. Output gets model name suffix (default: `.small`):

| Input | Flag | Output |
|---|---|---|
| YouTube URL | `--model tiny` | `{title}.mp4` (kept) + `{title}.tiny.mp4` |
| YouTube URL | *(no model)* | `{title}.mp4` (kept) + `{title}.small.mp4` |
| `--local-video f.mp4` | `--model tiny` | `f.mp4` (untouched) + `f.tiny.mp4` |
| `--local-video f.mp4` | *(no model)* | `f.mp4` (untouched) + `f.small.mp4` |
| any | `--output name` | `name` (no suffix appended) |

## Model Cache

Models download to `~/.yt-subtitles/models/`. WhisperKit stores them at:
`~/.yt-subtitles/models/models/argmaxinc/whisperkit-coreml/<model-name>/`

First run downloads ~800 MB + Core ML compile (1–2 min). Subsequent runs load compiled models from cache (seconds).

```bash
yt-subtitles --clean-model                   # list cached models with sizes
yt-subtitles --clean-model --model tiny      # confirm + delete openai_whisper-tiny
```

## Run Tests

```bash
swift test
swift test --filter <TestName>              # Single test
YT_SUBTITLES_INTEGRATION_TESTS=1 swift test # Integration tests
```
