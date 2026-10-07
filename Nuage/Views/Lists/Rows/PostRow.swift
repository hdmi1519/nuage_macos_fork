//
//  PostRow.swift
//  Nuage
//
//  Created by Laurin Brandner on 26.07.23.
//

import SwiftUI
import Combine
import SoundCloud

struct PostRow: View {
    
    var post: Post
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if post.isRepost {
                NavigationLink(value: post.user) {
                    HStack(spacing: 6) {
                        RemoteImage(url: post.user.avatarURL, cornerRadius: 10)
                            .frame(width: 20, height: 20)
                        
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.secondary)
                        
                        Text(post.user.username)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.primary)
                        
                        Text(LocalizedStringKey("post.reposted"))
                            .font(.system(size: 12, weight: .regular))
                            .foregroundColor(.secondary)
                    }
                }
                .buttonStyle(.plain)
                .padding(.leading, 8)
                .padding(.top, 4)
            }
            
            if case let .track(track) = post.item {
                TrackRow(track: track)
                    .trackContextMenu(with: track)
            }
            else if case let .playlist(playlist) = post.item {
                PlaylistRow(playlist: playlist)
            }
        }
    }
    
}
