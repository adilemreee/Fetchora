# Fetchora

A Safari-focused download manager for macOS built with Swift, SwiftUI, and SwiftData.

## Features

- 🌐 **Safari Web Extension** — Intercepts Safari downloads and domain rules from the companion extension
- ⏯️ **Pause/Resume/Cancel** — Full download control
- 📊 **Speed & ETA Tracking** — Real-time speed calculation with estimated time
- 📂 **Auto-Categorization** — Sorts files into Videos, Documents, Music, etc.
- 🕐 **Scheduled Downloads** — Queue new downloads for a configured time or schedule individual items
- 🔁 **Startup Recovery** — Restarts interrupted waiting/downloading items on the next launch
- 🛡️ **Store Recovery UI** — Corrupted local data now surfaces a recovery/reset screen instead of silently falling back
- 🔐 **Bookmark-Based Folder Access** — Keeps access to user-selected download folders across relaunches
- 📱 **Menu Bar Widget** — Quick access from the status bar
- ⚙️ **Configurable** — Concurrent downloads, speed limits, launch at login, URL rules, hide from dock

## Requirements

- macOS 14.0+ (Sonoma)
- Xcode 15.0+
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) (for project generation)

## Setup

```bash
# Install XcodeGen (if not installed)
brew install xcodegen

# Generate the Xcode project from the repository root
cd /path/to/SwiftDownloader-main
xcodegen generate

# Open in Xcode
open SwiftDownloader.xcodeproj
```

## Tests

```bash
xcodebuild test -project SwiftDownloader.xcodeproj -scheme SwiftDownloaderTests -destination 'platform=macOS'
```

If you are running tests from the command line without local signing configured, use:

```bash
xcodebuild test -project SwiftDownloader.xcodeproj -scheme SwiftDownloaderTests -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO
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
