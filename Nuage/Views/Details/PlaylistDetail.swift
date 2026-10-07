//
//  PlaylistDetail.swift
//  Nuage
//
//  Created by hdmi1519 on 03.10.2026.
//

import SwiftUI
import Combine
import SoundCloud

struct PlaylistDetail: View {
    
    @State var playlist: AnyPlaylist
    
    @State private var tracks: [Track] = []
    @State private var isLoadingTracks = false
    @State private var isHoveringArtwork = false
    @State private var isCopied = false
    @State private var isShowingDeleteAlert = false
    @State private var isShowingEditSheet = false
    
    @State private var editTitle = ""
    @State private var editDescription = ""
    @State private var editIsPublic = true
    @State private var isSavingEdit = false
    
    @State private var subscriptions = Set<AnyCancellable>()
    
    @EnvironmentObject private var player: StreamPlayer
    @Environment(\.playlists) private var playlists: [AnyPlaylist]
    @Environment(\.posts) private var posts: [Post]
    @Environment(\.toggleLikePlaylist) private var toggleLikePlaylist: (AnyPlaylist) -> () -> ()
    @Environment(\.toggleRepostPlaylist) private var toggleRepostPlaylist: (UserPlaylist) -> () -> ()
    @Environment(\.deletePlaylist) private var deletePlaylistAction: (UserPlaylist) -> ()
    @Environment(\.updateUserPlaylist) private var updateUserPlaylistAction: (UserPlaylist) -> ()
    @Environment(\.dismiss) private var dismiss
    
    private var isCurrentUserOwner: Bool {
        if let currentUserID = SoundCloud.shared.user?.id {
            if playlist.user.id == currentUserID { return true }
        }
        if let userP = playlist.userPlaylist, userP.secretToken != nil {
            return true
        }
        return false
    }
    
    private var isLiked: Bool {
        playlists.contains(where: { $0.id == playlist.id }) && !isCurrentUserOwner
    }
    
    private var isRepost: Bool {
        guard let userP = playlist.userPlaylist else { return false }
        return posts.filter { !$0.isTrack && $0.isRepost }
            .compactMap { $0.playlist }
            .contains(where: { $0.id == userP.id })
    }
    
    private var isPlayingThisPlaylist: Bool {
        guard player.isPlaying, let current = player.currentStream else { return false }
        return tracks.contains(current)
    }
    
    private var totalDuration: TimeInterval {
        TimeInterval(tracks.reduce(Float(0)) { $0 + $1.duration })
    }
    
    private func formattedTotalDuration(_ total: TimeInterval) -> String {
        let minutes = Int(total) / 60
        let hours = minutes / 60
        let remainingMinutes = minutes % 60
        if hours > 0 {
            return String(format: NSLocalizedString("duration.hoursMinutes", comment: ""), hours, remainingMinutes)
        } else {
            return String(format: NSLocalizedString("duration.minutes", comment: ""), minutes)
        }
    }
    
    private func playPlaylist(shuffled: Bool = false) {
        guard !tracks.isEmpty else { return }
        if shuffled {
            var queue = tracks.shuffled()
            player.play(queue, from: 0)
        } else {
            player.play(tracks, from: 0)
        }
    }
    
    private func togglePlay() {
        if isPlayingThisPlaylist {
            player.togglePlayback()
        } else {
            playPlaylist()
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
    
    private func removeTrackFromPlaylist(_ track: Track) {
        guard let userP = playlist.userPlaylist else { return }
        let currentIDs = tracks.map { $0.id }
        let newIDs = currentIDs.filter { $0 != track.id }.compactMap { Int($0) }
        
        withAnimation {
            tracks.removeAll { $0.id == track.id }
        }
        
        SoundCloud.shared.get(.set(userP, trackIDs: newIDs))
            .receive(on: RunLoop.main)
            .sink(receiveCompletion: { _ in }, receiveValue: { updated in
                self.playlist = .user(updated)
                self.updateUserPlaylistAction(updated)
            })
            .store(in: &subscriptions)
    }
    
    private func saveEdit() {
        guard let userP = playlist.userPlaylist, !editTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        isSavingEdit = true
        
        SoundCloud.shared.get(.updatePlaylist(id: userP.id, title: editTitle, description: editDescription, isPublic: editIsPublic))
            .receive(on: RunLoop.main)
            .sink(receiveCompletion: { completion in
                isSavingEdit = false
                if case let .failure(error) = completion {
                    print("Failed to update playlist: \(error)")
                }
            }, receiveValue: { updated in
                self.playlist = .user(updated)
                self.updateUserPlaylistAction(updated)
                self.isShowingEditSheet = false
                self.isSavingEdit = false
            })
            .store(in: &subscriptions)
    }
    
    private func deleteCurrentPlaylist() {
        guard let userP = playlist.userPlaylist else { return }
        deletePlaylistAction(userP)
        dismiss()
    }
    
    private func changeArtwork() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image, .jpeg, .png]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.title = NSLocalizedString("playlists.chooseArtwork", comment: "")
        if panel.runModal() == .OK, let url = panel.url, let data = try? Data(contentsOf: url), let target = playlist.userPlaylist {
            SoundCloud.shared.uploadPlaylistArtwork(id: target.id, imageData: data)
                .receive(on: RunLoop.main)
                .sink(receiveCompletion: { completion in
                    if case let .failure(error) = completion {
                        print("Failed to upload artwork: \(error)")
                    }
                }, receiveValue: { updated in
                    self.playlist = .user(updated)
                    self.updateUserPlaylistAction(updated)
                })
                .store(in: &subscriptions)
        }
    }
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                heroHeader
                
