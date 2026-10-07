//
//  SearchList.swift
//  Nuage
//
//  Created by Laurin Brandner on 25.12.20.
//

import SwiftUI
import Combine
import Introspect
import SoundCloud

private enum SearchSection: String {
    case users
    case tracks
    case playlists
}

struct SearchList: View {
    
    var query: String
    
    @State private var users = [User]()
    @State private var tracks = [Track]()
    @State private var playlists = [UserPlaylist]()
    @State private var isLoading = true
    @State private var subscriptions = Set<AnyCancellable>()
    
    var body: some View {
        Group {
            if isLoading && users.isEmpty && tracks.isEmpty && playlists.isEmpty {
                ProgressView()
                    .progressViewStyle(.circular)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            else if users.isEmpty && tracks.isEmpty && playlists.isEmpty {
                Text(NSLocalizedString("menu.search", comment: ""))
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 16) {
                        if !users.isEmpty {
                            Section(content: {
                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(alignment: .top, spacing: 16) {
                                        ForEach(users) { user in
                                            NavigationLink(value: user) {
                                                UserItem(user: user)
                                            }
                                            .buttonStyle(.plain)
                                        }
                                    }
                                    .padding(.vertical, 4)
                                }
                            }, header: header(for: .users), footer: footer)
                        }
                        if !tracks.isEmpty {
                            Section(content: {
                                VStack(alignment: .leading) {
                                    ForEach(tracks) { track in
                                        TrackRow(track: track)
                                            .playbackStart(at: track)
                                    }
                                }
                                .playbackContext(tracks)
                            }, header: header(for: .tracks), footer: footer)
                        }
                        if !playlists.isEmpty {
                            Section(content: {
                                VStack(alignment: .leading) {
                                    ForEach(playlists) { playlist in
                                        PlaylistRow(playlist: playlist)
                                    }
                                }
                                .playbackContext(playlists)
                            }, header: header(for: .playlists), footer: footer)
                        }
                    }
                    .padding()
                }
                .introspectScrollView { scrollView in
                    scrollView.scrollerStyle = .overlay
                    scrollView.verticalScroller?.controlSize = .small
                }
            }
        }
        .navigationTitle(NSLocalizedString("menu.search", comment: ""))
        .task(id: query) {
            await performSearch(for: query)
        }
    }
    
    @MainActor
    private func performSearch(for query: String) async {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            users = []
            tracks = []
            playlists = []
            isLoading = false
            return
        }
        
        isLoading = true
        // Debounce 250ms
        do {
            try await Task.sleep(nanoseconds: 250_000_000)
        }
        catch {
            return
        }
        
        subscriptions.removeAll()
        SoundCloud.shared.get(.search(trimmed))
            .receive(on: RunLoop.main)
            .sink(receiveCompletion: { _ in
                self.isLoading = false
            }, receiveValue: { page in
                var newUsers = [User]()
                var newTracks = [Track]()
                var newPlaylists = [UserPlaylist]()
                for elem in page.collection {
                    switch elem {
                    case .user(let user): newUsers.append(user)
                    case .track(let track): newTracks.append(track)
                    case .userPlaylist(let playlist): newPlaylists.append(playlist)
                    default: break
                    }
                }
                self.users = newUsers
                self.tracks = newTracks
                self.playlists = newPlaylists
                self.isLoading = false
            })
            .store(in: &subscriptions)
    }
    
    private func header(for section: SearchSection) -> () -> some View {
        @ViewBuilder func buildHeader() -> some View {
            Text(section.rawValue.capitalized)
                .font(.title2)
                .bold()
        }
        return buildHeader
    }
    
    @ViewBuilder private func footer() -> some View {
        Divider()
            .padding(.vertical, 8)
    }
    
}
