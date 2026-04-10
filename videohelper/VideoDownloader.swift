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

class VideoDownloader: ObservableObject {
    @Published var isDownloading = false
    @Published var statusMessage = ""
    @Published var alertMessage: String?
    @Published var showSettingsAlert = false

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
        // Try direct URL first, then try percent-encoding for non-ASCII characters
        let url: URL?
        if let directURL = URL(string: urlString) {
            url = directURL
        } else {
            // Parse and encode URL components properly
            url = parseAndEncodeURL(urlString)
        }

        guard let url = url else {
            DispatchQueue.main.async {
                self.alertMessage = "Invalid URL"
                completion(false)
            }
            return
        }

        DispatchQueue.main.async {
            self.isDownloading = true
            self.statusMessage = "Downloading..."
        }

        let task = URLSession.shared.downloadTask(with: url) { tempURL, response, error in
            guard let tempURL = tempURL, error == nil else {
                DispatchQueue.main.async {
                    self.isDownloading = false
                    self.alertMessage = "Download failed: \(error?.localizedDescription ?? "Unknown error")"
                    completion(false)
                }
                return
            }

            // Validate HTTP response
            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode) else {
                let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
                DispatchQueue.main.async {
                    self.isDownloading = false
                    self.alertMessage = "Server returned error: \(statusCode)"
                }
                try? FileManager.default.removeItem(at: tempURL)
                completion(false)
                return
            }

            // Check content type if available
            if let contentType = httpResponse.value(forHTTPHeaderField: "Content-Type"),
               !contentType.hasPrefix("video/") && !contentType.hasPrefix("application/octet-stream") {
                DispatchQueue.main.async {
                    self.isDownloading = false
                    self.alertMessage = "Invalid content type: \(contentType)"
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
                    DispatchQueue.main.async {
                        self.isDownloading = false
                        self.alertMessage = "Downloaded file is empty"
                    }
                    try? FileManager.default.removeItem(at: tempURL)
                    completion(false)
                    return
                }

                try FileManager.default.moveItem(at: tempURL, to: destURL)
                self.saveToPhotos(fileURL: destURL, completion: completion)
            } catch {
                DispatchQueue.main.async {
                    self.isDownloading = false
                    self.alertMessage = "File error: \(error.localizedDescription)"
                    completion(false)
                }
            }
        }

        task.resume()
    }

    private func parseAndEncodeURL(_ urlString: String) -> URL? {
        // Find scheme separator
        guard let schemeRange = urlString.range(of: "://") else {
            return nil
        }

        let scheme = String(urlString[..<schemeRange.lowerBound])
        let remainder = String(urlString[schemeRange.upperBound...])

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

    private func saveToPhotos(fileURL: URL, completion: @escaping (Bool) -> Void) {
        DispatchQueue.main.async {
            self.statusMessage = "Saving to Photos..."
        }

        PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
            guard status == .authorized else {
                DispatchQueue.main.async {
                    self.isDownloading = false
                    self.showSettingsAlert = true
                    completion(false)
                }
                return
            }

            PHPhotoLibrary.shared().performChanges({
                PHAssetCreationRequest.creationRequestForAssetFromVideo(atFileURL: fileURL)
            }) { success, error in
                // Cleanup temp file
                try? FileManager.default.removeItem(at: fileURL)

                DispatchQueue.main.async {
                    self.isDownloading = false
                    if success {
                        self.alertMessage = "Video saved to Photos"
                        self.statusMessage = "Done"
                        completion(true)
                    } else {
                        self.alertMessage = "Failed to save: \(error?.localizedDescription ?? "Unknown error")"
                        completion(false)
                    }
                }
            }
        }
    }
}