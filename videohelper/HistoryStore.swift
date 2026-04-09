//
//  HistoryStore.swift
//  videohelper
//
//  Created by juice on 2026/4/9.
//

import Foundation
import Combine

class HistoryStore: ObservableObject {
    @Published var urls: [String] = []

    private let maxCount = 50
    private let key = "downloadHistory"

    init() {
        load()
    }

    func add(_ url: String) {
        // Remove if exists (for dedup)
        urls.removeAll { $0 == url }
        // Add to front
        urls.insert(url, at: 0)
        // Trim to max
        if urls.count > maxCount {
            urls = Array(urls.prefix(maxCount))
        }
        save()
    }

    private func load() {
        urls = UserDefaults.standard.stringArray(forKey: key) ?? []
    }

    private func save() {
        UserDefaults.standard.set(urls, forKey: key)
    }

    func clear() {
        urls = []
        save()
    }
}