                if let description = playlist.description, !description.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(LocalizedStringKey("track.description.header"))
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(.secondary)
                        
                        Text(description.trimmingCharacters(in: .whitespacesAndNewlines).withAttributedLinks())
                            .font(.system(size: 13))
                            .foregroundColor(.primary.opacity(0.85))
                            .textSelection(.enabled)
                    }
                    .padding(.horizontal, 24)
                }
                
                Divider()
                    .padding(.horizontal, 24)
                
                tracksSection
            }
            .padding(.vertical, 24)
        }
        .navigationTitle(playlist.title)
        .task {
            loadTracks()
        }
        .sheet(isPresented: $isShowingEditSheet) {
            editPlaylistSheet
        }
        .alert(isPresented: $isShowingDeleteAlert) {
            Alert(
                title: Text(LocalizedStringKey("playlists.delete")),
                message: Text(LocalizedStringKey("playlists.deleteConfirm")),
                primaryButton: .destructive(Text(LocalizedStringKey("playlists.delete")), action: deleteCurrentPlaylist),
                secondaryButton: .cancel(Text(LocalizedStringKey("playlists.cancel")))
            )
        }
    }
    
    // MARK: - Hero Header
    
    @ViewBuilder
    private var heroHeader: some View {
        let artworkURL = playlist.artworkURL ?? tracks.first?.artworkURL
        
        HStack(alignment: .top, spacing: 24) {
            // Artwork with hover play overlay
            ZStack {
                RemoteImage(url: artworkURL, cornerRadius: 14)
                    .aspectRatio(1, contentMode: .fill)
                    .frame(width: 140, height: 140)
                    .shadow(color: Color.black.opacity(0.18), radius: 8, x: 0, y: 4)
                
                if isHoveringArtwork || isPlayingThisPlaylist {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color.black.opacity(isPlayingThisPlaylist ? 0.45 : 0.35))
                        .frame(width: 140, height: 140)
                    
                    Button(action: togglePlay) {
                        ZStack {
                            Circle()
                                .fill(Color(hex: 0xFF5500))
                                .frame(width: 48, height: 48)
                                .shadow(color: Color.black.opacity(0.3), radius: 4, x: 0, y: 2)
                            
                            Image(systemName: isPlayingThisPlaylist ? "pause.fill" : "play.fill")
                                .font(.system(size: 20, weight: .bold))
                                .foregroundColor(.white)
                                .offset(x: isPlayingThisPlaylist ? 0 : 2)
                        }
                    }
                    .buttonStyle(.plain)
                    .transition(.opacity)
                }
            }
            .frame(width: 140, height: 140)
            .onHover { inside in
                withAnimation(.easeInOut(duration: 0.15)) {
                    isHoveringArtwork = inside
                }
            }
            
            // Info Column
            VStack(alignment: .leading, spacing: 8) {
                // Badges Row
                HStack(spacing: 8) {
                    let badgeText = (playlist.userPlaylist?.isAlbum == true) ? "playlist.album" : "playlist.badge"
                    Text(LocalizedStringKey(badgeText))
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.secondary)
                    
                    if !playlist.isPublic {
                        HStack(spacing: 4) {
                            Image(systemName: "lock.fill")
                                .font(.system(size: 9))
                            Text(LocalizedStringKey("playlist.privateBadge"))
                                .font(.system(size: 10, weight: .semibold))
                        }
                        .foregroundColor(.orange)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            Capsule()
                                .fill(Color.orange.opacity(0.15))
                        )
                    }
                }
                
                Text(playlist.title)
                    .font(.system(size: 24, weight: .bold))
                    .lineLimit(2)
                    .foregroundColor(.primary)
                    .textSelection(.enabled)
                
                // Creator Row
                NavigationLink(value: playlist.user) {
                    HStack(spacing: 8) {
                        RemoteImage(url: playlist.user.avatarURL, cornerRadius: 10)
                            .frame(width: 22, height: 22)
                        Text(playlist.user.username)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.primary)
                    }
                }
                .buttonStyle(.plain)
                
                // Stats Ribbon
                HStack(spacing: 16) {
                    let count = tracks.count > 0 ? tracks.count : (playlist.trackIDs?.count ?? playlist.tracks?.count ?? 0)
                    HStack(spacing: 4) {
                        Image(systemName: "music.note")
                            .font(.system(size: 10))
                        Text("\(count) \(NSLocalizedString("playlists.tracksCount", comment: ""))")
                    }
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    
                    if totalDuration > 0 {
                        HStack(spacing: 4) {
                            Image(systemName: "clock")
                                .font(.system(size: 10))
                            Text(formattedTotalDuration(totalDuration))
                        }
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                    }
                    
                    if let userP = playlist.userPlaylist {
                        HStack(spacing: 4) {
                            Image(systemName: "calendar")
                                .font(.system(size: 10))
                            Text(userP.date.formatted(date: .abbreviated, time: .omitted))
                        }
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                    }
                }
                .padding(.top, 2)
                
                // Action Buttons Row
                HStack(spacing: 10) {
                    // Play All Button
                    Button {
                        playPlaylist(shuffled: false)
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "play.fill")
                                .font(.system(size: 12, weight: .bold))
                            Text(LocalizedStringKey("playlists.playAll"))
                                .font(.system(size: 13, weight: .semibold))
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 7)
                        .background(
                            Capsule()
                                .fill(Color(hex: 0xFF5500))
                        )
                    }
                    .buttonStyle(.plain)
                    
                    // Shuffle Button
                    Button {
                        playPlaylist(shuffled: true)
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "shuffle")
                                .font(.system(size: 12, weight: .semibold))
                            Text(LocalizedStringKey("playlists.shuffle"))
                                .font(.system(size: 13, weight: .medium))
                        }
                        .foregroundColor(.primary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .background(
                            Capsule()
                                .fill(Color(nsColor: .quaternaryLabelColor))
                        )
                        .overlay(
                            Capsule()
                                .stroke(Color(nsColor: .separatorColor).opacity(0.4), lineWidth: 0.5)
                        )
                    }
                    .buttonStyle(.plain)
                    
                    // Like Button (if not owner)
                    if !isCurrentUserOwner {
                        Button(action: toggleLikePlaylist(playlist)) {
                            Image(systemName: isLiked ? "heart.fill" : "heart")
                                .font(.system(size: 14))
                                .foregroundColor(isLiked ? Color(hex: 0xFF5500) : .primary)
                                .frame(width: 32, height: 32)
                                .background(
                                    Circle()
                                        .fill(Color(nsColor: .quaternaryLabelColor))
                                )
                                .overlay(
                                    Circle()
                                        .stroke(Color(nsColor: .separatorColor).opacity(0.4), lineWidth: 0.5)
                                )
                        }
                        .buttonStyle(.plain)
                        .help(LocalizedStringKey(isLiked ? "context.unlike" : "context.like"))
                    }
                    
                    // Repost Button (if user playlist)
                    if let userP = playlist.userPlaylist {
                        Button(action: toggleRepostPlaylist(userP)) {
                            Image(systemName: "arrow.2.squarepath")
                                .font(.system(size: 13))
                                .foregroundColor(isRepost ? Color(hex: 0xFF5500) : .primary)
                                .frame(width: 32, height: 32)
                                .background(
                                    Circle()
                                        .fill(Color(nsColor: .quaternaryLabelColor))
                                )
                                .overlay(
                                    Circle()
                                        .stroke(Color(nsColor: .separatorColor).opacity(0.4), lineWidth: 0.5)
                                )
                        }
                        .buttonStyle(.plain)
                        .help(LocalizedStringKey(isRepost ? "context.unrepost" : "context.repost"))
                    }
                    
                    // Copy Link Button
                    Button(action: copyLink) {
                        HStack(spacing: 4) {
                            Image(systemName: isCopied ? "checkmark" : "link")
                                .font(.system(size: 13))
                            if isCopied {
                                Text(LocalizedStringKey("track.copied"))
                                    .font(.system(size: 12, weight: .medium))
                            }
                        }
                        .foregroundColor(isCopied ? Color.green : .primary)
                        .frame(height: 32)
                        .padding(.horizontal, isCopied ? 10 : 8)
                        .background(
                            Capsule()
                                .fill(Color(nsColor: .quaternaryLabelColor))
                        )
                        .overlay(
                            Capsule()
                                .stroke(Color(nsColor: .separatorColor).opacity(0.4), lineWidth: 0.5)
                        )
                    }
                    .buttonStyle(.plain)
                    .help(LocalizedStringKey("track.copyLink"))
                    
                    // Share with Friend Button
                    Button {
                        NotificationCenter.default.post(name: .sharePlaylistToFriend, object: playlist)
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "paperplane")
                                .font(.system(size: 12))
                            Text(LocalizedStringKey("track.share"))
                                .font(.system(size: 12, weight: .medium))
                        }
                        .foregroundColor(.primary)
                        .frame(height: 32)
                        .padding(.horizontal, 10)
                        .background(
                            Capsule()
                                .fill(Color(nsColor: .quaternaryLabelColor))
                        )
                        .overlay(
                            Capsule()
                                .stroke(Color(nsColor: .separatorColor).opacity(0.4), lineWidth: 0.5)
                        )
                    }
                    .buttonStyle(.plain)
                    .help(NSLocalizedString("context.shareToFriend", comment: ""))
                    
                    // Owner Actions: Edit, Change Artwork & Delete
                    if isCurrentUserOwner, let userP = playlist.userPlaylist {
                        Button(action: changeArtwork) {
                            Image(systemName: "photo.badge.plus")
                                .font(.system(size: 13))
                                .foregroundColor(.primary)
                                .frame(width: 32, height: 32)
                                .background(
                                    Circle()
                                        .fill(Color(nsColor: .quaternaryLabelColor))
                                )
                                .overlay(
                                    Circle()
                                        .stroke(Color(nsColor: .separatorColor).opacity(0.4), lineWidth: 0.5)
                                )
                        }
                        .buttonStyle(.plain)
                        .help(LocalizedStringKey("playlists.chooseArtwork"))
                        
                        Button {
                            editTitle = userP.title
                            editDescription = userP.description ?? ""
                            editIsPublic = userP.isPublic
                            isShowingEditSheet = true
                        } label: {
                            Image(systemName: "pencil")
                                .font(.system(size: 13))
                                .foregroundColor(.primary)
                                .frame(width: 32, height: 32)
                                .background(
                                    Circle()
                                        .fill(Color(nsColor: .quaternaryLabelColor))
                                )
                                .overlay(
                                    Circle()
                                        .stroke(Color(nsColor: .separatorColor).opacity(0.4), lineWidth: 0.5)
                                )
                        }
                        .buttonStyle(.plain)
                        .help(LocalizedStringKey("playlists.edit"))
                        
                        Button {
                            isShowingDeleteAlert = true
                        } label: {
                            Image(systemName: "trash")
                                .font(.system(size: 13))
                                .foregroundColor(.red.opacity(0.85))
                                .frame(width: 32, height: 32)
                                .background(
                                    Circle()
                                        .fill(Color.red.opacity(0.1))
                                )
                                .overlay(
                                    Circle()
                                        .stroke(Color.red.opacity(0.2), lineWidth: 0.5)
                                )
                        }
                        .buttonStyle(.plain)
                        .help(LocalizedStringKey("playlists.delete"))
                    }
                }
                .padding(.top, 6)
            }
            
            Spacer()
        }
        .padding(.horizontal, 24)
    }
    
    // MARK: - Tracks Section
    
    @ViewBuilder
    private var tracksSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            if isLoadingTracks && tracks.isEmpty {
                HStack {
                    Spacer()
                    ProgressView()
                        .padding(40)
                    Spacer()
                }
            } else if tracks.isEmpty {
                HStack {
                    Spacer()
                    VStack(spacing: 8) {
                        Image(systemName: "music.note")
                            .font(.system(size: 32))
                            .foregroundColor(.secondary)
                        Text(LocalizedStringKey("playlists.empty"))
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.secondary)
                    }
                    .padding(40)
                    Spacer()
                }
            } else {
                ForEach(Array(tracks.enumerated()), id: \.element.id) { index, track in
                    HStack(spacing: 12) {
                        Text("\(index + 1)")
                            .font(.system(size: 12, weight: .medium, design: .monospaced))
                            .foregroundColor(.secondary)
                            .frame(width: 26, alignment: .trailing)
                        
                        TrackRow(track: track)
                            .playbackStart(at: track)
                            .trackContextMenu(with: track, onRemove: isCurrentUserOwner ? { removeTrackFromPlaylist(track) } : nil)
                    }
                }
                .playbackContext(tracks)
            }
        }
        .padding(.horizontal, 16)
    }
    
    // MARK: - Edit Sheet
    
    @ViewBuilder
    private var editPlaylistSheet: some View {
        VStack(spacing: 18) {
            Text(LocalizedStringKey("playlists.edit"))
                .font(.system(size: 16, weight: .bold))
            
            VStack(alignment: .leading, spacing: 6) {
                Text(LocalizedStringKey("playlists.namePlaceholder"))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.secondary)
                TextField(NSLocalizedString("playlists.namePlaceholder", comment: ""), text: $editTitle)
                    .textFieldStyle(.roundedBorder)
            }
            
            VStack(alignment: .leading, spacing: 6) {
                Text(LocalizedStringKey("playlists.descriptionPlaceholder"))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.secondary)
                TextEditor(text: $editDescription)
                    .frame(height: 70)
                    .padding(4)
                    .background(RoundedRectangle(cornerRadius: 6).stroke(Color(nsColor: .separatorColor), lineWidth: 0.5))
            }
            
            Toggle(LocalizedStringKey("playlists.public"), isOn: $editIsPublic)
                .toggleStyle(.checkbox)
                .frame(maxWidth: .infinity, alignment: .leading)
            
            HStack(spacing: 12) {
                Button(LocalizedStringKey("playlists.cancel")) {
                    isShowingEditSheet = false
                }
                .keyboardShortcut(.cancelAction)
                
                Spacer()
                
                Button(LocalizedStringKey("playlists.save")) {
                    saveEdit()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(editTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSavingEdit)
            }
            .padding(.top, 8)
        }
        .padding(20)
        .frame(width: 380)
    }
    
    // MARK: - Data Loading
    
    private func loadTracks() {
        if let directTracks = playlist.tracks, directTracks.count == (playlist.trackIDs?.count ?? directTracks.count), !directTracks.isEmpty {
            self.tracks = directTracks
            return
        }
        
        isLoadingTracks = true
        
        if let trackIDs = playlist.trackIDs, !trackIDs.isEmpty {
            SoundCloud.shared.get(.tracks(trackIDs))
                .receive(on: RunLoop.main)
                .sink(receiveCompletion: { _ in
                    self.isLoadingTracks = false
                }, receiveValue: { fetchedTracks in
                    self.tracks = fetchedTracks
                    self.isLoadingTracks = false
                })
                .store(in: &subscriptions)
            return
        }
        
        switch playlist {
        case .user(let userP):
            SoundCloud.shared.get(.userPlaylist(userP.id))
                .receive(on: RunLoop.main)
                .sink(receiveCompletion: { _ in
                    self.isLoadingTracks = false
                }, receiveValue: { fetchedPlaylist in
                    self.playlist = .user(fetchedPlaylist)
                    if let ids = fetchedPlaylist.trackIDs, !ids.isEmpty {
                        SoundCloud.shared.get(.tracks(ids))
                            .receive(on: RunLoop.main)
                            .sink(receiveCompletion: { _ in
                                self.isLoadingTracks = false
                            }, receiveValue: { fetchedTracks in
                                self.tracks = fetchedTracks
                                self.isLoadingTracks = false
                            })
                            .store(in: &subscriptions)
                    } else if let trks = fetchedPlaylist.tracks {
                        self.tracks = trks
                        self.isLoadingTracks = false
                    }
                })
                .store(in: &subscriptions)
            
        case .system(let sysP):
            SoundCloud.shared.get(.systemPlaylist(sysP.urn))
                .receive(on: RunLoop.main)
                .sink(receiveCompletion: { _ in
                    self.isLoadingTracks = false
                }, receiveValue: { fetchedPlaylist in
                    self.playlist = .system(fetchedPlaylist)
                    if let ids = fetchedPlaylist.trackIDs, !ids.isEmpty {
                        SoundCloud.shared.get(.tracks(ids))
                            .receive(on: RunLoop.main)
                            .sink(receiveCompletion: { _ in
                                self.isLoadingTracks = false
                            }, receiveValue: { fetchedTracks in
                                self.tracks = fetchedTracks
                                self.isLoadingTracks = false
                            })
                            .store(in: &subscriptions)
                    } else if let trks = fetchedPlaylist.tracks {
                        self.tracks = trks
                        self.isLoadingTracks = false
                    }
                })
                .store(in: &subscriptions)
        }
    }
}
