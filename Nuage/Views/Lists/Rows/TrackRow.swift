//
//  TrackRow.swift
//  Nuage
//
//  Created by Laurin Brandner on 25.12.20.
//

import SwiftUI
import Combine
import SoundCloud

struct TrackRow: View {
    
    var track: Track
    
    @State private var isHovered = false
    @EnvironmentObject private var player: StreamPlayer
    @Environment(\.onPlay) private var onPlay: () -> ()
    @Environment(\.likes) private var likes: [Track]
    @Environment(\.posts) private var posts: [Post]
    @Environment(\.toggleLikeTrack) private var toggleLikeTrack: (Track) -> () -> ()
    @Environment(\.toggleRepostTrack) private var toggleRepostTrack: (Track) -> () -> ()
    
    private var isLiked: Bool {
        likes.contains(track)
    }
    
    private var isRepost: Bool {
        posts.contains(where: { $0.isTrack && $0.isRepost && $0.tracks.first?.id == track.id })
    }
    
    private var isCurrent: Bool {
        player.currentStream == track
    }
    
    private var isPlayingThis: Bool {
        isCurrent && player.isPlaying
    }
    
    private var backgroundColor: Color {
        if isCurrent {
            return Color(hex: 0xFF5500).opacity(isHovered ? 0.08 : 0.04)
        } else if isHovered {
            return Color.primary.opacity(0.06)
        } else {
            return Color.clear
        }
    }
    
    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            // 1. Artwork with Play/Pause overlay
            ZStack {
                RemoteImage(url: track.artworkURL ?? track.user.avatarURL, cornerRadius: 8)
                    .frame(width: 74, height: 74)
                
                if isHovered || isCurrent {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.black.opacity(isCurrent ? 0.40 : 0.30))
                        .frame(width: 74, height: 74)
                    
                    Button {
                        if isCurrent {
                            player.togglePlayback()
                        } else {
                            onPlay()
                            if player.currentStream != track {
                                player.play([track], from: 0)
                            }
                        }
                    } label: {
                        ZStack {
                            Circle()
                                .fill(Color(hex: 0xFF5500))
                                .frame(width: 34, height: 34)
                                .shadow(color: Color.black.opacity(0.25), radius: 3, x: 0, y: 1)
                            
                            Image(systemName: isPlayingThis ? "pause.fill" : "play.fill")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundColor(.white)
                                .offset(x: isPlayingThis ? 0 : 1.5)
                        }
                    }
                    .buttonStyle(.plain)
                    .transition(.opacity)
                }
            }
            .frame(width: 74, height: 74)
            
            // 2. Info Column
            VStack(alignment: .leading, spacing: 5) {
                // Title
                PlaybackNavigationLink(value: track) {
                    Text(track.title)
                        .font(.system(size: 14, weight: .semibold))
                        .lineLimit(1)
                        .foregroundColor(.primary)
                }
                .buttonStyle(.plain)
                
                // Artist
                NavigationLink(value: track.user) {
                    Text(track.user.username)
                        .font(.system(size: 12.5, weight: .regular))
                        .lineLimit(1)
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                
                // Actions & Stats лента
                HStack(spacing: 12) {
                    // Like Button
                    Button(action: { toggleLikeTrack(track)() }) {
                        HStack(spacing: 3.5) {
                            Image(systemName: isLiked ? "heart.fill" : "heart")
                            Text(format(count: track.likeCount))
                        }
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(isLiked ? Color(hex: 0xFF5500) : .secondary)
                    }
                    .buttonStyle(.plain)
                    
                    // Repost Button
                    Button(action: { toggleRepostTrack(track)() }) {
                        HStack(spacing: 3.5) {
                            Image(systemName: isRepost ? "arrow.triangle.2.circlepath.circle.fill" : "arrow.triangle.2.circlepath")
                            Text(format(count: track.repostCount))
                        }
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(isRepost ? Color(hex: 0xFF5500) : .secondary)
                    }
                    .buttonStyle(.plain)
                    
                    // Play Count
                    HStack(spacing: 3) {
                        Image(systemName: "play.fill")
                            .font(.system(size: 8))
                        Text(format(count: track.playbackCount))
                    }
                    .font(.system(size: 11, weight: .regular))
                    .foregroundColor(.secondary.opacity(0.85))
                    
                    // Duration (в той же ленте)
                    HStack(spacing: 3) {
                        Image(systemName: "clock")
                            .font(.system(size: 8))
                        Text(format(time: track.duration))
                    }
                    .font(.system(size: 11, weight: .regular))
                    .foregroundColor(.secondary.opacity(0.85))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(backgroundColor)
        )
        .contentShape(Rectangle())
        .onHover { inside in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = inside
            }
        }
    }
    
}
