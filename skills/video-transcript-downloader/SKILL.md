---
name: video-transcript-downloader
description: Download and clean transcripts from YouTube videos and other platforms using yt-dlp. Outputs clean Markdown suitable for LLM consumption. Use when the operator needs the text content of a video for analysis, summarization, or reference.
---

# video-transcript-downloader — video transcript extraction

Downloads auto-generated or manual subtitles and converts them to clean Markdown.

## When to use

- "この YouTube 動画の文字起こしが欲しい"
- "この動画の内容をテキストにして"
- "transcript をダウンロードして要約したい"

Do **not** use for:
- Downloading audio or video files (use yt-dlp directly)
- Videos with no available subtitles (will fail gracefully)
- Paid/paywalled content

## Extraction steps

```bash
# 1. Check available subtitles
yt-dlp --list-subs "<url>"

# 2. Download preferred subtitles (Japanese first, English fallback)
yt-dlp --write-subs --write-auto-subs --sub-lang "ja,en" \
  --skip-download --convert-subs srt \
  -o "%(title)s.%(ext)s" "<url>"

# 3. Convert SRT to clean Markdown (strip timestamps)
python3 - <<'EOF'
import re, sys
srt = open(sys.argv[1]).read()
lines = re.sub(r'\d+\n\d{2}:\d{2}:\d{2},\d{3} --> \d{2}:\d{2}:\d{2},\d{3}\n', '', srt)
lines = re.sub(r'\n{3,}', '\n\n', lines).strip()
print(lines)
EOF transcript.srt > transcript.md
```

## Output

Clean Markdown file at `~/work/docs/transcripts/<video-title>.md` or operator-specified path.

## Hard-rule reminders

- Only download from publicly accessible URLs.
- Check license/terms before using transcript content commercially.
- yt-dlp must be installed: `brew install yt-dlp`.
