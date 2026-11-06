//
//  DownloadedStore.swift
//  videohelper
//
//  Created by juice on 2026/4/10.
//

import Foundation

class DownloadedStore {
    private let key = "lastDownloadedUrl"

    func isDownloaded(_ url: String) -> Bool {
        guard let lastUrl = UserDefaults.standard.string(forKey: key) else {
            return false
        }
        return lastUrl == url
    }

    func markDownloaded(_ url: String) {
        UserDefaults.standard.set(url, forKey: key)
    }

    func clear() {
        UserDefaults.standard.removeObject(forKey: key)
    }
}