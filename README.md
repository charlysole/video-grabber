# Video Grabber

A native macOS video downloader built with SwiftUI. Paste any URL, pick your settings, and download — powered by yt-dlp and ffmpeg under the hood.

![Platform](https://img.shields.io/badge/platform-macOS%2013%2B-blue)
![Swift](https://img.shields.io/badge/Swift-5.9-orange)
![License](https://img.shields.io/badge/license-MIT-green)
![Notarized](https://img.shields.io/badge/notarized-yes-brightgreen)

---

## Download

**[→ Download latest release](../../releases/latest)**

Requires macOS 13 Ventura or later.

---

## Features

### Downloading
- **Multi-URL queue** — add multiple URLs, each with its own settings
- **Concurrent downloads** — configurable simultaneous download limit
- **1000+ supported sites** — YouTube, Instagram, TikTok, Vimeo, X/Twitter, Facebook, M3U8 streams, and [many more](https://github.com/yt-dlp/yt-dlp/blob/master/supportedsites.md)
- **Playlist support** — detects playlists and lets you pick which entries to download
- **Format & quality picker** — browse available formats and resolutions before downloading
- **Audio extraction** — download as MP3 directly
- **Subtitle download** — fetch automatic subtitles (English/Spanish)
- **Scheduled downloads** — set a future date and time for any job

### Per-URL Settings
- **Video trim** — set start and end time (H:MM:SS)
- **Format conversion** — convert to MP4, MOV, MKV, or AVI after download
- **Compress to target size** — two-pass ffmpeg encoding to hit a specific MB target
- **Integrity verification** — verify the file after download

### Queue Management
- **Pause / Resume** — suspend and continue individual jobs
- **Cancel / Re-run** — stop or restart any job
- **Clear finished** — clean up the queue in one click

### History
- **Persistent history** — all completed downloads saved across launches
- **Search & filter** — by URL, filename, or status
- **Export** — save history as CSV or JSON

### System Integration
- **macOS Service** — right-click any URL in Safari or any app → "Download with Video Grabber"
- **Quick Look** — preview downloaded files without opening Finder
- **Desktop notifications** — get notified when downloads finish or fail
- **Dock badge** — shows active download count

---

## Installation

1. Download the `.dmg` from the [Releases](../../releases/latest) page
2. Open the `.dmg` and drag **Video Grabber.app** to your Applications folder
3. Open the app — on first launch it will guide you through installing yt-dlp and ffmpeg via Homebrew

> The app is notarized by Apple, so it opens without any security warnings.

### Dependencies (installed automatically on first launch)

| Tool | Purpose |
|------|---------|
| [yt-dlp](https://github.com/yt-dlp/yt-dlp) | Video downloading from 1000+ sites |
| [ffmpeg](https://ffmpeg.org) | Compression, trimming, format conversion |
| [Homebrew](https://brew.sh) | Package manager (required to install the above) |

---

## Localization

- English (default)
- Spanish — applied automatically when macOS is set to Spanish

---

## How It Works

Video Grabber is a native SwiftUI wrapper around `yt-dlp` and `ffmpeg`:

1. Manages download jobs as a queue with configurable concurrency
2. Spawns `yt-dlp` subprocesses and streams output in real time
3. Parses progress, speed, ETA, and filenames from stdout
4. Chains `ffmpeg` for post-processing (compression, trimming, conversion)
5. Stores history locally using `UserDefaults`

---

## Support

If you find Video Grabber useful, consider [making a donation](https://www.paypal.com/donate?business=G8KQK7TRUJLJ6&no_recurring=0&item_name=Support+Video+Grabber+to+keep+a+simple%2C+powerful+macOS+video+tool+growing+and+improving+for+everyone.&currency_code=USD) to support development.

---

## License

MIT — see [LICENSE](LICENSE) for details.
