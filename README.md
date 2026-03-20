# Video Grabber

A native macOS video downloader built with SwiftUI. Supports hundreds of platforms through yt-dlp, with built-in video processing via ffmpeg — all from a clean, native interface.

## Features

### Downloading
- **Multi-URL queue** — add URLs one by one with the + button; each gets its own settings
- **Concurrent downloads** — configurable simultaneous download limit
- **Platform presets** — auto-detects YouTube, Instagram, Vimeo, Facebook, X/Twitter, Frame.io, M3U8 streams, and more
- **Playlist support** — detects playlists and lets you pick which entries to download
- **Format & quality picker** — browse available formats and resolutions before downloading
- **Audio extraction** — download as MP3 directly
- **Subtitle download** — fetch automatic subtitles (English/Spanish)
- **Scheduled downloads** — set a future date and time for any job

### Per-URL Settings (via ⚙️ popover)
- **Video trim** — set start and end time with H:MM:SS fields
- **Format conversion** — convert to MP4, MOV, MKV, AVI after download
- **Compress to target size** — two-pass ffmpeg encoding to hit a specific MB target
- **Subtitle download** — per-URL toggle
- **Integrity verification** — verify the file after download

### Queue Management
- **Pause / Resume** — suspend and continue individual jobs
- **Cancel** — stop any running download
- **Re-run** — restart a completed or failed job
- **Clear finished** — clean up the queue in one click

### History
- **Persistent history** — all completed downloads saved across launches
- **Selectable cells** — right-click any field to copy (URL, filename, status, etc.)
- **Filter** — search by URL, filename, or status
- **Export** — save history as CSV or JSON
- **Clear history** — wipe all records

### System Integration
- **macOS Service** — right-click any URL in Safari or any app and choose "Download with Video Grabber"
- **Quick Look** — preview downloaded files in-app without opening Finder
- **Desktop notifications** — get notified when downloads finish or fail
- **Dock badge** — shows active download count

---

## Requirements

- macOS 13 Ventura or later
- [Homebrew](https://brew.sh) (for installing dependencies)

### Dependencies (installed automatically)
| Tool | Purpose |
|------|---------|
| [yt-dlp](https://github.com/yt-dlp/yt-dlp) | Video downloading from 1000+ sites |
| [ffmpeg](https://ffmpeg.org) | Compression, trimming, format conversion |

On first launch, Video Grabber will guide you through installing missing dependencies via Homebrew.

---

## Supported Platforms

Any site supported by yt-dlp works, including:

- YouTube (videos, playlists, Shorts)
- Instagram (Reels, public posts)
- Facebook (public videos)
- Vimeo
- X / Twitter
- TikTok
- M3U8 / HLS streams
- Frame.io direct links
- And [1000+ more](https://github.com/yt-dlp/yt-dlp/blob/master/supportedsites.md)

---

## Installation

1. Download the latest release from the [Releases](../../releases) page
2. Move `Video Grabber.app` to your Applications folder
3. Open it — on first launch, follow the setup wizard to install yt-dlp and ffmpeg

> **Note:** macOS may show a security warning on first open. Go to **System Settings → Privacy & Security** and click "Open Anyway".

---

## Localization

The interface is available in:
- **English** (default)
- **Spanish** — automatically applied when macOS is set to Spanish

---

## How It Works

Video Grabber is a native SwiftUI wrapper around `yt-dlp` and `ffmpeg`. It:

1. Manages download jobs as a queue with a configurable concurrency limit
2. Spawns `yt-dlp` subprocesses and streams their output in real time
3. Parses progress, speed, ETA, and filenames from yt-dlp's stdout
4. Chains `ffmpeg` post-processing for compression, trimming, and format conversion
5. Stores history locally using `UserDefaults`

---

## License

This software is proprietary.  
You may not copy, modify, or redistribute it without permission.
If you find it useful, you can support the project via [donations](https://www.paypal.com/donate?business=G8KQK7TRUJLJ6&no_recurring=0&item_name=Support+Video+Grabber+to+keep+a+simple%2C+powerful+macOS+video+tool+growing+and+improving+for+everyone.&currency_code=USD
)
