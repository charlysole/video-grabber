# Video Grabber — Native macOS Video Downloader

**Download videos from YouTube, Instagram, TikTok, Vimeo, X/Twitter, Facebook, and 1000+ sites — with a clean, native macOS interface. No Terminal required.**

![Platform](https://img.shields.io/badge/platform-macOS%2013%2B-blue)
![Swift](https://img.shields.io/badge/Swift-5.9-orange)
![License](https://img.shields.io/badge/license-MIT-green)
![Notarized](https://img.shields.io/badge/Apple%20Notarized-yes-brightgreen)
![Release](https://img.shields.io/github/v/release/charlysole/video-grabber)
![Downloads](https://img.shields.io/github/downloads/charlysole/video-grabber/total)

---

## Download

**[→ Download latest release (.dmg)](../../releases/latest)**

Requires **macOS 13 Ventura or later** · Apple Silicon & Intel supported

---

## What is Video Grabber?

Video Grabber is a **free, open source, native macOS app** that wraps the power of [yt-dlp](https://github.com/yt-dlp/yt-dlp) and [ffmpeg](https://ffmpeg.org) into a clean SwiftUI interface. It lets you download, convert, trim, and compress videos from over **1000 websites** — all without touching the Terminal.

Whether you want to save a YouTube video in 4K, extract the audio from a podcast, grab an Instagram reel, or batch-download an entire playlist — Video Grabber handles it from a single window.

---

## Features

### Download from 1000+ Sites
- **YouTube** — videos, Shorts, playlists, channels
- **Instagram** — reels, posts, stories
- **TikTok** — videos and slideshows
- **Vimeo** — public and unlisted videos
- **X / Twitter** — video tweets
- **Facebook** — public video posts
- **M3U8 / HLS streams** — live and on-demand streaming URLs
- **Frame.io** — review links
- **…and [1000+ more sites](https://github.com/yt-dlp/yt-dlp/blob/master/supportedsites.md)** via yt-dlp

### Multi-URL Queue
- Add multiple URLs at once, each with **independent settings**
- Configure concurrent download limit (1–10 simultaneous jobs)
- **Pause, resume, cancel, or retry** any job individually
- Clear finished jobs with one click

### Per-URL Settings
| Option | Description |
|---|---|
| **Format & quality picker** | Browse all available resolutions and codecs before downloading |
| **Video trim** | Set start and end time (H:MM:SS) |
| **Format conversion** | Convert to MP4, MOV, MKV, or AVI after download |
| **Audio extraction** | Save as MP3 instead of video |
| **Target file size** | Two-pass ffmpeg compression to hit a specific MB target |
| **Subtitle download** | Fetch automatic subtitles (English / Spanish) |
| **Integrity check** | Verify the downloaded file after completion |
| **Playlist entry picker** | Select specific videos from a playlist |

### Scheduled Downloads
- Set any job to run at a **future date and time**
- Jobs are promoted automatically when the scheduled time arrives

### Download History
- All completed downloads saved **persistently across sessions**
- Filter by status, platform, or date range
- Export history as **CSV or JSON**
- Quick Look preview and Finder reveal from the history list

### Native macOS Integration
- **macOS Service** — right-click any URL in Safari, Chrome, or any app → *Download with Video Grabber*
- **Quick Look** — preview downloaded files without opening Finder
- **Desktop notifications** — notified when downloads complete or fail
- **Dock badge** — live active download count
- **Auto-updater** — checks GitHub Releases on launch and installs updates in one click

### Languages
- English
- Spanish — applied automatically when macOS is set to Spanish

---

## Installation

1. Download `VideoGrabber-x.xx.dmg` from the [Releases](../../releases/latest) page
2. Open the `.dmg` and drag **Video Grabber.app** to your Applications folder
3. Launch the app — on first launch it detects and installs its dependencies automatically

> **Apple Notarized** — the app opens without any security warning on macOS 13+.

### Dependencies (managed automatically)

| Tool | Purpose |
|---|---|
| [yt-dlp](https://github.com/yt-dlp/yt-dlp) | Downloads video from 1000+ sites |
| [ffmpeg](https://ffmpeg.org) | Trim, convert, and compress video |
| [Homebrew](https://brew.sh) | Package manager used for installation |

On first launch, Video Grabber checks if yt-dlp and ffmpeg are present and offers to install them via Homebrew. No manual setup required.

---

## Building from Source

```bash
git clone https://github.com/charlysole/video-grabber.git
cd "video-grabber/Video grabber"
open "Video grabber.xcodeproj"
```

Requires **Xcode 15 or later**. No additional configuration needed — dependencies are managed at runtime, not build time.

---

## How It Works

Video Grabber is a native **SwiftUI / AppKit** app following an MVVM architecture:

1. URLs are staged with per-job configuration and added to a download queue
2. A concurrent job runner spawns `yt-dlp` subprocesses (up to N simultaneous)
3. stdout is streamed line-by-line and parsed for progress, speed, ETA, and filename
4. Post-processing chains `ffmpeg` for trimming, format conversion, and compression
5. Completed jobs are written to a persistent JSON history in `~/Library/Application Support/Video Grabber/`
6. The macOS Service, Quick Look panel, and Dock badge integrate with the system at the AppKit level

---

## FAQ

**Does it work on Apple Silicon?**
Yes — universal binary, runs natively on both Apple Silicon (arm64) and Intel (x86_64).

**Is it free?**
Yes, completely free and open source under the MIT license. If you find it useful, [donations are appreciated](https://www.paypal.com/donate?business=G8KQK7TRUJLJ6&no_recurring=0&item_name=Support+Video+Grabber+to+keep+a+simple%2C+powerful+macOS+video+tool+growing+and+improving+for+everyone.&currency_code=USD).

**Does it support 4K and 8K?**
Yes — the format picker lists all available resolutions including 4K (2160p) and 8K when offered by the source.

**Can it download private videos?**
Only if yt-dlp supports it for that platform (e.g. cookies-based auth). Video Grabber does not add any authentication layer beyond what yt-dlp provides.

**Does it need an internet connection to work?**
Only for downloading. The app itself, the queue, and the history work offline.

---

## Support & Feedback

- **Bug reports / feature requests** → [open an issue](../../issues)
- **Support development** → [Donate via PayPal](https://www.paypal.com/donate?business=G8KQK7TRUJLJ6&no_recurring=0&item_name=Support+Video+Grabber+to+keep+a+simple%2C+powerful+macOS+video+tool+growing+and+improving+for+everyone.&currency_code=USD)

---

## License

MIT — see [LICENSE](LICENSE) for details.

---

*Video Grabber is not affiliated with YouTube, Instagram, TikTok, Meta, X Corp, or any other platform. Always respect the terms of service of the sites you download from and the rights of content creators.*
