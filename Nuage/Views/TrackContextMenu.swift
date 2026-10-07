//
//  TrackContextMenu.swift
//  Nuage
//
//  Created by Laurin Brandner on 04.12.20.
//  Copyright © 2020 Laurin Brandner. All rights reserved.
//

import SwiftUI
import Combine
import SoundCloud

private struct TrackContextMenu: ViewModifier {
    
    @ObservedObject private var soundCloud = SoundCloud.shared
    
    var track: Track
    var onRemove: (() -> Void)? = nil
    
    @State private var subscriptions = Set<AnyCancellable>()
    
    @Environment(\.playlists) private var playlists: [AnyPlaylist]
    @Environment(\.likes) private var likes: [Track]
    @Environment(\.posts) private var posts: [Post]
    @Environment(\.toggleLikeTrack) private var toggleLike: (Track) -> () -> ()
    @Environment(\.toggleRepostTrack) private var toggleRepost: (Track) -> () -> ()
    @Environment(\.onPlay) private var onPlay: () -> ()
    
    private var isLiked: Bool {
        likes.contains(track)
    }
    
    private var isRepost: Bool {
        posts.filter { $0.isTrack && $0.isRepost }
            .compactMap { $0.tracks.first }
            .contains(track)
    }
    
    // Computed outside the contextMenu body to avoid re-evaluation flicker on hover
    private var myPlaylists: [UserPlaylist] {
        playlists
            .compactMap { $0.userPlaylist }
            .filter { $0.user.id == SoundCloud.shared.user?.id }
    }
    
    func body(content: Content) -> some View {
        content.contextMenu {
            Button(LocalizedStringKey("context.play")) {
                StreamPlayer.shared?.play([track], from: 0)
            }
            Button(LocalizedStringKey("context.addToQueue")) {
                StreamPlayer.shared?.enqueue([track])
            }
            NavigationLink(LocalizedStringKey("context.startStation"), value: Station.track(track))
            
            Divider()
            
            NavigationLink(LocalizedStringKey("context.goToArtist"), value: track.user)
            
            Divider()
            
            Button(LocalizedStringKey(isLiked ? "context.unlike" : "context.like"), action: toggleLike(track))
            Button(LocalizedStringKey(isRepost ? "context.unrepost" : "context.repost"), action: toggleRepost(track))
            
            if !myPlaylists.isEmpty {
                Menu(LocalizedStringKey("context.addToPlaylist")) {
                    ForEach(myPlaylists, id: \.id) { playlist in
                        Button(playlist.title) {
                            addTrack(to: playlist)
                        }
                    }
                }
            }
            
            Divider()
            
            Button(LocalizedStringKey("context.lyrics")) {
                NotificationCenter.default.post(name: .openTrackLyrics, object: track)
            }
            
            Button(LocalizedStringKey("context.poster")) {
                NotificationCenter.default.post(name: .openTrackPoster, object: track)
            }
            
            Button(LocalizedStringKey("context.shareToFriend")) {
                NotificationCenter.default.post(name: .shareTrackToFriend, object: track)
            }
            
            Button(LocalizedStringKey("context.copyLink")) {
                let text = track.permalinkURL.absoluteString
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(text, forType: .string)
            }
            
            if let onRemove = onRemove {
                Divider()
                Button(role: .destructive, action: onRemove) {
                    Text(NSLocalizedString("playlists.removeFromPlaylist", comment: ""))
                }
            }
        }
    }
    
    private func addTrack(to playlist: UserPlaylist) {
        guard let newTrackID = Int(track.id) else { return }
        soundCloud.get(.userPlaylist(playlist.id))
            .map { ($0.trackIDs ?? []).compactMap { Int($0) } }
            .flatMap { soundCloud.get(.set(playlist, trackIDs: $0 + [newTrackID])) }
            .receive(on: RunLoop.main)
            .sink(receiveCompletion: { _ in }, receiveValue: { _ in })
            .store(in: &subscriptions)
    }

}

extension View {
    
    func trackContextMenu(with track: Track, onRemove: (() -> Void)? = nil) -> some View {
        return modifier(TrackContextMenu(track: track, onRemove: onRemove))
    }
    
}
