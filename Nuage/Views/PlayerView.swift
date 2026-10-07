//
//  PlayerView.swift
//  Nuage
//
//  Created by Laurin Brandner on 26.12.19.
//  Copyright © 2019 Laurin Brandner. All rights reserved.
//

import SwiftUI
import Combine
import SoundCloud

struct NoTrackError: Error {}

struct PlayerView: View {
    
    var onTrackDetailTap: () -> ()
    var onUserDetailTap: (User) -> ()
    var onStationTap: ((Station) -> ())? = nil
    @Binding var showingPanel: Bool
    @Binding var panelMode: NowPlayingMode
    var onPanelOpen: (() -> Void)? = nil
    
    @State private var showingQueue = false
    @State private var showingAddToPlaylist = false
    @State private var showingQuickComment = false
    @State private var quickCommentText = ""
    @State private var quickCommentAttachTimestamp = true
    @State private var isSubmittingQuickComment = false
    @State private var quickCommentSuccess = false
    @State private var isHoveringArtwork = false
    @State private var preMuteVolume: Float = 0.5
    @State private var subscriptions = Set<AnyCancellable>()
    @AppStorage("showTimedComments") private var showTimedComments: Bool = true
    @AppStorage("showCommentMarkersOnBar") private var showCommentMarkersOnBar: Bool = false
    @ObservedObject private var commentsService = TimedCommentsService.shared
    @ObservedObject private var equalizerService = EqualizerService.shared
    @ObservedObject private var voiceControlService = VoiceControlService.shared
    
