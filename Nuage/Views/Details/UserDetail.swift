//
//  UserDetail.swift
//  Nuage
//
//  Created by Laurin Brandner on 03.01.21.
//

import Foundation
import SwiftUI
import Combine
import SoundCloud

struct UserDetail: View {
    
    @State var user: User
    @State private var loadedUser: User?
    @State private var selection: Tab = .all
    @State private var subscriptions = Set<AnyCancellable>()
    
    // Follow State
    @State private var isFollowing = false
    @State private var isFollowHovered = false
    @State private var followerCount: Int?
    
    var body: some View {
        let currentUser = loadedUser ?? user
        let followers = followerCount ?? currentUser.followerCount ?? 0
        
        VStack(spacing: 0) {
            // Header Section
            HStack(alignment: .top, spacing: 18) {
                RemoteImage(url: currentUser.avatarURL, cornerRadius: 40)
                    .frame(width: 80, height: 80)
                    .clipShape(Circle())
                    .overlay(Circle().stroke(Color.white.opacity(0.12), lineWidth: 1))
                    .shadow(color: Color.black.opacity(0.18), radius: 6, x: 0, y: 2)
                
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .center, spacing: 12) {
                        Text(user.username)
                            .font(.system(size: 22, weight: .bold))
                            .foregroundColor(.primary)
                            .lineLimit(1)
                        
                        Spacer()
                        
                        // Action Buttons: Follow + Station
                        HStack(spacing: 8) {
                            if let myID = SoundCloud.shared.user?.id, myID != user.id {
                                Button(action: toggleFollow) {
                                    HStack(spacing: 5) {
                                        Image(systemName: isFollowing ? (isFollowHovered ? "xmark" : "checkmark") : "person.badge.plus")
                                            .font(.system(size: 11, weight: .bold))
                                        Text(isFollowing ? (isFollowHovered ? LocalizedStringKey("user.unfollow") : LocalizedStringKey("user.followingStatus")) : LocalizedStringKey("user.follow"))
                                            .font(.system(size: 12, weight: .semibold))
                                    }
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 5)
                                    .background(
                                        Capsule()
                                            .fill(isFollowing ? (isFollowHovered ? Color.red.opacity(0.15) : Color(nsColor: .quaternaryLabelColor)) : Color(hex: 0xFF5500))
                                    )
                                    .foregroundColor(isFollowing ? (isFollowHovered ? .red : .primary) : .white)
                                    .overlay(
                                        Capsule()
                                            .stroke(isFollowing ? (isFollowHovered ? Color.red.opacity(0.4) : Color.primary.opacity(0.15)) : Color.clear, lineWidth: 1)
                                    )
                                }
                                .buttonStyle(.plain)
                                .onHover { isFollowHovered = $0 }
                            }
                            
                            NavigationLink(value: Station.artist(user)) {
                                HStack(spacing: 5) {
                                    Image(systemName: "dot.radiowaves.left.and.right")
                                    Text(LocalizedStringKey("user.station"))
                                }
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.secondary)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(
                                    Capsule()
                                        .fill(Color(nsColor: .quaternaryLabelColor))
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    
                    if !currentUser.name.trimmingCharacters(in: .whitespaces).isEmpty && currentUser.name != currentUser.username {
                        Text(currentUser.name)
                            .font(.system(size: 12.5))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                    
                    HStack(spacing: 16) {
                        HStack(spacing: 5) {
                            Image(systemName: "person.2.fill")
                                .font(.system(size: 11))
                            Text("\(format(count: followers)) \(NSLocalizedString("user.followers", comment: ""))")
                        }
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.secondary)
                        
                        HStack(spacing: 5) {
                            Image(systemName: "person.fill.checkmark")
                                .font(.system(size: 11))
                            Text("\(format(count: currentUser.followingCount ?? 0)) \(NSLocalizedString("user.following", comment: ""))")
                        }
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.secondary)
                        
                        if let trackCount = currentUser.trackCount, trackCount > 0 {
                            HStack(spacing: 5) {
                                Image(systemName: "waveform")
                                    .font(.system(size: 11))
                                Text("\(format(count: trackCount)) \(NSLocalizedString("playlists.tracksCount", comment: ""))")
                            }
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.secondary)
                        }
                    }
                    .padding(.top, 2)
                    
                    if let description = currentUser.description, !description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text(description.withAttributedLinks())
                            .font(.system(size: 12))
                            .lineSpacing(2.5)
                            .foregroundColor(.secondary)
                            .lineLimit(3)
                            .padding(.top, 2)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            
            // Tab Selector
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    tabButton(for: .all, title: NSLocalizedString("user.all", comment: ""), icon: "square.stack")
                    tabButton(for: .popular, title: NSLocalizedString("user.popular", comment: ""), icon: "flame.fill")
                    tabButton(for: .tracks, title: NSLocalizedString("user.tracksTab", comment: ""), icon: "waveform")
                    tabButton(for: .albums, title: NSLocalizedString("user.albums", comment: ""), icon: "opticaldisc")
                    tabButton(for: .playlists, title: NSLocalizedString("playlists.title", comment: ""), icon: "music.note.list")
                    tabButton(for: .reposts, title: NSLocalizedString("sidebar.reposts", comment: ""), icon: "arrow.triangle.2.circlepath")
                    tabButton(for: .likes, title: NSLocalizedString("user.likes", comment: ""), icon: "heart.fill")
                    tabButton(for: .following, title: NSLocalizedString("sidebar.following", comment: ""), icon: "person.2")
                    tabButton(for: .followers, title: NSLocalizedString("user.followersTab", comment: ""), icon: "person.3")
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
            }
            
            Divider()

            stream(for: selection)
        }
        .navigationTitle(user.username)
        .onAppear {
            SoundCloud.shared.get(.user(with: user.id))
                .replaceError(with: user)
                .map { Optional($0) }
                .receive(on: RunLoop.main)
                .sink { loaded in
                    self.loadedUser = loaded
                    if let fc = loaded?.followerCount {
                        self.followerCount = fc
                    }
                }
                .store(in: &subscriptions)
            
            checkFollowingStatus()
        }
    }
    
    private func checkFollowingStatus() {
        guard let myUser = SoundCloud.shared.user, myUser.id != user.id, let targetIdInt = Int(user.id) else { return }
        SoundCloud.shared.get(.followingIDs(of: myUser))
            .receive(on: RunLoop.main)
            .sink(receiveCompletion: { _ in }, receiveValue: { page in
                isFollowing = page.collection.contains(targetIdInt)
            })
            .store(in: &subscriptions)
    }
    
    private func toggleFollow() {
        let willFollow = !isFollowing
        withAnimation(.easeInOut(duration: 0.15)) {
            isFollowing = willFollow
            if willFollow {
                followerCount = (followerCount ?? 0) + 1
            } else if let count = followerCount {
                followerCount = max(0, count - 1)
            }
        }
        let req = willFollow ? SoundCloud.shared.perform(.follow(user)) : SoundCloud.shared.perform(.unfollow(user))
        req.receive(on: RunLoop.main)
            .sink(receiveCompletion: { completion in
                if case .failure(let error) = completion {
                    withAnimation {
                        isFollowing = !willFollow
                        if willFollow {
                            followerCount = max(0, (followerCount ?? 1) - 1)
                        } else if let count = followerCount {
                            followerCount = count + 1
                        }
                    }
                    print("Follow toggle error: \(error)")
                }
            }, receiveValue: { _ in })
            .store(in: &subscriptions)
    }
    
    @ViewBuilder private func tabButton(for tab: Tab, title: String, icon: String) -> some View {
        Button(action: { withAnimation(.easeInOut(duration: 0.15)) { selection = tab } }) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 11))
                Text(title)
                    .font(.system(size: 12, weight: selection == tab ? .semibold : .regular))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .foregroundColor(selection == tab ? .white : .secondary)
            .background(
                Capsule()
                    .fill(selection == tab ? Color(hex: 0xFF5500) : Color.clear)
            )
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
    
    @ViewBuilder private func stream(for selection: Tab) -> some View {
        switch selection {
        case .all:
            PostList(for: SoundCloud.shared.get(.stream(of: user)))
        case .popular:
            TrackList(for: SoundCloud.shared.get(.userTopTracks(of: user)))
        case .tracks:
            TrackList(for: SoundCloud.shared.get(.userTracks(of: user)))
        case .albums:
            InfiniteList(publisher: .page(SoundCloud.shared.get(.userAlbums(of: user)))) { (playlist: UserPlaylist) in
                PlaylistRow(playlist: playlist)
            }
        case .playlists:
            InfiniteList(publisher: .page(SoundCloud.shared.get(.userPlaylists(of: user)))) { (playlist: UserPlaylist) in
                PlaylistRow(playlist: playlist)
            }
        case .reposts:
            PostList(for: SoundCloud.shared.get(.userReposts(of: user)))
        case .likes:
            TrackList(for: SoundCloud.shared.get(.trackLikes(of: user)))
        case .following:
            UserGrid(for: SoundCloud.shared.get(.followings(of: user)))
        case .followers:
            UserGrid(for: SoundCloud.shared.get(.followers(of: user)))
        }
    }
    
}

extension UserDetail {
    
    enum Tab: String, CaseIterable {
        case all
        case popular
        case tracks
        case albums
        case playlists
        case reposts
        case likes
        case following
        case followers
    }
    
}
