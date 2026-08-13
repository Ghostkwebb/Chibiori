# Chibiori (千織) 🌸

> **A modern, local-first anime tracker and discovery browser for macOS built with SwiftUI and SwiftData.**

---

## ✨ Features

- 💎 **Glassmorphic macOS UI**: Detached floating sidebar and inspector panels, specular glass borders, ambient drop shadows, and rich dark mode palette.
- ⚡ **120Hz ProMotion Optimization**: Multi-threaded CoreAnimation compositor rendering (`drawsAsynchronously`), zero-heap allocations during scrolling, and hardware-accelerated Spaces/Mission Control transitions.
- 🎯 **Full Arrow Key Grid Navigation**: Seamless `Up / Down / Left / Right` keyboard navigation across anime cards with automatic scroll-to-visible focusing.
- 🔄 **MyAnimeList (MAL) XML Importer**: Upload MAL XML list exports with instant status filtering (*Completed Only, Watching Only, Plan to Watch, All*).
- 🚀 **Automatic Poster & Metadata Hydration**: High-speed batch queries via AniList GraphQL (`media(idMal_in:)`) capable of fetching cover artwork, scores, synopses, and genres for 50+ anime per single 100ms request.
- 🔔 **Sequel & Season 2 Announcement Tracking**: Automatically scans your completed anime library to detect newly announced upcoming seasons, movies, or sequels with 1-click addition to your watch list.
- 📅 **Weekly Airing Calendar**: Grouped broadcast schedules for currently airing anime by day of the week.
- 💾 **Local-First & Offline Ready**: CoreGraphics hardware thumbnail caching, full JSON backup import/export, and offline poster storage.

---

## 🛠️ Building and Running

### Prerequisites
- macOS 14.0 (Sonoma) or newer
- Xcode 15.0+ or Command Line Tools

### Build Release Application Bundle
```bash
./scripts/build_app.sh
```
The compiled and code-signed application bundle will be output to `Chibiori.app`.

### Run Automated Smoke Tests
```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift run Chibiori --smoke-test
```

---

## 📄 License
Private Repository – All rights reserved.
