# Fetchora

A powerful Safari Download Manager for macOS built with Swift, SwiftUI, and SwiftData.

## Features

- 🌐 **Safari Web Extension** — Intercepts downloads directly from Safari
- ⏯️ **Pause/Resume/Cancel** — Full download control
- 📊 **Speed & ETA Tracking** — Real-time speed calculation with estimated time
- 📂 **Auto-Categorization** — Sorts files into Videos, Documents, Music, etc.
- 🕐 **Download Scheduler** — Schedule downloads for specific times
- 📱 **Menu Bar Widget** — Quick access from the status bar
- 🎨 **Dark Theme** — Modern, polished dark UI
- ⚙️ **Configurable** — Concurrent downloads, speed limits, launch at login, hide from dock

## Requirements

- macOS 14.0+ (Sonoma)
- Xcode 15.0+
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) (for project generation)

## Setup

```bash
# Install XcodeGen (if not installed)
brew install xcodegen

# Generate Xcode project
cd SwiftDownloader
xcodegen generate

# Open in Xcode
open SwiftDownloader.xcodeproj
```

## Safari Extension Setup

1. Run the app from Xcode (⌘R)
2. Safari → **Develop** → **Allow Unsigned Extensions**
3. Safari → **Settings** → **Extensions** → Enable **Fetchora Extension**

## Tech Stack

- **Swift 5.9** / **SwiftUI**
- **SwiftData** for persistence
- **URLSession** for downloads
- **Safari Web Extension** (Manifest V2)

## License

MIT
