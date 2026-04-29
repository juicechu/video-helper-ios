//
//  VideoDownloader.swift
//  videohelper
//
//  Created by juice on 2026/4/9.
//

import Foundation
import Photos
import UIKit
import Combine
import AVFoundation

class VideoDownloader: ObservableObject {
    @Published var isDownloading = false
    @Published var statusMessage = ""
    @Published var alertMessage: String?
    @Published var showSettingsAlert = false
    @Published var forceDownload = false
    @Published var downloadURL: String = ""

    private let downloadedStore = DownloadedStore()

    func getVideoURLFromArgs() -> String? {
        let args = ProcessInfo.processInfo.arguments

        if let idx = args.firstIndex(of: "-video_url"),
           idx + 1 < args.count {
            return args[idx + 1]
        }
        return nil
    }

    func getAutoFlagFromArgs() -> Bool {
        let args = ProcessInfo.processInfo.arguments

        // If no -video_url, return false
        if args.firstIndex(of: "-video_url") == nil {
            return false
        }

        // If -auto present, check its value
        if let idx = args.firstIndex(of: "-auto"),
           idx + 1 < args.count {
            let value = args[idx + 1].lowercased()
            return value == "true" || value == "1" || value == "yes"
        }

        // Default: auto if -video_url present without -auto
        return true
    }

    func downloadAndSave(urlString: String, completion: @escaping (Bool) -> Void) {
        // Store URL for UI binding
        print("[VideoDownloader] Starting download for: \(urlString)")
        DispatchQueue.main.async {
            self.downloadURL = urlString
        }

        // Check if already downloaded (skip if force download)
        if !forceDownload && downloadedStore.isDownloaded(urlString) {
            print("[VideoDownloader] URL already in downloaded history, skipping")
            DispatchQueue.main.async {
                self.alertMessage = "This video was previously saved. Enable 'Force Download' to save again."
                completion(true)
            }
            return
        }

        // Encode unencoded chars (non-ASCII, spaces) preserving existing %XX sequences,
        // then construct URL via URLComponents to prevent Foundation double-encoding %XX
        let encodedString = encodeUnencodedNonASCII(urlString)
        let url = constructURL(encodedString)

        guard let url = url else {
            print("[VideoDownloader] ERROR: Failed to create URL from string")
            DispatchQueue.main.async {
                self.alertMessage = "Invalid URL format. Please check the URL."
                completion(false)
            }
            return
        }

        DispatchQueue.main.async {
            self.isDownloading = true
            self.statusMessage = "Downloading..."
        }

        print("[VideoDownloader] Requesting URL: \(url.absoluteString)")

        let task = URLSession.shared.downloadTask(with: url) { tempURL, response, error in
            guard let tempURL = tempURL, error == nil else {
                print("[VideoDownloader] ERROR: Download failed - \(error?.localizedDescription ?? "Unknown error")")
                DispatchQueue.main.async {
                    self.isDownloading = false
                    self.alertMessage = "Download failed: \(error?.localizedDescription ?? "Check your network connection")"
                    completion(false)
                }
                return
            }

            // Validate HTTP response
            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode) else {
                let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
                print("[VideoDownloader] ERROR: HTTP status \(statusCode)")
                DispatchQueue.main.async {
                    self.isDownloading = false
                    self.alertMessage = "Server error (HTTP \(statusCode)). The video may be unavailable or requires authentication."
                }
                try? FileManager.default.removeItem(at: tempURL)
                completion(false)
                return
            }

            print("[VideoDownloader] HTTP \(httpResponse.statusCode) - Content-Type: \(httpResponse.value(forHTTPHeaderField: "Content-Type") ?? "unknown")")

            // Check content type if available
            if let contentType = httpResponse.value(forHTTPHeaderField: "Content-Type"),
               !contentType.hasPrefix("video/") && !contentType.hasPrefix("application/octet-stream") {
                print("[VideoDownloader] ERROR: Invalid content type: \(contentType)")
                DispatchQueue.main.async {
                    self.isDownloading = false
                    self.alertMessage = "Invalid file type: \(contentType). Expected a video file."
                }
                try? FileManager.default.removeItem(at: tempURL)
                completion(false)
                return
            }

            let fileName = UUID().uuidString + ".mp4"
            let destURL = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)

