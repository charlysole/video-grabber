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

Whether you want to save a YouTube video in 4K, extract audio from a podcast, grab an Instagram reel, or batch-download an entire playlist — Video Grabber handles it from a single window.

---

## Features

### Download from 1000+ Sites
- **YouTube** — videos, Shorts, playlists, channels (with bot-detection bypass)
- **Instagram** — reels, posts, stories
- **TikTok** — videos and slideshows
- **Vimeo** — public and domain-restricted videos
- **X / Twitter** — video tweets
- **Facebook** — public video posts
- **M3U8 / HLS streams** — live and on-demand streaming URLs
- **…and [1000+ more sites](https://github.com/yt-dlp/yt-dlp/blob/master/supportedsites.md)** via yt-dlp

### In-App Browser
- Full browsing experience without leaving the app
- **Log in to any site** — cookies are automatically captured and used for authenticated downloads
- **Video scanner** — tap 🔍 to scan the current page for embedded videos and add them to the queue instantly
- **M3U8 stream detection** — streams are captured automatically in the background as the page loads; add them to the queue with one tap
- Toggle "Use cookies in downloads" to apply your session to any download

### Download Queue
- Add multiple URLs at once, each with **independent settings**
- Configure concurrent download limit (1–10 simultaneous jobs)
- **Per-row controls**: pause, resume, and stop buttons on every active download row
- **Stop All** — halt every active and queued download at once
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

### Cloud Upload Shortcuts
- One-click access to **iCloud Drive** (opens local folder) and **Google Drive** (opens web)
- Available directly from the destination picker

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

1. Download `VideoGrabber-1.07.dmg` from the [Releases](../../releases/latest) page
2. Open the `.dmg` and drag **Video Grabber.app** to your Applications folder
3. Launch the app
4. **On first launch, tap "Update" in the welcome screen** — this downloads the latest yt-dlp and deno (the JavaScript runtime needed for YouTube). Without this step, YouTube downloads will fail.

> **Apple Notarized** — the app opens without any security warning on macOS 13+.

### Dependencies (managed automatically in-app)

| Tool | Purpose | How to get |
|---|---|---|
| [yt-dlp](https://github.com/yt-dlp/yt-dlp) | Downloads video from 1000+ sites | **Update button in Preferences** |
| [ffmpeg](https://ffmpeg.org) | Trim, convert, and compress video | Bundled with the app |
| [deno](https://deno.com) | JavaScript runtime for YouTube n-challenge | Downloaded automatically with yt-dlp update |

No Terminal or Homebrew required.

---

## What's New in v1.07

### In-App Browser
A full browser tab is now built into the app. Browse to any page, log in with your account, and your session cookies are automatically used for downloads — solving authentication issues on Vimeo, Patreon, educational platforms, and more.

### Video Page Scanner
While in the browser, tap 🔍 to scan the current page for embedded videos. The scanner uses JavaScript DOM inspection plus yt-dlp to detect `<video>` elements, iframe embeds (YouTube, Vimeo, Dailymotion, Twitch…), and data attributes — all deduplicated and titled correctly.

### Automatic M3U8 Stream Capture
The browser intercepts XHR and fetch requests in real time. When a `.m3u8` streaming URL is detected, it appears in a panel below the browser toolbar — tap "Add" to queue it immediately.

### YouTube Bot-Detection Fix
YouTube now requires a JavaScript runtime to solve its "n challenge". Video Grabber automatically downloads [deno](https://deno.com) alongside yt-dlp and passes it to yt-dlp for every YouTube download. No configuration needed.

### yt-dlp One-Click Updater
The bundled yt-dlp can now be updated to the latest version directly from **Preferences → Dependencies** (or from the welcome screen on first launch). The updater fetches the latest `yt-dlp_macos` and `deno` binaries from their official GitHub releases, sets the correct permissions, and removes quarantine automatically.

### Per-Row Download Controls
Every download row now has inline **pause**, **resume**, and **stop** buttons — no need to select a job first. A **Stop All** button in the queue header halts everything at once.

### Improved Error Messages
Errors are now classified more precisely:
- YouTube bot detection (429 / "confirm you're not a bot") → clear instructions to update yt-dlp
- Cookie permission errors → explains which browsers are and aren't supported
- Rate limiting → distinguished from network failures

### Removed
- *Cancel Current* button (replaced by per-row stop + Stop All)
- *Capture M3U8* button (M3U8 capture now happens automatically in the browser)
- *Open HandBrake* button and HandBrake dependency detection
- System browser cookie picker (replaced by in-app browser cookies)

---

## Building from Source

```bash
git clone https://github.com/charlysole/video-grabber.git
cd "video-grabber/Video grabber"
open "Video grabber.xcodeproj"
```

Requires **Xcode 15 or later**. No additional configuration needed — all dependencies are managed at runtime.

---

## How It Works

Video Grabber is a native **SwiftUI / AppKit** app following an MVVM architecture:

1. URLs are staged with per-job configuration and added to a download queue
2. A concurrent job runner spawns `yt-dlp` subprocesses (up to N simultaneous)
3. stdout is streamed line-by-line and parsed for progress, speed, ETA, and filename
4. Post-processing chains `ffmpeg` for trimming, format conversion, and compression
5. The in-app browser (WKWebView) exports cookies in Netscape format for yt-dlp `--cookies`
6. A WKUserScript intercepts XHR/fetch calls to capture M3U8 URLs in real time
7. Completed jobs are written to a persistent JSON history in `~/Library/Application Support/Video Grabber/`

---

## FAQ

**Does it work on Apple Silicon?**
Yes — universal binary, runs natively on both Apple Silicon (arm64) and Intel (x86_64).

**Is it free?**
Yes, completely free and open source under the MIT license. If you find it useful, [donations are appreciated](https://www.paypal.com/donate?business=G8KQK7TRUJLJ6&no_recurring=0&item_name=Support+Video+Grabber+to+keep+a+simple%2C+powerful+macOS+video+tool+growing+and+improving+for+everyone.&currency_code=USD).

**Does it support 4K and 8K?**
Yes — the format picker lists all available resolutions including 4K (2160p) and 8K when offered by the source.

**Can it download private or login-restricted videos?**
Yes — log in via the in-app Browser tab and enable "Use cookies in downloads". Your session is passed directly to yt-dlp.

**YouTube downloads fail with "bot detection" error**
Open **Preferences → Dependencies** and tap **Update** on yt-dlp. This installs the latest version plus deno, which solves the YouTube n-challenge automatically.

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
