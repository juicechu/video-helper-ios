# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build Commands

This is an Xcode project. Build and run via Xcode IDE:
- Build: `Cmd+B`
- Clean: `Cmd+Shift+K`
- Run: `Cmd+R`

## Project Architecture

iOS app (Swift/SwiftUI, minimum iOS 15.0) that downloads videos and images and saves them to the Photos library.

### Services

- **VideoDownloader.swift** - Core service: URL argument parsing (`ProcessInfo.processInfo.arguments`), media download via `URLSession`, content-type detection (video vs. image vs. unsupported), photo library save via `PHPhotoLibrary`. Handles URL encoding for non-ASCII characters. Supported images: JPEG, PNG, GIF, HEIC, HEIF; videos use the existing AVAsset export pipeline.
- **HistoryStore.swift** - UserDefaults-backed URL history (max 50 items, most recent first, deduplication)
- **DownloadedStore.swift** - UserDefaults-backed record of the last successfully downloaded URL (prevents re-downloading the same video or image)

### Views

- **ContentView.swift** - Main UI: URL text field with history dropdown, clear button, force-download toggle, download button with loading state
- **videohelperApp.swift** - Entry point: auto-trigger logic from WDA launch arguments

### WDA Automation

App supports WebDriverAgent launch arguments:
```
-video_url <url>       # Required: URL to download (video or image)
-auto <true|false>     # Optional: auto-download (defaults to true)
```

The media type is detected from the HTTP `Content-Type`, so `-video_url` accepts image URLs too; no separate image flag exists.

### Permissions

Info.plist requires `NSPhotoLibraryAddUsageDescription` for photo library access (videos and images).

## Bundle ID

`com.seafarerit.videohelper`