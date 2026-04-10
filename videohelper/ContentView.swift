//
//  ContentView.swift
//  videohelper
//
//  Created by juice on 2026/4/9.
//

import SwiftUI

struct ContentView: View {
    @StateObject private var downloader: VideoDownloader
    @ObservedObject var historyStore: HistoryStore

    @State private var urlText = ""
    @State private var showHistory = false
    @FocusState private var urlFieldFocused: Bool

    init(historyStore: HistoryStore, downloader: VideoDownloader = VideoDownloader()) {
        self._downloader = StateObject(wrappedValue: downloader)
        self.historyStore = historyStore
    }

    var body: some View {
        VStack(spacing: 20) {
            // URL input with clear button
            HStack {
                TextField("Enter video URL", text: $urlText)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .focused($urlFieldFocused)
                    .onSubmit {
                        showHistory = false
                    }

                if !urlText.isEmpty {
                    Button(action: {
                        urlText = ""
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.gray)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
            .padding(.horizontal)

            // History list (when focused)
            if urlFieldFocused && historyStore.urls.count > 0 && urlText.isEmpty {
                ScrollView {
                    VStack(spacing: 4) {
                        ForEach(historyStore.urls, id: \.self) { url in
                            Button(action: {
                                urlText = url
                                showHistory = false
                                urlFieldFocused = false
                            }) {
                                Text(url)
                                    .font(.system(size: 14))
                                    .foregroundColor(.primary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(8)
                                    .background(Color(.systemGray6))
                                    .cornerRadius(4)
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                    }
                    .padding(.horizontal)
                }
                .frame(maxHeight: 200)
            }

            Spacer()

            // Status message
            if !downloader.statusMessage.isEmpty {
                Text(downloader.statusMessage)
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }

            // Download button
            Button(action: {
                guard !urlText.isEmpty else { return }
                historyStore.add(urlText)
                downloader.downloadAndSave(urlString: urlText) { _ in }
            }) {
                HStack {
                    if downloader.isDownloading {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle())
                        Text("Downloading...")
                    } else {
                        Text("Download")
                    }
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(downloader.isDownloading ? Color.gray : Color.blue)
                .foregroundColor(.white)
                .cornerRadius(8)
            }
            .disabled(downloader.isDownloading || urlText.isEmpty)
            .padding(.horizontal)

            Spacer()
        }
        .padding()
        .alert(item: Binding<String?>(
            get: { downloader.alertMessage },
            set: { downloader.alertMessage = $0 }
        )) { message in
            Alert(
                title: Text(message.contains("saved") ? "Success" : "Error"),
                message: Text(message),
                dismissButton: .default(Text("OK"))
            )
        }
        .alert("Photo Library Access Required", isPresented: $downloader.showSettingsAlert) {
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Please enable photo library access in Settings to save videos.")
        }
    }
}

extension String: Identifiable {
    public var id: String { self }
}

#Preview {
    ContentView(historyStore: HistoryStore(), downloader: VideoDownloader())
}
