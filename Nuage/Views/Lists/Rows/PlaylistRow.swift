//
//  PlaylistRow.swift
//  Nuage
//
//  Created by Laurin Brandner on 25.12.20.
//

import SwiftUI
import Combine
import SoundCloud

struct PlaylistRow<T: Playlist>: View {
    
    var playlist: T
    
    @State private var isHovered = false
    @State private var isCopied = false
    @State private var subscriptions = Set<AnyCancellable>()
    
    @EnvironmentObject private var player: StreamPlayer
    @Environment(\.playlists) private var playlists: [AnyPlaylist]
    @Environment(\.posts) private var posts: [Post]
    @Environment(\.toggleLikePlaylist) private var toggleLikePlaylist: (AnyPlaylist) -> () -> ()
    @Environment(\.toggleRepostPlaylist) private var toggleRepostPlaylist: (UserPlaylist) -> () -> ()
    
    private var isLiked: Bool {
        playlists.contains(where: { $0.id == playlist.id })
    }
    
    private var isRepost: Bool {
        guard let userP = playlist.eraseToAnyPlaylist().userPlaylist else { return false }
        return posts.filter { !$0.isTrack && $0.isRepost }
            .compactMap { $0.playlist }
            .contains(where: { $0.id == userP.id })
    }
    
    private var trackCount: Int {
        playlist.trackCount ?? playlist.tracks?.count ?? playlist.trackIDs?.count ?? 0
    }
    
    private var backgroundColor: Color {
        if isHovered {
            return Color.primary.opacity(0.06)
        } else {
            return Color.clear
        }
    }
    
    private func playPlaylist() {
        let anyP = playlist.eraseToAnyPlaylist()
        if let tracks = anyP.tracks, !tracks.isEmpty {
            player.play(tracks, from: 0)
            return
        }
        
        switch anyP {
        case .user(let userP):
            SoundCloud.shared.get(.userPlaylist(userP.id))
                .receive(on: RunLoop.main)
                .sink(receiveCompletion: { _ in }, receiveValue: { p in
                    if let ids = p.trackIDs, !ids.isEmpty {
                        SoundCloud.shared.get(.tracks(ids))
                            .receive(on: RunLoop.main)
                            .sink(receiveCompletion: { _ in }, receiveValue: { tracks in
                                self.player.play(tracks, from: 0)
                            })
                            .store(in: &self.subscriptions)
                    }
                })
                .store(in: &subscriptions)
        case .system(let sysP):
            SoundCloud.shared.get(.systemPlaylist(sysP.urn))
                .receive(on: RunLoop.main)
                .sink(receiveCompletion: { _ in }, receiveValue: { p in
                    if let ids = p.trackIDs, !ids.isEmpty {
                        SoundCloud.shared.get(.tracks(ids))
                            .receive(on: RunLoop.main)
                            .sink(receiveCompletion: { _ in }, receiveValue: { tracks in
                                self.player.play(tracks, from: 0)
                            })
                            .store(in: &self.subscriptions)
                    }
                })
                .store(in: &subscriptions)
        }
    }
    
    private func copyLink() {
        let text = playlist.permalinkURL.absoluteString
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        withAnimation {
            isCopied = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation {
                isCopied = false
            }
        }
    }
    