    @EnvironmentObject private var player: StreamPlayer
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.playlists) private var playlists: [AnyPlaylist]
    @Environment(\.reloadPlaylists) private var reloadPlaylists: () -> ()
    @Environment(\.likes) private var likes: [Track]
    @Environment(\.posts) private var posts: [Post]
    @Environment(\.toggleLikeTrack) private var toggleLikeTrack: (Track) -> () -> ()
    @Environment(\.toggleRepostTrack) private var toggleRepostTrack: (Track) -> () -> ()
    
    private func isTrackLiked(_ track: Track) -> Bool {
        likes.contains(track)
    }
    
    private func isTrackReposted(_ track: Track) -> Bool {
        posts.filter { $0.isTrack && $0.isRepost }.compactMap { $0.tracks.first }.contains(track)
    }
    
    var body: some View {
        HStack(spacing: 16) {
            // 1. Left: Track Info & Artwork
            leftSection
                .frame(minWidth: 200, maxWidth: 330, alignment: .leading)
            
            Spacer()
            
            // 2. Center: Controls & Waveform / Timeline Scrubber
            centerSection
                .frame(maxWidth: 520)
            
            Spacer()
            
            // 3. Right: Utility Controls (Lyrics, Poster, Queue, Volume)
            rightSection
                .frame(minWidth: 200, alignment: .trailing)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .frame(height: 68)
        .background(.ultraThinMaterial)
        .onChange(of: player.currentStream) { track in
            if let track = track {
                GeniusLyricsService.shared.fetchLyrics(for: track)
                TimedCommentsService.shared.fetchComments(for: track)
            }
        }
        .onAppear {
            if let track = player.currentStream {
                GeniusLyricsService.shared.fetchLyrics(for: track)
                TimedCommentsService.shared.fetchComments(for: track)
            }
        }
    }
    
    // MARK: - Left Section
    
    private var leftSection: some View {
        HStack(spacing: 10) {
            // Artwork with hover expand indicator
            ZStack {
                if let track = player.currentStream {
                    let url = track.artworkURL ?? track.user.avatarURL
                    RemoteImage(url: url, cornerRadius: 8)
                        .frame(width: 48, height: 48)
                        .shadow(color: Color.black.opacity(0.18), radius: 4, x: 0, y: 2)
                    
                    if isHoveringArtwork {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.black.opacity(0.4))
                            .frame(width: 48, height: 48)
                        
                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(.white)
                    }
                } else {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.secondary.opacity(0.15))
                        .frame(width: 48, height: 48)
                }
            }
            .contentShape(Rectangle())
            .onHover { isHoveringArtwork = $0 }
            .onTapGesture {
                if showingPanel && panelMode == .poster {
                    showingPanel = false
                } else {
                    panelMode = .poster
                    showingPanel = true
                }
            }
            .help(NSLocalizedString("player.openPoster", comment: ""))
            
            // Track Info
            if let track = player.currentStream {
                VStack(alignment: .leading, spacing: 3) {
                    Button(action: onTrackDetailTap) {
                        Text(track.title)
                            .font(.system(size: 13, weight: .semibold))
                            .lineLimit(1)
                            .foregroundColor(.primary)
                    }
                    .buttonStyle(.plain)
                    
                    Button(action: { onUserDetailTap(track.user) }) {
                        Text(track.user.username)
                            .font(.system(size: 11.5))
                            .lineLimit(1)
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                
                HStack(spacing: 12) {
                    // Like Button
                    Button(action: { toggleLikeTrack(track)() }) {
                        Image(systemName: isTrackLiked(track) ? "heart.fill" : "heart")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(isTrackLiked(track) ? Color(hex: 0xFF5500) : .secondary)
                            .frame(width: 20, height: 20)
                    }
                    .buttonStyle(.plain)
                    .help(isTrackLiked(track) ? NSLocalizedString("context.unlike", comment: "") : NSLocalizedString("player.like", comment: ""))
                    
                    // Repost Button
                    Button(action: { toggleRepostTrack(track)() }) {
                        Image(systemName: isTrackReposted(track) ? "arrow.triangle.2.circlepath.circle.fill" : "arrow.triangle.2.circlepath")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(isTrackReposted(track) ? Color(hex: 0xFF5500) : .secondary)
                            .frame(width: 20, height: 20)
                    }
                    .buttonStyle(.plain)
                    .help(isTrackReposted(track) ? NSLocalizedString("context.unrepost", comment: "") : NSLocalizedString("player.repost", comment: ""))
                    
                    // Station / Radio Button
                    Button(action: { onStationTap?(Station.track(track)) }) {
                        Image(systemName: "dot.radiowaves.left.and.right")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.secondary)
                            .frame(width: 20, height: 20)
                    }
                    .buttonStyle(.plain)
                    .help(LocalizedStringKey("context.startStation"))
                    
                    // Quick Comment Button
                    Button(action: { showingQuickComment.toggle() }) {
                        Image(systemName: "bubble.left")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(showingQuickComment ? Color(hex: 0xFF5500) : .secondary)
                            .frame(width: 20, height: 20)
                    }
                    .buttonStyle(.plain)
                    .popover(isPresented: $showingQuickComment) {
                        quickCommentPopover(track: track)
                    }
                    .contextMenu {
                        Toggle(LocalizedStringKey("player.timedComments"), isOn: $showTimedComments)
                        if showTimedComments {
                            Toggle(LocalizedStringKey("player.commentMarkers"), isOn: $showCommentMarkersOnBar)
                        }
                    }
                    .help(NSLocalizedString("player.leaveComment", comment: ""))
                    
                    // Share to Friend Button
                    Button(action: {
                        NotificationCenter.default.post(name: .shareTrackToFriend, object: track)
                    }) {
                        Image(systemName: "paperplane")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.secondary)
                            .frame(width: 20, height: 20)
                    }
                    .buttonStyle(.plain)
                    .help(NSLocalizedString("player.shareWithFriend", comment: ""))
                }
                .fixedSize()
                .padding(.leading, 2)
            }
        }
    }
    
    // MARK: - Center Section
    
    @ViewBuilder private var centerSection: some View {
        let activeComment = commentsService.hoveredComment ?? commentsService.activeComment(at: player.progress, window: 3.5)
        
        VStack(spacing: 4) {
            // Controls row
            HStack(spacing: 20) {
                // Shuffle
                Button(action: { player.shuffleQueue.toggle() }) {
                    Image(systemName: "shuffle")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(player.shuffleQueue ? Color(hex: 0xFF5500) : .secondary)
                }
                .buttonStyle(.plain)
                .help(NSLocalizedString("menu.shuffle", comment: ""))
                
                // Backward
                Button(action: player.advanceBackward) {
                    Image(systemName: "backward.fill")
                        .font(.system(size: 13))
                        .foregroundColor(.primary)
                }
                .buttonStyle(.plain)
                
                // Play / Pause Circle Button
                Button(action: player.togglePlayback) {
                    ZStack {
                        Circle()
                            .fill(Color(hex: 0xFF5500))
                            .frame(width: 32, height: 32)
                            .shadow(color: Color(hex: 0xFF5500).opacity(0.35), radius: 4, x: 0, y: 1.5)
                        
                        Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(.white)
                            .offset(x: player.isPlaying ? 0 : 1)
                    }
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.space, modifiers: [])
                
                // Forward
                Button(action: player.advanceForward) {
                    Image(systemName: "forward.fill")
                        .font(.system(size: 13))
                        .foregroundColor(.primary)
                }
                .buttonStyle(.plain)
                
                // Repeat (3-state: off -> all -> one)
                Button(action: player.toggleRepeatMode) {
                    Image(systemName: repeatIconName)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(player.repeatMode != .off ? Color(hex: 0xFF5500) : .secondary)
                }
                .buttonStyle(.plain)
                .help(repeatTooltip)
            }
            
            // Progress Bar (Clean Apple Music style, no waveform)
            progressSlider()
        }
        .overlay(alignment: .top) {
            if voiceControlService.showVoiceHUD && voiceControlService.isShowingHUD, let text = voiceControlService.currentHUDText {
                HStack(alignment: .center, spacing: 8) {
                    Image(systemName: voiceControlService.currentHUDIcon)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(Color(hex: 0xFF5500))
                    
                    Text(text)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.primary)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(
                    Capsule()
                        .fill(Color(nsColor: .windowBackgroundColor).opacity(0.96))
                        .shadow(color: Color.black.opacity(0.35), radius: 8, x: 0, y: 4)
                )
                .overlay(
                    Capsule()
                        .stroke(Color.primary.opacity(0.18), lineWidth: 1)
                )
                .offset(y: -58)
                .transition(.asymmetric(
                    insertion: .scale(scale: 0.9).combined(with: .opacity).combined(with: .offset(y: 4)),
                    removal: .opacity.combined(with: .scale(scale: 0.95))
                ))
            } else if showTimedComments, let comment = activeComment {
                CommentCapsuleView(comment: comment, onSeek: {
                    player.progress = comment.timestamp
                })
                .offset(y: -58)
                .transition(.asymmetric(
                    insertion: .scale(scale: 0.9).combined(with: .opacity).combined(with: .offset(y: 4)),
                    removal: .opacity.combined(with: .scale(scale: 0.95))
                ))
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: voiceControlService.isShowingHUD)
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: activeComment?.id)
    }
    
    // MARK: - Right Section
    
    private var rightSection: some View {
        HStack(spacing: 12) {
            // Voice Control Button
            Button(action: {
                voiceControlService.toggle()
            }) {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: voiceControlService.isEnabled ? "mic.fill" : "mic.slash")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(voiceControlService.isListening ? Color.green : (voiceControlService.isEnabled ? Color(hex: 0xFF5500) : .secondary))
                        .frame(width: 20, height: 20)
                    
                    if voiceControlService.isListening {
                        Circle()
                            .fill(Color.green)
                            .frame(width: 5, height: 5)
                            .offset(x: 1, y: -1)
                    }
                }
            }
            .buttonStyle(.plain)
            .contextMenu {
                Button(voiceControlService.isEnabled ? LocalizedStringKey("voice.disable") : LocalizedStringKey("voice.enable")) {
                    voiceControlService.toggle()
                }
                Divider()
                Menu(LocalizedStringKey("voice.microphone")) {
                    Button(action: {
                        voiceControlService.selectedDeviceID = "default"
                    }) {
                        HStack {
                            Text(LocalizedStringKey("voice.defaultSystem"))
                            if voiceControlService.selectedDeviceID == "default" {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                    Divider()
                    ForEach(voiceControlService.availableDevices) { dev in
                        Button(action: {
                            voiceControlService.selectedDeviceID = dev.id
                        }) {
                            HStack {
                                Text(dev.name + (dev.isBuiltIn ? " (\(NSLocalizedString("voice.defaultSystem", comment: "")))" : ""))
                                if voiceControlService.selectedDeviceID == dev.id {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                }
                Divider()
                Button(LocalizedStringKey("voice.settings")) {
                    NotificationCenter.default.post(name: .openVoiceControlSettings, object: nil)
                }
            }
            .help(voiceControlService.isEnabled ? NSLocalizedString("voice.disable", comment: "") : NSLocalizedString("voice.enable", comment: ""))
            
            // Lyrics Button (Genius)
            Button(action: {
                if showingPanel && panelMode == .lyrics {
                    showingPanel = false
                } else {
                    onPanelOpen?()
                    panelMode = .lyrics
                    showingPanel = true
                }
            }) {
                Image(systemName: "quote.bubble.fill")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(showingPanel && panelMode == .lyrics ? Color(hex: 0xFF5500) : .secondary)
                    .frame(width: 20, height: 20)
            }
            .buttonStyle(.plain)
            .help(NSLocalizedString("player.lyricsGenius", comment: ""))
            
            // Poster Mode Button
            Button(action: {
                if showingPanel && panelMode == .poster {
                    showingPanel = false
                } else {
                    onPanelOpen?()
                    panelMode = .poster
                    showingPanel = true
                }
            }) {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(showingPanel && panelMode == .poster ? Color(hex: 0xFF5500) : .secondary)
                    .frame(width: 20, height: 20)
            }
            .buttonStyle(.plain)
            .help(NSLocalizedString("player.posterMode", comment: ""))
            
            // Add to Playlist Button
            if let currentTrack = player.currentStream {
                let myPlaylists = playlists.compactMap { $0.userPlaylist }
                    .filter { $0.user.id == SoundCloud.shared.user?.id }
                if !myPlaylists.isEmpty {
                    Button(action: { showingAddToPlaylist.toggle() }) {
                        Image(systemName: "text.badge.plus")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(showingAddToPlaylist ? Color(hex: 0xFF5500) : .secondary)
                            .frame(width: 20, height: 20)
                    }
                    .buttonStyle(.plain)
                    .popover(isPresented: $showingAddToPlaylist) {
                        addToPlaylistPopover(track: currentTrack, myPlaylists: myPlaylists)
                    }
                    .help(NSLocalizedString("context.addToPlaylist", comment: ""))
                }
            }
            
            // Queue Button
            Button(action: { showingQueue.toggle() }) {
                Image(systemName: "list.bullet")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(showingQueue ? Color(hex: 0xFF5500) : .secondary)
                    .frame(width: 20, height: 20)
            }
            .buttonStyle(.plain)
            .popover(isPresented: $showingQueue, content: queue)
            .help(NSLocalizedString("queue.title", comment: ""))

            // Equalizer Button
            Button(action: { equalizerService.isShowingEqualizer.toggle() }) {
                Image(systemName: "slider.vertical.3")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(equalizerService.isShowingEqualizer ? Color(hex: 0xFF5500) : (equalizerService.isEnabled ? Color(hex: 0xFF5500) : .secondary))
                    .frame(width: 20, height: 20)
            }
            .buttonStyle(.plain)
            .popover(isPresented: $equalizerService.isShowingEqualizer) {
                EqualizerView()
            }
            .help(LocalizedStringKey("equalizer.title"))
            
            // Volume
            HStack(spacing: 6) {
                Button(action: toggleMute) {
                    Image(systemName: volumeIconName)
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .frame(width: 16, height: 20)
                }
                .buttonStyle(.plain)
                .help(LocalizedStringKey(player.volume == 0 ? "player.unmute" : "player.mute"))
                
                Slider(value: $player.volume, in: 0...1)
                    .frame(width: 80)
                    .controlSize(.mini)
                    .tint(Color(hex: 0xFF5500))
                    .accentColor(Color(hex: 0xFF5500))
            }
        }
    }
    
    private var volumeIconName: String {
        if player.volume == 0 {
            return "speaker.slash.fill"
        } else if player.volume < 0.33 {
            return "speaker.fill"
        } else if player.volume < 0.66 {
            return "speaker.wave.1.fill"
        } else {
            return "speaker.wave.2.fill"
        }
    }
    
    private func toggleMute() {
        if player.volume > 0 {
            preMuteVolume = player.volume
            player.volume = 0
        } else {
            player.volume = preMuteVolume > 0 ? preMuteVolume : 0.5
        }
    }
    
    private var repeatIconName: String {
        switch player.repeatMode {
        case .off, .all: return "repeat"
        case .one: return "repeat.1"
        }
    }
    
    private var repeatTooltip: LocalizedStringKey {
        switch player.repeatMode {
        case .off: return LocalizedStringKey("player.repeatOff")
        case .all: return LocalizedStringKey("player.repeatAll")
        case .one: return LocalizedStringKey("player.repeatOne")
        }
    }
    
    @ViewBuilder private func progressSlider() -> some View {
        let duration = TimeInterval(player.currentStream?.duration ?? 0)
        ModernProgressBar(value: $player.progress, duration: duration, showCommentMarkers: showCommentMarkersOnBar)
            .contextMenu {
                Toggle(LocalizedStringKey("player.timedComments"), isOn: $showTimedComments)
                if showTimedComments {
                    Toggle(LocalizedStringKey("player.commentMarkers"), isOn: $showCommentMarkersOnBar)
                }
            }
            .onTapGesture(count: 2) {
                if showingPanel {
                    showingPanel = false
                } else {
                    panelMode = .lyrics
                    showingPanel = true
                }
            }
    }
    
    @ViewBuilder private func queue() -> some View {
        let tracks = player.playbackQueue
        let currentIndex = player.currentStreamIndex ?? 0
        
        VStack(spacing: 0) {
            // Queue Header
            HStack(alignment: .center, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(LocalizedStringKey("queue.title"))
                        .font(.system(size: 13.5, weight: .bold))
                    
                    Text("\(tracks.count) \(NSLocalizedString("playlists.tracksCount", comment: ""))")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                if player.shuffleQueue {
                    HStack(spacing: 4) {
                        Image(systemName: "shuffle")
                            .font(.system(size: 10, weight: .semibold))
                        Text(LocalizedStringKey("queue.shuffled"))
                            .font(.system(size: 10.5, weight: .medium))
                    }
                    .foregroundColor(Color(hex: 0xFF5500))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(Color(hex: 0xFF5500).opacity(0.12)))
                }
                
                if currentIndex + 1 < tracks.count {
                    Button(LocalizedStringKey("queue.clearUpcoming")) {
                        withAnimation {
                            player.clearUpcomingQueue()
                        }
                    }
                    .font(.system(size: 11.5, weight: .medium))
                    .buttonStyle(.plain)
                    .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 12)
            .padding(.bottom, 10)
            
            Divider()
            
            if tracks.isEmpty {
                VStack(spacing: 8) {
                    Spacer()
                    Image(systemName: "music.note.list")
                        .font(.system(size: 28))
                        .foregroundColor(.secondary)
                    Text(LocalizedStringKey("queue.empty"))
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView(.vertical, showsIndicators: true) {
                    VStack(alignment: .leading, spacing: 12) {
                        // 1. History (if any)
                        let historyCount = min(max(0, currentIndex), tracks.count)
                        if historyCount > 0 {
                            DisclosureGroup {
                                VStack(spacing: 2) {
                                    ForEach(0..<historyCount, id: \.self) { idx in
                                        QueueTrackRow(
                                            track: tracks[idx],
                                            isCurrent: false,
                                            isPlaying: false,
                                            indexNumber: idx + 1,
                                            onTap: {
                                                player.playTrackInQueue(atPlaybackIndex: idx)
                                            },
                                            onDelete: {
                                                withAnimation {
                                                    player.removeFromQueue(atPlaybackIndex: idx)
                                                }
                                            }
                                        )
                                    }
                                }
                                .padding(.top, 4)
                            } label: {
                                HStack {
                                    Text(LocalizedStringKey("queue.previous"))
                                        .font(.system(size: 11.5, weight: .semibold))
                                        .foregroundColor(.secondary)
                                    Text("(\(historyCount))")
                                        .font(.system(size: 11))
                                        .foregroundColor(.secondary)
                                }
                            }
                            .padding(.horizontal, 12)
                            .padding(.top, 8)
                        }
                        
                        // 2. Now Playing
                        if currentIndex >= 0 && currentIndex < tracks.count {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(LocalizedStringKey("queue.nowPlaying"))
                                    .font(.system(size: 11.5, weight: .semibold))
                                    .foregroundColor(.secondary)
                                    .padding(.horizontal, 12)
                                
                                QueueTrackRow(
                                    track: tracks[currentIndex],
                                    isCurrent: true,
                                    isPlaying: player.isPlaying,
                                    indexNumber: nil,
                                    onTap: {
                                        player.togglePlayback()
                                    },
                                    onDelete: nil
                                )
                                .padding(.horizontal, 8)
                            }
                            .padding(.top, currentIndex == 0 ? 8 : 0)
                        }
                        
                        // 3. Up Next
                        let nextIndex = currentIndex + 1
                        if nextIndex >= 0 && nextIndex < tracks.count {
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Text(LocalizedStringKey("queue.upNext"))
                                        .font(.system(size: 11.5, weight: .semibold))
                                        .foregroundColor(.secondary)
                                    Text("(\(tracks.count - nextIndex))")
                                        .font(.system(size: 11))
                                        .foregroundColor(.secondary)
                                }
                                .padding(.horizontal, 12)
                                
                                VStack(spacing: 2) {
                                    ForEach(nextIndex..<tracks.count, id: \.self) { idx in
                                        QueueTrackRow(
                                            track: tracks[idx],
                                            isCurrent: false,
                                            isPlaying: false,
                                            indexNumber: idx - currentIndex,
                                            onTap: {
                                                player.playTrackInQueue(atPlaybackIndex: idx)
                                            },
                                            onDelete: {
                                                withAnimation {
                                                    player.removeFromQueue(atPlaybackIndex: idx)
                                                }
                                            }
                                        )
                                    }
                                }
                                .padding(.horizontal, 8)
                            }
                        }
                    }
                    .padding(.vertical, 8)
                }
            }
        }
        .frame(width: 350, height: 450)
        .background(.ultraThinMaterial)
    }
    
    @ViewBuilder private func addToPlaylistPopover(track: Track, myPlaylists: [UserPlaylist]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(LocalizedStringKey("context.addToPlaylist"))
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.secondary)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
            
            Divider()
            
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(myPlaylists, id: \.id) { playlist in
                        Button {
                            guard let newTrackID = Int(track.id) else { return }
                            SoundCloud.shared.get(.userPlaylist(playlist.id))
                                .map { ($0.trackIDs ?? []).compactMap { Int($0) } }
                                .flatMap { SoundCloud.shared.get(.set(playlist, trackIDs: $0 + [newTrackID])) }
                                .receive(on: RunLoop.main)
                                .sink(receiveCompletion: { _ in }, receiveValue: { _ in
                                    reloadPlaylists()
                                })
                                .store(in: &subscriptions)
                            showingAddToPlaylist = false
                        } label: {
                            HStack(spacing: 10) {
                                RemoteImage(url: playlist.artworkURL ?? playlist.tracks?.first?.artworkURL, cornerRadius: 4)
                                    .frame(width: 36, height: 36)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(playlist.title)
                                        .font(.system(size: 13, weight: .medium))
                                        .foregroundColor(.primary)
                                        .lineLimit(1)
                                    Text("\(playlist.trackCount ?? playlist.trackIDs?.count ?? 0) \(NSLocalizedString("playlists.tracksCount", comment: ""))")
                                        .font(.system(size: 11))
                                        .foregroundColor(.secondary)
                                }
                                Spacer()
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 7)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .frame(maxHeight: 300)
        }
        .frame(width: 280)
    }
    
    @ViewBuilder
    private func quickCommentPopover(track: Track) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack(spacing: 10) {
                RemoteImage(url: track.artworkURL ?? track.user.avatarURL, cornerRadius: 6)
                    .frame(width: 34, height: 34)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(track.title)
                        .font(.system(size: 12.5, weight: .semibold))
                        .lineLimit(1)
                    Text(track.user.username)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                
                Spacer()
            }
            
            // Timestamp toggle
            Button {
                withAnimation(.easeInOut(duration: 0.15)) {
                    quickCommentAttachTimestamp.toggle()
                }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: quickCommentAttachTimestamp ? "clock.fill" : "clock")
                        .font(.system(size: 10))
                    if quickCommentAttachTimestamp {
                        Text(String(format: NSLocalizedString("player.commentAtTime", comment: ""), format(time: player.progress)))
                            .font(.system(size: 11, weight: .medium))
                    } else {
                        Text(LocalizedStringKey("player.commentNoTime"))
                            .font(.system(size: 11, weight: .medium))
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    Capsule()
                        .fill(quickCommentAttachTimestamp ? Color(hex: 0xFF5500) : Color.primary.opacity(0.08))
                )
                .foregroundColor(quickCommentAttachTimestamp ? .white : .secondary)
            }
            .buttonStyle(.plain)
            
            // Input field
            HStack(spacing: 8) {
                TextField(LocalizedStringKey("player.yourCommentPlaceholder"), text: $quickCommentText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .onSubmit {
                        submitQuickComment(track: track)
                    }
                
                if quickCommentSuccess {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 15))
                        .foregroundColor(.green)
                } else if isSubmittingQuickComment {
                    ProgressView()
                        .scaleEffect(0.6)
                        .frame(width: 20, height: 20)
                } else {
                    Button(action: { submitQuickComment(track: track) }) {
                        Image(systemName: "paperplane.fill")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(quickCommentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? .secondary.opacity(0.4) : Color(hex: 0xFF5500))
                    }
                    .buttonStyle(.plain)
                    .disabled(quickCommentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color.primary.opacity(0.12), lineWidth: 0.8)
            )
        }
        .padding(14)
        .frame(width: 290)
    }
    
    private func submitQuickComment(track: Track) {
        let text = quickCommentText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isSubmittingQuickComment else { return }
        
        isSubmittingQuickComment = true
        let timestamp: TimeInterval? = quickCommentAttachTimestamp ? player.progress : nil
        
        SoundCloud.shared.get(.comment(text, at: timestamp, on: track))
            .receive(on: RunLoop.main)
            .sink(receiveCompletion: { completion in
                isSubmittingQuickComment = false
            }, receiveValue: { newComment in
                isSubmittingQuickComment = false
                quickCommentSuccess = true
                quickCommentText = ""
                TimedCommentsService.shared.addComment(newComment)
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                    quickCommentSuccess = false
                    showingQuickComment = false
                }
            })
            .store(in: &subscriptions)
    }
}

