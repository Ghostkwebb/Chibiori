<div align="center">

  <img src="Chibiori_Logo.jpg" alt="Chibiori Logo" width="160" height="160" style="border-radius: 32px;" />

  # Chibiori (千織)

  **The Native, Offline-First Anime Tracker & Schedule Manager for macOS**

  [![Swift](https://img.shields.io/badge/Swift-5.10%20%7C%206.0-orange.svg?style=flat-square)](https://developer.apple.com/swift/)
  [![Platform](https://img.shields.io/badge/Platform-macOS%2014.0%2B%20(Sonoma%20%2F%20Sequoia)-lightgrey.svg?style=flat-square)](https://www.apple.com/macos/)
  [![Architecture](https://img.shields.io/badge/Architecture-Apple%20Silicon%20%26%20Intel-blue.svg?style=flat-square)](https://www.apple.com/mac/)
  [![License](https://img.shields.io/badge/License-MIT-green.svg?style=flat-square)](LICENSE)
  [![Release](https://img.shields.io/github/v/release/Ghostkwebb/Chibiori?style=flat-square)](https://github.com/Ghostkwebb/Chibiori/releases/latest)

  <p>
    <b>Chibiori</b> is a lightweight, high-performance desktop anime manager designed natively for macOS.
    <br>
    Built with <b>SwiftUI</b>, <b>SwiftData</b>, and <b>CoreAnimation</b> for fluid 120Hz ProMotion scrolling, zero cloud lock-in, and instant offline access.
  </p>

  <a href="https://github.com/Ghostkwebb/Chibiori/releases/latest/download/Chibiori.zip">
    <img src="https://img.shields.io/badge/Download-Chibiori.app-blue?style=for-the-badge&logo=apple&logoColor=white" alt="Download Chibiori" />
  </a>

</div>

<br />

> [!IMPORTANT]
> **System Requirements**: Requires a Mac running **macOS 14.0 (Sonoma)** or newer. Chibiori is a native universal binary supporting both **Apple Silicon (M1/M2/M3/M4)** and **Intel** Macs.

---

## Highlights

*   **Fluid Glassmorphic UI**: Detached floating sidebar, specular glass borders, vibrant status pills, and adaptive dark mode tailored for macOS.
*   **120Hz ProMotion Performance**: Multi-threaded CoreAnimation compositor rendering (`drawsAsynchronously`), zero-allocation viewport reuse, and instant keyboard grid navigation.
*   **Multilingual Title Preferences**: Switch seamlessly between English, Romaji, and Native Japanese/Chinese titles across your entire collection, with custom title overrides for any anime.
*   **Offline-First SwiftData Engine**: All watch status records, personal ratings, custom notes, and poster artwork are saved locally on disk with zero telemetry or account requirements.
*   **High-Speed Metadata Hydration**: Batch-fetches missing cover art, scores, synopses, and genres using concurrent AniList GraphQL queries (up to 50 titles per 100ms request).
*   **Sequel & Announcement Detection**: Scans your completed anime list to automatically notify you when new seasons, movies, or sequels are officially announced.
*   **Weekly Airing Schedule**: Displays currently airing anime organized by broadcast day with live countdown timers and release badges.
*   **MyAnimeList (MAL) & JSON Vault**: Direct import from MAL XML backup files with status filtering, plus comprehensive JSON backup and private iCloud Drive synchronization.
*   **In-App Auto-Updates**: One-click check for updates powered directly by GitHub Releases.

---

## Installation

1.  **Download**: Get the latest `Chibiori.zip` from the [Releases Page](https://github.com/Ghostkwebb/Chibiori/releases/latest).
2.  **Unzip**: Double-click `Chibiori.zip` to extract `Chibiori.app`.
3.  **Install**: Drag `Chibiori.app` into your **`/Applications`** folder.
4.  **Open**: Launch the app from Spotlight or Applications.

---

## Core Capabilities

### Multilingual Title System
Chibiori provides granular control over how anime titles appear in your library and search views:
*   **English**: Prioritizes official localized English titles (with intelligent English synonym resolution for Chinese Donghua where standard API fields are empty).
*   **Romaji**: Standard romanized transliteration (e.g. *Sousou no Frieren*, *Guimi Zhi Zhu*).
*   **Native**: Original script (e.g. *葬送のフリーレン*, *诡秘之主*).
*   **Custom Overrides**: Set a custom name for any title directly in the Inspector panel.

### High-Performance Poster Grid & Table Views
*   **Poster Grid**: Interactive poster gallery with air status badges, score pills, and real-time hover elevation.
*   **Compact Table**: High-density data grid featuring status picker menus, progress counters, and sortable columns.
*   **Full Keyboard Traversal**: Navigate your grid with `Arrow Keys`, inspect with `Enter`, increment episodes with `Spacebar`, and re-queue items with `Cmd + Backspace`.

### Private iCloud Sync & Backup Vault
*   **iCloud Vault**: Automatically mirrors your library database to your personal iCloud Drive container (`Chibiori_AutoVault.json`) across your Mac devices.
*   **Universal JSON Export**: Full round-trip JSON serialization conforming to the Chibiori Backup Specification.
*   **MAL XML Importer**: Easily migrate an existing anime list from MyAnimeList with selectable import modes (*Completed Only, Watching Only, Plan to Watch, All*).

---

## Keyboard Shortcuts

| Shortcut | Action |
| :--- | :--- |
| `↑` `↓` `←` `→` | Navigate anime cards in Poster Grid |
| `Return` / `Enter` | Select anime and open Inspector |
| `Space` | Increment current episode progress (+1) |
| `⌘` + `Backspace` | Re-queue anime to top of Plan to Watch |
| `⌘` + `1` | Switch to Poster Grid view |
| `⌘` + `2` | Switch to Compact Table view |
| `⌘` + `⌥` + `I` | Toggle Inspector panel |
| `⌘` + `⇧` + `F` | Jump to Discover / Search tab |
| `⌘` + `⇧` + `K` | Jump to Weekly Airing Calendar |

---

## Tech Stack

*   **Language**: Swift 5.10 / Swift 6.0
*   **UI Framework**: SwiftUI (macOS 14+ SDK) & AppKit Window Management
*   **Data Persistence**: SwiftData (`@Model`, `ModelContainer`, `ModelContext`)
*   **Image Pipeline**: CoreGraphics hardware thumbnail decoding and disk caching
*   **Network & APIs**:
    *   AniList GraphQL API (Batch Hydration & Sequel Discovery)
    *   Jikan REST API v4 (MyAnimeList Gateway & Weekly Schedules)
*   **Cloud Storage**: Apple CloudKit & Private iCloud Drive Documents

---

## Building from Source

### Prerequisites
*   macOS 14.0 (Sonoma) or newer
*   Xcode 15.0+ or Xcode Command Line Tools (`xcode-select --install`)

### Compile and Package `.app` Bundle
```bash
git clone https://github.com/Ghostkwebb/Chibiori.git
cd Chibiori
./scripts/build_app.sh
```
The compiled, signed application bundle will be created at `./Chibiori.app`.

### Run Automated Smoke Test Suite
```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift run Chibiori --smoke-test
```

---

## Credits

*   **AniList API**: Community anime metadata, cover art, and relationship graph.
*   **Jikan API**: Open-source REST API for MyAnimeList data.
*   **Apple SF Symbols**: System iconography and UI glyphs.

---

<div align="center">
  <p>Crafted natively for macOS</p>
</div>