    var body: some View {
        let artworkURL = playlist.artworkURL ?? playlist.tracks?.first?.artworkURL
        let anyPlaylist = playlist.eraseToAnyPlaylist()
        
        HStack(alignment: .center, spacing: 14) {
            // Main clickable area: Artwork + Info + Spacer
            NavigationLink(value: anyPlaylist) {
                HStack(alignment: .center, spacing: 14) {
                    // Artwork with play button overlay on hover
                    ZStack {
                        RemoteImage(url: artworkURL, cornerRadius: 8)
                            .aspectRatio(1, contentMode: .fill)
                            .frame(width: 74, height: 74)
                        
                        if isHovered {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(Color.black.opacity(0.35))
                                .frame(width: 74, height: 74)
                            
                            Button(action: playPlaylist) {
                                ZStack {
                                    Circle()
                                        .fill(Color(hex: 0xFF5500))
                                        .frame(width: 34, height: 34)
                                        .shadow(color: Color.black.opacity(0.25), radius: 3, x: 0, y: 1)
                                    
                                    Image(systemName: "play.fill")
                                        .font(.system(size: 13, weight: .bold))
                                        .foregroundColor(.white)
                                        .offset(x: 1)
                                }
                            }
                            .buttonStyle(.plain)
                            .transition(.opacity)
                        }
                    }
                    .frame(width: 74, height: 74)
                    
                    // Middle info column
                    VStack(alignment: .leading, spacing: 4) {
                        // Badge & Private indicator
                        HStack(spacing: 6) {
                            let badgeText = (anyPlaylist.userPlaylist?.isAlbum == true) ? "playlist.album" : "playlist.badge"
                            Text(LocalizedStringKey(badgeText))
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(.secondary)
                            
                            if !playlist.isPublic {
                                Image(systemName: "lock.fill")
                                    .font(.system(size: 9))
                                    .foregroundColor(.orange)
                            }
                        }
                        
                        // Title
                        Text(playlist.title)
                            .font(.system(size: 15, weight: .bold))
                            .foregroundColor(.primary)
                            .lineLimit(1)
                        
                        // Creator & Track count
                        HStack(spacing: 6) {
                            Text(playlist.user.username)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(.secondary)
                            
                            Text("•")
                                .font(.system(size: 10))
                                .foregroundColor(.secondary.opacity(0.5))
                            
                            Text("\(trackCount) \(NSLocalizedString("playlists.tracksCount", comment: ""))")
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                        }
                        
                        if let description = playlist.description, !description.isEmpty {
                            Text(description.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "\n", with: " "))
                                .font(.system(size: 12))
                                .foregroundColor(.secondary.opacity(0.8))
                                .lineLimit(1)
                        }
                    }
                    
                    Spacer(minLength: 8)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            
            // Trailing actions row
            HStack(spacing: 12) {
                // Like button
                Button(action: toggleLikePlaylist(anyPlaylist)) {
                    Image(systemName: isLiked ? "heart.fill" : "heart")
                        .font(.system(size: 14))
                        .foregroundColor(isLiked ? Color(hex: 0xFF5500) : .secondary)
                }
                .buttonStyle(.plain)
                .help(LocalizedStringKey(isLiked ? "context.unlike" : "context.like"))
                
                // Repost button
                if let userP = anyPlaylist.userPlaylist {
                    Button(action: toggleRepostPlaylist(userP)) {
                        Image(systemName: "arrow.2.squarepath")
                            .font(.system(size: 13))
                            .foregroundColor(isRepost ? Color(hex: 0xFF5500) : .secondary)
                    }
                    .buttonStyle(.plain)
                    .help(LocalizedStringKey(isRepost ? "context.unrepost" : "context.repost"))
                }
                
                // Copy link button
                Button(action: copyLink) {
                    Image(systemName: isCopied ? "checkmark" : "link")
                        .font(.system(size: 13))
                        .foregroundColor(isCopied ? .green : .secondary)
                }
                .buttonStyle(.plain)
                .help(LocalizedStringKey("track.copyLink"))
                
                // Navigation Chevron
                NavigationLink(value: anyPlaylist) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.secondary.opacity(0.5))
                }
                .buttonStyle(.plain)
            }
            .opacity(isHovered ? 1.0 : 0.6)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(backgroundColor)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(isHovered ? Color.primary.opacity(0.08) : Color.clear, lineWidth: 0.5)
        )

        .contentShape(Rectangle())
        .onHover { inside in
            withAnimation(.easeInOut(duration: 0.12)) {
                isHovered = inside
            }
        }
        .contextMenu {
            Button(LocalizedStringKey("context.play"), action: playPlaylist)
            
            Divider()
            
            NavigationLink(LocalizedStringKey("context.goToArtist"), value: playlist.user)
            
            Divider()
            
            Button(LocalizedStringKey(isLiked ? "context.unlike" : "context.like"), action: toggleLikePlaylist(anyPlaylist))
            if let userP = anyPlaylist.userPlaylist {
                Button(LocalizedStringKey("context.repost"), action: toggleRepostPlaylist(userP))
            }
            
            Button(LocalizedStringKey("context.copyLink"), action: copyLink)
            
            Button(LocalizedStringKey("context.shareToFriend")) {
                NotificationCenter.default.post(name: .sharePlaylistToFriend, object: anyPlaylist)
            }
        }
    }
}
