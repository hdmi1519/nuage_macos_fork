//
//  URLDetail.swift
//  Nuage
//
//  Created by Laurin Brandner on 02.08.23.
//

import SwiftUI
import SoundCloud
import Combine

struct URLDetail: View {
    
    var url: URL
    @State private var item: Some?
    @State private var isLoading = true
    @State private var hasFailed = false
    
    @State private var subscriptions = Set<AnyCancellable>()
    
    var body: some View {
        Group {
            if let item = item {
                switch item {
                case .track(let track):
                    TrackDetail(track: track)
                        .playbackContext([track])
                        .playbackStart(at: track)
                case .user(let user):
                    UserDetail(user: user)
                case .userPlaylist(let playlist):
                    PlaylistDetail(playlist: .user(playlist))
                case .systemPlaylist(let playlist):
                    PlaylistDetail(playlist: .system(playlist))
                }
            } else if hasFailed {
                VStack(spacing: 12) {
                    Image(systemName: "link.badge.plus")
                        .font(.system(size: 38))
                        .foregroundColor(.secondary)
                    Text(LocalizedStringKey("url.openFailed"))
                        .font(.system(size: 15, weight: .semibold))
                    Text(url.absoluteString)
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                    Button(LocalizedStringKey("url.retry")) {
                        loadURL()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .padding(.top, 4)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ProgressView()
                    .progressViewStyle(.circular)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onAppear {
            loadURL()
        }
    }
    
    private func loadURL() {
        isLoading = true
        hasFailed = false
        
        let cleanedURL = cleanSoundCloudURL(url)
        
        if cleanedURL.host?.contains("on.soundcloud.com") == true {
            var request = URLRequest(url: cleanedURL)
            request.httpMethod = "HEAD"
            URLSession.shared.dataTask(with: request) { _, response, _ in
                let targetURL = response?.url ?? cleanedURL
                DispatchQueue.main.async {
                    self.resolve(url: targetURL)
                }
            }.resume()
        } else {
            resolve(url: cleanedURL)
        }
    }
    
    private func resolve(url: URL) {
        SoundCloud.shared.get(.resolve(url))
            .receive(on: RunLoop.main)
            .sink(receiveCompletion: { completion in
                if case .failure(let error) = completion {
                    print("Failed to resolve URL \(url): \(error)")
                    self.isLoading = false
                    self.hasFailed = true
                }
            }, receiveValue: { resolved in
                self.isLoading = false
                self.hasFailed = false
                self.item = resolved
            })
            .store(in: &subscriptions)
    }
    
}
