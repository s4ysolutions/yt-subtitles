---
name: transcribe-youtube
description: Use when transcribing YouTube videos to subtitles with yt-subtitles CLI tool. Triggers on "transcribe youtube", "add subtitles to video", "generate captions for youtube".
---

# Transcribe YouTube Videos

## Quick Reference

| Parameter | Flag | Default | Options |
|-----------|------|---------|---------|
| Language | `--lang` | auto-detect | `en`, `sr`, `hr`, `de`, `fr`, etc. |
| Model | `--model` | `small` | `tiny`, `base`, `small`, `large` |
| Output | `--no-mux` | muxed mp4 | `--srt`, `--vtt`, `--no-mux` |
| Quality | `--show-text` | ellipsed | full text preview |

## Basic Usage

```bash
# Auto-detect language, small model (default)
./yt-subtitles <youtube-url>

# Specify language and model
./yt-subtitles --lang en --model large <youtube-url>

# Subtitle files only (no video muxing)
./yt-subtitles --lang sr --no-mux <youtube-url>
```

## Model Selection

| Model | Speed | Accuracy | Use Case |
|-------|-------|----------|----------|
| `tiny` | Fastest | Lower | Quick preview |
| `base` | Fast | Good | Balanced |
| `small` | Medium | Better | Default choice |
| `large` | Slow | Best | High quality needed |

## Common Examples

```bash
# English subtitles, large model
./yt-subtitles --lang en --model large https://youtube.com/watch?v=...

# Serbian with Cyrillic output
./yt-subtitles --lang sr https://youtube.com/watch?v=...

# Just SRT file, no video
./yt-subtitles --lang de --no-mux --srt https://youtube.com/watch?v=...
```

## Output Files

- **Default:** `{title}.mp4` (video + subtitles muxed)
- **`--srt`:** `{title}.srt` (subtitle file)
- **`--vtt`:** `{title}.vtt` (WebVTT format)
- **`--no-mux`:** subtitle files only

## Tips

- First run downloads model (~1-2GB for large)
- YouTube videos saved to CWD, re-used on subsequent runs
- Use `--show-text` to see transcribed text during processing
- Use `--verbose` for detailed progress info
