//
//  DownloadedStore.swift
//  videohelper
//
//  Created by juice on 2026/4/10.
//

import Foundation

class DownloadedStore {
    private let key = "downloadedUrls"

    func isDownloaded(_ url: String) -> Bool {
        let downloaded = getDownloadedUrls()
        return downloaded.contains(url)
    }

    func markDownloaded(_ url: String) {
        var downloaded = getDownloadedUrls()
        if !downloaded.contains(url) {
            downloaded.insert(url)
            save(downloaded)
        }
    }

    private func getDownloadedUrls() -> Set<String> {
        let array = UserDefaults.standard.stringArray(forKey: key) ?? []
        return Set(array)
    }

    private func save(_ urls: Set<String>) {
        UserDefaults.standard.set(Array(urls), forKey: key)
    }

    func clear() {
        UserDefaults.standard.removeObject(forKey: key)
    }
}