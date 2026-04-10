//
//  videohelperApp.swift
//  videohelper
//
//  Created by juice on 2026/4/9.
//

import SwiftUI

@main
struct videohelperApp: App {
    @StateObject private var historyStore = HistoryStore()
    @StateObject private var downloader = VideoDownloader()

    var body: some Scene {
        WindowGroup {
            ContentView(historyStore: historyStore, downloader: downloader)
                .onAppear {
                    // Auto-download from launch arguments if enabled
                    if downloader.getAutoFlagFromArgs(),
                       let videoURL = downloader.getVideoURLFromArgs() {
                        historyStore.add(videoURL)
                        downloader.downloadAndSave(urlString: videoURL) { success in
                            // App can close or minimize after download based on success
                            print("Auto-download completed with success: \(success)")
                        }
                    }
                }
        }
    }
}
