<p align="center">
  <img height="180" width="180" src="Nuage/Assets.xcassets/AppIcon.appiconset/icon-512@2x.png" alt="Nuage Icon" />
</p>

<h1 align="center">SoundCloud (Nuage Fork)</h1>

<p align="center">
  A modern, native SoundCloud client for macOS built with SwiftUI. Enhanced with an infinite "My Wave" recommendation engine, Genius lyrics with translations, on-device voice control, and Discord Rich Presence.
</p>

<p align="center">
  <img src="https://img.shields.io/badge/platform-macOS%2013%2B-blue.svg" alt="Platform: macOS 13+" />
  <img src="https://img.shields.io/badge/language-Swift%205.9-orange.svg" alt="Swift 5.9" />
  <img src="https://img.shields.io/badge/UI-SwiftUI-red.svg" alt="SwiftUI" />
  <img src="https://img.shields.io/badge/license-GPL--3.0-green.svg" alt="License: GPL-3.0" />
</p>

---

## About

This project is an advanced, feature-rich fork of **[Nuage](README.original)** — an independent native SoundCloud player for macOS written in SwiftUI.

While the original Nuage provided a lightweight playback foundation, this fork turns it into a full-featured desktop experience by introducing smart continuous recommendations, interactive lyrics, on-device voice assistance, direct messaging, captcha-resilient authentication, and complete bilingual localization.

---

## What's New in This Fork

### 1. My Wave (Personal Endless Stream)
* **Algorithmic Infinite Music Stream**: Automatically builds an evolving queue of tracks based on your liked songs, favorite artists, and related recommendations.
* **Seamless Background Prefetching**: New tracks are queued smoothly while you listen, guaranteeing uninterrupted playback.
* **Instant Stream Regeneration**: One-click refresh button to re-seed the algorithm and get a fresh music mix on demand.
* **Inspirational Artist Badges**: Shows which artists in your library inspired the current stream.

### 2. Lyrics & Fullscreen Now Playing (Genius Integration)
* **Real-Time Genius Synchronization**: Automatically searches and fetches synced song lyrics for currently playing tracks.
* **Multi-Language Translations**: Easily switch between original lyrics and translated versions directly from Genius.
* **Immersive Fullscreen View**:
  * Dynamic ambient background gradient that adapts to album artwork.
  * Synchronized, large-typography lyric view.
  * **Poster Mode**: Clean artwork layout tailored for screenshots and lyric sharing.

### 3. On-Device Voice Control
* **100% Local Speech Recognition**: Powered by Apple's `SFSpeechRecognizer` directly on your Mac — no external voice APIs, completely private.
* **Bilingual Support**: Full support for both Russian and English speech commands.
* **Custom Wake Word**: Hands-free mode with configurable assistant name (default: `Sound`) or direct command mode.
* **Microphone Selector**: Choose built-in or USB mics to prevent Bluetooth headphones (like AirPods) from dropping into low-quality mono headset profile.
* **Interactive Heads-Up Display (HUD)**: Sleek capsule feedback above the player displaying executed commands and status.
* **Over 20 Voice Commands**:
  * Playback: *next, previous, pause, play, volume up, volume down, mute, shuffle, repeat*.
  * Discovery: *my wave, refresh wave, play likes, play reposts*.
  * Social: *like, dislike, repost, remove repost, comment [text], send to [friend]*.
  * Search: *find [track name]*.

### 4. Direct Messages, Sharing & Voice Aliases
* **Integrated Conversations**: View direct messages and chat history without leaving the app.
* **Quick Sharing**: Share tracks, playlists, or albums directly to friends with custom notes.
* **Voice Aliases with Grammar Support**: Assign voice nicknames to friends with grammatical declension handling (*"send to Alex"*, *"share with Denis"*).

### 5. DataDome Bypass & Instant Token Login
* **WebKit Captcha Solver**: Automatic background WebKit interceptor for DataDome anti-bot challenges on likes, reposts, and follows.
* **Token/Cookie Login Mode**: Direct sign-in using `oauth_token`, `datadome`, and `_soundcloud_session` cookies, providing instant access even if embedded web views are blocked.

### 6. Discord Rich Presence (RPC)
* Real-time status broadcasting to Discord showing the current track title, artist name, cover art, elapsed playback time, and duration.

### 7. Full Localization & UI Polish
* **Complete English & Russian Parity**: Every single UI string, menu item, context menu, and tooltip is fully localized.
* **Runtime Language Switcher**: Switch between English and Russian on the fly from the menu bar.
* **Modernized Audio Scrubbing**: Custom progress bar featuring comment timestamps and clickable markers.
* **Touch Bar & AppKit Menus**: Native macOS integration with media keys and shortcuts.

---

## Requirements

* **macOS 13.0 (Ventura)** or later.
* **Xcode 15.0+** (Swift 5.9+).
* A SoundCloud account (Free or Go+).

---

## Building from Source

1. Clone the repository:
   ```bash
   git clone https://github.com/your-username/nuage_fork.git
   cd nuage_fork
   ```

2. Open the Xcode project:
   ```bash
   open Nuage.xcodeproj
   ```

3. Select the **Nuage** scheme and build (`Cmd + B`) or run (`Cmd + R`), or build via command line:
   ```bash
   xcodebuild -scheme Nuage -configuration Release build
   ```

---

## Credits & Acknowledgements

* **[Laurin Brandner](https://twitter.com/lbrndnr)** — Creator of the original Nuage project.
* Open-source contributors to the **[SoundCloud API](https://github.com/lerboe/soundcloud)** framework.

---

## License

This project is licensed under **GPL-3.0**. See [LICENSE](LICENSE) and [README.original](README.original) for more details.
