# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build Commands

This is an Xcode project. Build and run via Xcode IDE:
- Build: `Cmd+B`
- Clean: `Cmd+Shift+K`
- Run: `Cmd+R`

## Project Architecture

iOS app (Swift/SwiftUI, minimum iOS 13.0) that downloads MP4 videos and saves to Photos album.

### Services

- **VideoDownloader.swift** - Core service: URL argument parsing (`ProcessInfo.processInfo.arguments`), video download via `URLSession`, photo library save via `PHPhotoLibrary`. Handles URL encoding for non-ASCII characters.
- **HistoryStore.swift** - UserDefaults-backed URL history (max 50 items, most recent first, deduplication)
- **DownloadedStore.swift** - UserDefaults-backed set of successfully downloaded URLs (prevents re-downloading same video)

### Views

- **ContentView.swift** - Main UI: URL text field with history dropdown, clear button, force-download toggle, download button with loading state
- **videohelperApp.swift** - Entry point: auto-trigger logic from WDA launch arguments

### WDA Automation

App supports WebDriverAgent launch arguments:
```
-video_url <url>       # Required: URL to download
-auto <true|false>     # Optional: auto-download (defaults to true)
```

### Permissions

Info.plist requires `NSPhotoLibraryAddUsageDescription` for photo library access.

## Bundle ID

`com.seafarerit.videohelper`