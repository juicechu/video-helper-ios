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
        guard let url = URL(string: urlString) else {
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

            let fileName = UUID().uuidString + ".mp4"
            let destURL = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)

            do {
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

    private func saveToPhotos(fileURL: URL, completion: @escaping (Bool) -> Void) {
        DispatchQueue.main.async {
            self.statusMessage = "Saving to Photos..."
        }

        PHPhotoLibrary.requestAuthorization { status in
            guard status == .authorized || status == .limited else {
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