struct QueueTrackRow: View {
    let track: Track
    let isCurrent: Bool
    let isPlaying: Bool
    let indexNumber: Int?
    let onTap: () -> Void
    let onDelete: (() -> Void)?
    
    @State private var isHovered = false
    
    var body: some View {
        HStack(spacing: 9) {
            // Number / Equalizer indicator
            ZStack {
                if isCurrent {
                    Image(systemName: isPlaying ? "speaker.wave.2.fill" : "speaker.fill")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(Color(hex: 0xFF5500))
                } else if let num = indexNumber {
                    Text("\(num)")
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundColor(.secondary)
                }
            }
            .frame(width: 18, alignment: .center)
            
            // Artwork
            RemoteImage(url: track.artworkURL ?? track.user.avatarURL, cornerRadius: 6)
                .frame(width: 36, height: 36)
                .shadow(color: Color.black.opacity(0.12), radius: 2, x: 0, y: 1)
            
            // Title & Artist
            VStack(alignment: .leading, spacing: 2) {
                Text(track.title)
                    .font(.system(size: 12.5, weight: isCurrent ? .semibold : .medium))
                    .foregroundColor(isCurrent ? Color(hex: 0xFF5500) : .primary)
                    .lineLimit(1)
                
                Text(track.user.username)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            
            Spacer()
            
            // Duration or Delete button on hover
            if isHovered, let onDelete = onDelete {
                Button(action: onDelete) {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(.secondary)
                        .frame(width: 20, height: 20)
                        .background(Circle().fill(Color.primary.opacity(0.08)))
                }
                .buttonStyle(.plain)
                .help(NSLocalizedString("queue.removeFromQueue", comment: ""))
            } else {
                Text(format(time: track.duration))
                    .font(.system(size: 11, design: .rounded))
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isHovered ? Color.primary.opacity(0.06) : (isCurrent ? Color(hex: 0xFF5500).opacity(0.08) : Color.clear))
        )
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .onTapGesture(perform: onTap)
    }
}