            do {
                // Verify file has content
                let attributes = try FileManager.default.attributesOfItem(atPath: tempURL.path)
                guard let fileSize = attributes[.size] as? Int64, fileSize > 0 else {
                    print("[VideoDownloader] ERROR: Downloaded file is empty")
                    DispatchQueue.main.async {
                        self.isDownloading = false
                        self.alertMessage = "Downloaded file is empty (0 bytes). The video may not exist or requires authentication."
                    }
                    try? FileManager.default.removeItem(at: tempURL)
                    completion(false)
                    return
                }

                print("[VideoDownloader] Downloaded \(fileSize) bytes to: \(tempURL.path)")
                try FileManager.default.moveItem(at: tempURL, to: destURL)
                print("[VideoDownloader] Moved to: \(destURL.path)")
                self.saveToPhotos(fileURL: destURL, originalUrlString: urlString, completion: completion)
            } catch {
                print("[VideoDownloader] ERROR: File operation failed - \(error.localizedDescription)")
                DispatchQueue.main.async {
                    self.isDownloading = false
                    self.alertMessage = "Failed to save downloaded file: \(error.localizedDescription)"
                    completion(false)
                }
            }
        }

        task.resume()
    }

    private func parseAndEncodeURL(_ urlString: String) -> URL? {
        // First, decode any existing percent-encoding to get raw characters
        // Then re-encode properly. This prevents double-encoding issues where
        // already-encoded parts (like signatures) would get encoded again.
        let decodedString = urlString.removingPercentEncoding ?? urlString

        // Find scheme separator
        guard let schemeRange = decodedString.range(of: "://") else {
            return nil
        }

        let scheme = String(decodedString[..<schemeRange.lowerBound])
        let remainder = String(decodedString[schemeRange.upperBound...])

        // Split host from path/query/fragment
        var host: String?
        var pathAndQuery = ""

        if let slashIndex = remainder.firstIndex(of: "/") {
            host = String(remainder[..<slashIndex])
            pathAndQuery = String(remainder[slashIndex...])
        } else {
            host = remainder.isEmpty ? nil : remainder
            pathAndQuery = "/"
        }

        // Build URLComponents with proper encoding
        var components = URLComponents()
        components.scheme = scheme
        components.host = host?.addingPercentEncoding(withAllowedCharacters: .urlHostAllowed)

        // Split path and query/fragment
        if let queryIndex = pathAndQuery.firstIndex(of: "?") {
            let pathPart = String(pathAndQuery[..<queryIndex])
            let queryAndFragment = String(pathAndQuery[queryIndex...])

            components.path = pathPart.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? pathPart

            // Handle query and fragment
            if let fragmentIndex = queryAndFragment.firstIndex(of: "#") {
                let queryPart = String(queryAndFragment[queryAndFragment.startIndex..<fragmentIndex])
                let fragmentPart = String(queryAndFragment[fragmentIndex...])
                components.query = parseQuery(queryPart)
                components.fragment = parseFragment(fragmentPart)
            } else {
                components.query = parseQuery(queryAndFragment)
            }
        } else if let fragmentIndex = pathAndQuery.firstIndex(of: "#") {
            let pathPart = String(pathAndQuery[..<fragmentIndex])
            let fragmentPart = String(pathAndQuery[fragmentIndex...])
            components.path = pathPart.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? pathPart
            components.fragment = parseFragment(fragmentPart)
        } else {
            components.path = pathAndQuery.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? pathAndQuery
        }

        return components.url
    }

    private func parseQuery(_ queryWithQuestionMark: String) -> String? {
        // Remove leading "?" if present
        let queryString = queryWithQuestionMark.hasPrefix("?") ? String(queryWithQuestionMark.dropFirst()) : queryWithQuestionMark
        guard !queryString.isEmpty else { return nil }

        // Split by & and encode each parameter
        let pairs = queryString.split(separator: "&", omittingEmptySubsequences: false)
        let encodedPairs = pairs.map { pair -> String in
            let parts = pair.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            if parts.count == 2 {
                let key = parts[0].addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? String(parts[0])
                let value = parts[1].addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? String(parts[1])
                return "\(key)=\(value)"
            } else {
                return String(parts[0]).addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? String(parts[0])
            }
        }
        return encodedPairs.joined(separator: "&")
    }

    private func parseFragment(_ fragmentWithHash: String) -> String? {
        // Remove leading "#" if present
        let fragment = fragmentWithHash.hasPrefix("#") ? String(fragmentWithHash.dropFirst()) : fragmentWithHash
        guard !fragment.isEmpty else { return nil }
        return fragment.addingPercentEncoding(withAllowedCharacters: .urlFragmentAllowed) ?? fragment
    }

    /// Encode unencoded characters invalid in URLs (non-ASCII, space, control chars), preserving existing %XX sequences
    private func encodeUnencodedNonASCII(_ urlString: String) -> String {
        var result = ""
        var i = urlString.startIndex

        while i < urlString.endIndex {
            let char = urlString[i]

            // Check for existing percent-encoded sequence (%XX)
            if char == "%" {
                // Check if this is a valid %XX sequence
                let nextIdx = urlString.index(i, offsetBy: 1)
                let nextNextIdx = urlString.index(i, offsetBy: 2)

                if nextIdx < urlString.endIndex && nextNextIdx < urlString.endIndex {
                    let hex1 = urlString[nextIdx]
                    let hex2 = urlString[nextNextIdx]

                    if hex1.isHexDigit && hex2.isHexDigit {
                        // Valid %XX sequence - preserve it
                        result.append(char)
                        result.append(hex1)
                        result.append(hex2)
                        i = urlString.index(after: nextNextIdx)
                        continue
                    }
                }
            }

            // Encode characters that need percent-encoding in URLs:
            // - Non-ASCII characters (not in 0-127 range)
            // - ASCII characters invalid in URLs: space (0x20) and control chars (0x00-0x1F, 0x7F)
            if !char.isASCII {
                let encoded = char.utf8.map { byte -> String in
                    return "%" + String(byte, radix: 16).uppercased()
                }.joined()
                result.append(encoded)
            } else if let ascii = char.asciiValue, ascii <= 0x20 || ascii == 0x7F {
                let hex = String(ascii, radix: 16).uppercased()
                let paddedHex = hex.count == 1 ? "0" + hex : hex
                result.append("%" + paddedHex)
            } else {
                result.append(char)
            }

            i = urlString.index(after: i)
        }

        return result
    }

    /// Build URL from an already-percent-encoded string using URLComponents.
    /// Using percentEncodedPath/percentEncodedQuery prevents Foundation from
    /// double-encoding existing %XX sequences (e.g. %23 → %2523).
    private func constructURL(_ encodedString: String) -> URL? {
        guard let schemeRange = encodedString.range(of: "://") else { return nil }
        let scheme = String(encodedString[..<schemeRange.lowerBound])
        let remainder = String(encodedString[schemeRange.upperBound...])

        var host = ""
        var pathAndQuery = "/"

        if let slashIndex = remainder.firstIndex(of: "/") {
            host = String(remainder[..<slashIndex])
            pathAndQuery = String(remainder[slashIndex...])
        } else {
            host = remainder
        }

        var path = pathAndQuery
        var query: String? = nil

        if let queryIndex = pathAndQuery.firstIndex(of: "?") {
            path = String(pathAndQuery[..<queryIndex])
            query = String(pathAndQuery[pathAndQuery.index(after: queryIndex)...])
        }

        var components = URLComponents()
        components.scheme = scheme
        components.host = host
        components.percentEncodedPath = path
        components.percentEncodedQuery = query

        return components.url
    }

    private func saveToPhotos(fileURL: URL, originalUrlString: String, completion: @escaping (Bool) -> Void) {
        print("[VideoDownloader] Starting export to Photos")
        DispatchQueue.main.async {
            self.statusMessage = "Exporting video..."
        }

        // Workaround for iOS Photos error 3302 (invalidResource)
        // iOS Photos is stricter than AVPlayer - rejects non-standard container/codec/metadata
        // First try Passthrough (fast), fallback to HighestQuality if still fails
        self.exportAndSave(fileURL: fileURL, originalUrlString: originalUrlString, useHighestQuality: false, completion: completion)
    }

    private func exportAndSave(fileURL: URL, originalUrlString: String, useHighestQuality: Bool, completion: @escaping (Bool) -> Void) {
        // Use 1280x720 preset for maximum compatibility while maintaining HD quality
        // For streaming segments/fragmented MP4, quality-based presets may fail with "Operation Stopped"
        // Resolution-based presets (640x480, 960x540, 1280x720) force complete re-encoding
        let preset = useHighestQuality ? AVAssetExportPreset1280x720 : AVAssetExportPresetPassthrough
        let asset = AVAsset(url: fileURL)
        print("[VideoDownloader] Export preset: \(preset)")

        // Check if asset has video tracks - if not, it's likely a non-video file or corrupted
        asset.loadValuesAsynchronously(forKeys: ["tracks", "duration", "playable"]) {
            var error: NSError?
            let tracksStatus = asset.statusOfValue(forKey: "tracks", error: &error)
            let playableStatus = asset.statusOfValue(forKey: "playable", error: &error)

            print("[VideoDownloader] Asset loaded - tracks: \(tracksStatus), playable: \(playableStatus)")

            guard tracksStatus == .loaded, playableStatus == .loaded else {
                print("[VideoDownloader] ERROR: Failed to load asset - tracks: \(tracksStatus), playable: \(playableStatus)")
                if let error = error {
                    print("[VideoDownloader] Asset error: \(error.localizedDescription)")
                }
                // Asset couldn't be loaded - try fallback if we haven't already
                if !useHighestQuality {
                    print("[VideoDownloader] Retrying with HighestQuality preset")
                    self.exportAndSave(fileURL: fileURL, originalUrlString: originalUrlString, useHighestQuality: true, completion: completion)
                    return
                }
                DispatchQueue.main.async {
                    self.isDownloading = false
                    self.alertMessage = "Invalid video file: unable to read video tracks. The file may be corrupted or not a valid video."
                }
                try? FileManager.default.removeItem(at: fileURL)
                completion(false)
                return
            }

            let videoTracks = asset.tracks(withMediaType: .video)
            print("[VideoDownloader] Video tracks found: \(videoTracks.count)")
            guard !videoTracks.isEmpty else {
                DispatchQueue.main.async {
                    self.isDownloading = false
                    self.alertMessage = "No video tracks found. The file may be audio-only or not a valid video."
                }
                try? FileManager.default.removeItem(at: fileURL)
                completion(false)
                return
            }

            // Proceed with export
            self.performExport(asset: asset, fileURL: fileURL, preset: preset, originalUrlString: originalUrlString, useHighestQuality: useHighestQuality, completion: completion)
        }
    }

    private func performExport(asset: AVAsset, fileURL: URL, preset: String, originalUrlString: String, useHighestQuality: Bool, completion: @escaping (Bool) -> Void) {
        let exportURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".mp4")
        print("[VideoDownloader] Export destination: \(exportURL.path)")

        guard let exportSession = AVAssetExportSession(asset: asset, presetName: preset) else {
            print("[VideoDownloader] ERROR: Failed to create export session")
            DispatchQueue.main.async {
                self.isDownloading = false
                self.alertMessage = "Failed to initialize video export. Try again or use a different video."
            }
            try? FileManager.default.removeItem(at: fileURL)
            completion(false)
            return
        }

        exportSession.outputURL = exportURL
        exportSession.outputFileType = .mp4
        print("[VideoDownloader] Export started with fileType: MP4")

        exportSession.exportAsynchronously {
            print("[VideoDownloader] Export status: \(exportSession.status.rawValue)")
            guard exportSession.status == .completed else {
                let exportError = exportSession.error?.localizedDescription ?? "Unknown error"
                print("[VideoDownloader] ERROR: Export failed - \(exportError)")
                if let error = exportSession.error {
                    print("[VideoDownloader] Export error details: \(error)")
                }
                try? FileManager.default.removeItem(at: exportURL)

                // If Passthrough export failed, fallback to HighestQuality
                if !useHighestQuality {
                    print("[VideoDownloader] Falling back to HighestQuality preset")
                    DispatchQueue.main.async {
                        self.statusMessage = "Re-encoding video..."
                    }
                    self.exportAndSave(fileURL: fileURL, originalUrlString: originalUrlString, useHighestQuality: true, completion: completion)
                    return
                }

                DispatchQueue.main.async {
                    self.isDownloading = false
                    self.alertMessage = "Video export failed: \(exportError). The video format may be incompatible."
                }
                try? FileManager.default.removeItem(at: fileURL)
                completion(false)
                return
            }

            print("[VideoDownloader] Export completed successfully")
            // Export succeeded, now save to Photos
            // Only delete original file after successful export
            if useHighestQuality {
                try? FileManager.default.removeItem(at: fileURL)
            }

            PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
                print("[VideoDownloader] Photo library authorization status: \(status.rawValue)")
                guard status == .authorized else {
                    print("[VideoDownloader] ERROR: Photo library access denied")
                    DispatchQueue.main.async {
                        self.isDownloading = false
                        self.showSettingsAlert = true
                    }
                    try? FileManager.default.removeItem(at: exportURL)
                    if !useHighestQuality { try? FileManager.default.removeItem(at: fileURL) }
                    completion(false)
                    return
                }

                DispatchQueue.main.async {
                    self.statusMessage = "Saving to Photos..."
                }

                print("[VideoDownloader] Creating asset in Photos library")
                PHPhotoLibrary.shared().performChanges({
                    PHAssetCreationRequest.creationRequestForAssetFromVideo(atFileURL: exportURL)
                }) { success, error in
                    try? FileManager.default.removeItem(at: exportURL)

                    DispatchQueue.main.async {
                        self.isDownloading = false
                        if success {
                            print("[VideoDownloader] Video saved to Photos successfully")
                            if !useHighestQuality { try? FileManager.default.removeItem(at: fileURL) }
                            self.downloadedStore.markDownloaded(originalUrlString)
                            self.alertMessage = "Video saved to Photos successfully!"
                            self.statusMessage = "Done"
                            completion(true)
                        } else {
                            print("[VideoDownloader] ERROR: Failed to save to Photos - \(error?.localizedDescription ?? "Unknown")")
                            if let error = error {
                                print("[VideoDownloader] Photos save error: \(error)")
                            }
                            // If Passthrough result still triggered 3302, fallback to HighestQuality
                            if !useHighestQuality {
                                print("[VideoDownloader] Retrying with re-encoding")
                                DispatchQueue.main.async {
                                    self.statusMessage = "Re-encoding video..."
                                }
                                self.exportAndSave(fileURL: fileURL, originalUrlString: originalUrlString, useHighestQuality: true, completion: completion)
                                return
                            }
                            try? FileManager.default.removeItem(at: fileURL)
                            self.alertMessage = "Failed to save to Photos: \(error?.localizedDescription ?? "Unknown error"). Please check Photos permissions."
                            completion(false)
                        }
                    }
                }
            }
        }
    }
}