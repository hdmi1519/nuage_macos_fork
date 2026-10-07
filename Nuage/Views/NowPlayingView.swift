//
//  NowPlayingView.swift
//  Nuage
//
//  Created on 03.10.2026.
//

import SwiftUI
import SoundCloud
import Introspect

public enum NowPlayingMode: String, CaseIterable, Identifiable {
    case lyrics = "lyrics"
    case poster = "poster"
    
    public var id: String { rawValue }
    
    public var title: LocalizedStringKey {
        switch self {
        case .lyrics: return LocalizedStringKey("lyrics.title")
        case .poster: return LocalizedStringKey("poster.title")
        }
    }
}

struct ClosePanelButton: View {
    var action: () -> Void
    @State private var isHovered = false
    
    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark")
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(isHovered ? .primary : .secondary)
                .frame(width: 24, height: 24)
                .background(
                    Circle()
                        .fill(isHovered ? Color.primary.opacity(0.12) : Color.primary.opacity(0.06))
                )
        }
        .buttonStyle(.plain)
        .help(LocalizedStringKey("panel.close"))
        .onHover { isHovered = $0 }
    }
}

public struct NowPlayingPanel: View {
    @Binding var isPresented: Bool
    @Binding var mode: NowPlayingMode
    @Binding var inspectedTrack: Track?
    var onTrackTap: ((Track) -> Void)?
    var onUserTap: ((User) -> Void)?
    
    @EnvironmentObject private var player: StreamPlayer
    @Environment(\.likes) private var likes: [Track]
    @Environment(\.posts) private var posts: [Post]
    @Environment(\.toggleLikeTrack) private var toggleLikeTrack: (Track) -> () -> ()
    @Environment(\.toggleRepostTrack) private var toggleRepostTrack: (Track) -> () -> ()
    
    @StateObject private var lyricsService = GeniusLyricsService.shared
    @State private var isHoveringArtwork = false
    
    public init(
        isPresented: Binding<Bool>,
        mode: Binding<NowPlayingMode>,
        inspectedTrack: Binding<Track?> = .constant(nil),
        onTrackTap: ((Track) -> Void)? = nil,
        onUserTap: ((User) -> Void)? = nil
    ) {
        self._isPresented = isPresented
        self._mode = mode
        self._inspectedTrack = inspectedTrack
        self.onTrackTap = onTrackTap
        self.onUserTap = onUserTap
    }
    
    private var track: Track? {
        inspectedTrack ?? player.currentStream
    }
    
    private var isLiked: Bool {
        guard let track = track else { return false }
        return likes.contains(track)
    }
    
    private var isRepost: Bool {
        guard let track = track else { return false }
        return posts.filter { $0.isTrack && $0.isRepost }
            .compactMap { $0.tracks.first }
            .contains(track)
    }
    
    @State private var showingTranslation: Bool = false
    
    private var activeLyrics: String? {
        if showingTranslation, let trans = lyricsService.translatedLyrics {
            return trans
        }
        return lyricsService.lyrics
    }
    
    private var activeSongInfo: GeniusSongInfo? {
        if showingTranslation, let trans = lyricsService.translatedSongInfo {
            return trans
        }
        return lyricsService.songInfo
    }
    
    // MARK: - Inspection state
    
    private var isInspectingNonPlayingTrack: Bool {
        guard let inspected = inspectedTrack,
              let current = player.currentStream else {
            return false
        }
        return inspected.id != current.id
    }
    
    // MARK: - Return to Now Playing Bar (when inspecting non-playing track)
    
    @ViewBuilder
    private var returnToNowPlayingBar: some View {
        if isInspectingNonPlayingTrack, let current = player.currentStream {
            HStack(spacing: 8) {
                Button {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        inspectedTrack = nil
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 10, weight: .bold))
                        Text(LocalizedStringKey("panel.returnToPlaying"))
                            .font(.system(size: 11, weight: .semibold))
                            .lineLimit(1)
                            .layoutPriority(1)
                        Text("•")
                            .font(.system(size: 9))
                            .opacity(0.6)
                        Text(current.title)
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                        Spacer(minLength: 0)
                    }
                    .foregroundColor(Color(hex: 0xFF5500))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(hex: 0xFF5500).opacity(0.12))
                    .cornerRadius(6)
                }
                .buttonStyle(.plain)
                .help(current.title)
                
                ClosePanelButton {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isPresented = false
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 6)
        }
    }
    
    public var body: some View {
        VStack(spacing: 0) {
            returnToNowPlayingBar
            
            // Content
            if mode == .lyrics {
                lyricsView
            } else {
                posterView
            }
        }
        .frame(width: 320)
        .background(.ultraThinMaterial, ignoresSafeAreaEdges: [])
        .onAppear {
            if let track = track {
                lyricsService.fetchLyrics(for: track)
            }
        }
        .onChange(of: track?.id) { _ in
            showingTranslation = false
            if let track = track {
                lyricsService.fetchLyrics(for: track)
            }
        }
        .onExitCommand {
            isPresented = false
        }
    }
    
    // MARK: - Lyrics View (Mode 1)
    
    private var lyricsView: some View {
        VStack(spacing: 0) {
            // Top Mini Player
            if let track = track {
                VStack(spacing: 10) {
                    HStack(spacing: 12) {
                        let artworkURL = track.artworkURL ?? track.user.avatarURL
                        RemoteImage(url: artworkURL, cornerRadius: 8)
                            .frame(width: 44, height: 44)
                            .shadow(color: Color.black.opacity(0.18), radius: 3, x: 0, y: 1)
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Button(action: { onTrackTap?(track) }) {
                                Text(track.title)
                                    .font(.system(size: 13, weight: .semibold))
                                    .lineLimit(1)
                                    .foregroundColor(.primary)
                            }
                            .buttonStyle(.plain)
                            
                            Button(action: { onUserTap?(track.user) }) {
                                Text(track.user.username)
                                    .font(.system(size: 11.5))
                                    .lineLimit(1)
                                    .foregroundColor(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                        
                        Spacer()
                        
                        if !isInspectingNonPlayingTrack {
                            ClosePanelButton {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    isPresented = false
                                }
                            }
                        }
                    }
                    
                    // Controls: Backward, Play/Pause, Forward ONLY
                    let isCurrent = player.currentStream?.id == track.id
                    let isPlayingThis = isCurrent && player.isPlaying
                    
                    HStack(spacing: 24) {
                        Button(action: player.advanceBackward) {
                            Image(systemName: "backward.fill")
                                .font(.system(size: 14))
                                .foregroundColor(.primary)
                        }
                        .buttonStyle(.plain)
                        
                        Button(action: {
                            if isCurrent {
                                player.togglePlayback()
                            } else {
                                player.play([track], from: 0)
                                inspectedTrack = nil
                            }
                        }) {
                            ZStack {
                                Circle()
                                    .fill(Color(hex: 0xFF5500))
                                    .frame(width: 36, height: 36)
                                    .shadow(color: Color(hex: 0xFF5500).opacity(0.35), radius: 4, x: 0, y: 1.5)
                                
                                Image(systemName: isPlayingThis ? "pause.fill" : "play.fill")
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundColor(.white)
                                    .offset(x: isPlayingThis ? 0 : 1.5)
                            }
                        }
                        .buttonStyle(.plain)
                        
                        Button(action: player.advanceForward) {
                            Image(systemName: "forward.fill")
                                .font(.system(size: 14))
                                .foregroundColor(.primary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 10)
                
                Divider()
            } else {
                HStack {
                    Spacer()
                    ClosePanelButton {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            isPresented = false
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 10)
                .padding(.bottom, 6)
            }
            
            // Lyrics Scroll Body
            if lyricsService.isLoading {
                VStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let lyrics = activeLyrics, !lyrics.isEmpty {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 14) {
                        let sections = parseLyricsSections(lyrics)
                        ForEach(Array(sections.enumerated()), id: \.element.id) { index, section in
                            VStack(alignment: .leading, spacing: 4) {
                                if let header = section.header {
                                    HStack(alignment: .center, spacing: 8) {
                                        Text(header)
                                            .font(.system(size: 12.5, weight: .bold, design: .rounded))
                                            .foregroundColor(Color(hex: 0xFF5500))
                                            .lineLimit(1)
                                            .truncationMode(.tail)
                                            .layoutPriority(0)
                                        
                                        Spacer(minLength: 4)
                                        
                                        if index == 0 {
                                            languageSwitcherAndGeniusLink
                                                .layoutPriority(1)
                                        }
                                    }
                                    .padding(.top, index == 0 ? 0 : 8)
                                } else if index == 0 {
                                    HStack(alignment: .center, spacing: 8) {
                                        if let firstLine = section.lines.first {
                                            Text(firstLine)
                                                .font(.system(size: 15, weight: .medium, design: .rounded))
                                                .foregroundColor(.primary)
                                                .lineLimit(1)
                                                .truncationMode(.tail)
                                                .layoutPriority(0)
                                        }
                                        Spacer(minLength: 4)
                                        languageSwitcherAndGeniusLink
                                            .layoutPriority(1)
                                    }
                                }
                                
                                let linesToDisplay = (section.header == nil && index == 0 && (activeSongInfo?.geniusURL != nil || lyricsService.translatedLyrics != nil)) ? Array(section.lines.dropFirst()) : section.lines
                                
                                ForEach(Array(linesToDisplay.enumerated()), id: \.offset) { _, line in
                                    Text(line)
                                        .font(.system(size: 15, weight: .medium, design: .rounded))
                                        .foregroundColor(.primary)
                                        .lineSpacing(4)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                        }
                        
                        // Generous clearance at the bottom so outro has plenty of breathing room
                        Color.clear.frame(height: 70)
                    }
                    .padding(.horizontal, 18)
                    .padding(.top, 14)
                    .padding(.bottom, 20)
                }
                .introspectScrollView { scrollView in
                    scrollView.hasVerticalScroller = false
                }
            } else {
                VStack(spacing: 10) {
                    Image(systemName: "quote.bubble")
                        .font(.system(size: 32))
                        .foregroundColor(.secondary.opacity(0.4))
                    Text(LocalizedStringKey("lyrics.notFound"))
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.primary)
                    Text(LocalizedStringKey("lyrics.notFoundDescription"))
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                    
                    if let track = track {
                        Button(LocalizedStringKey("lyrics.tryAgain")) {
                            lyricsService.fetchLyrics(for: track)
                        }
                        .buttonStyle(.bordered)
                        .padding(.top, 4)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
    
    // MARK: - Language Switcher & Genius Link
    
    @ViewBuilder
    private var languageSwitcherAndGeniusLink: some View {
        HStack(spacing: 6) {
            if lyricsService.translatedLyrics != nil {
                HStack(spacing: 2) {
                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.18)) {
                            showingTranslation = false
                        }
                    }) {
                        Text(lyricsService.originalLanguageCode)
                            .font(.system(size: 10, weight: !showingTranslation ? .bold : .medium))
                            .foregroundColor(!showingTranslation ? Color(hex: 0xFF5500) : .secondary)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(
                                Capsule()
                                    .fill(!showingTranslation ? Color(hex: 0xFF5500).opacity(0.15) : Color.clear)
                            )
                    }
                    .buttonStyle(.plain)
                    .help(String(format: NSLocalizedString("lyrics.originalWithLang", comment: ""), lyricsService.originalLanguageCode))
                    
                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.18)) {
                            showingTranslation = true
                        }
                    }) {
                        Text(lyricsService.translationLanguageCode)
                            .font(.system(size: 10, weight: showingTranslation ? .bold : .medium))
                            .foregroundColor(showingTranslation ? Color(hex: 0xFF5500) : .secondary)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(
                                Capsule()
                                    .fill(showingTranslation ? Color(hex: 0xFF5500).opacity(0.15) : Color.clear)
                            )
                    }
                    .buttonStyle(.plain)
                    .help(String(format: NSLocalizedString("lyrics.translationWithLang", comment: ""), lyricsService.translationLanguageCode))
                }
                .padding(2)
                .background(
                    Capsule()
                        .fill(Color.primary.opacity(0.06))
                )
            }
            
            if let url = activeSongInfo?.geniusURL {
                Link(destination: url) {
                    HStack(spacing: 3) {
                        Image(systemName: "safari")
                            .font(.system(size: 10))
                        Text("Genius ↗")
                            .font(.system(size: 11, weight: .medium))
                            .lineLimit(1)
                    }
                    .fixedSize(horizontal: true, vertical: false)
                    .foregroundColor(Color(hex: 0xFF5500))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(
                        Capsule()
                            .fill(Color(hex: 0xFF5500).opacity(0.12))
                    )
                }
                .buttonStyle(.plain)
                .help(showingTranslation ? NSLocalizedString("lyrics.openTranslationOnGenius", comment: "") : NSLocalizedString("lyrics.openOnGenius", comment: ""))
            }
        }
        .fixedSize(horizontal: true, vertical: false)
    }
    
    // MARK: - Poster View (Mode 2)
    
    private var posterView: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 16) {
                if !isInspectingNonPlayingTrack {
                    HStack {
                        Spacer()
                        ClosePanelButton {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                isPresented = false
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 10)
                    .padding(.bottom, 0)
                }
                
                if let track = track {
                    let artworkURL = track.artworkURL ?? track.user.avatarURL
                    
                    // Artwork with ambient glow
                    ZStack {
                        RemoteImage(url: artworkURL, cornerRadius: 18)
                            .frame(width: 220, height: 220)
                            .blur(radius: 22)
                            .opacity(0.38)
                            .offset(y: 8)
                        
                        RemoteImage(url: artworkURL, cornerRadius: 16)
                            .frame(width: 210, height: 210)
                            .overlay(
                                RoundedRectangle(cornerRadius: 16)
                                    .stroke(Color.white.opacity(0.12), lineWidth: 1)
                            )
                            .shadow(color: Color.black.opacity(0.3), radius: 14, x: 0, y: 6)
                        
                        if isHoveringArtwork {
                            RoundedRectangle(cornerRadius: 16)
                                .fill(Color.black.opacity(0.32))
                                .frame(width: 210, height: 210)
                            
                            Button(action: {
                                NotificationCenter.default.post(name: .openFullscreenNowPlaying, object: track)
                            }) {
                                ZStack {
                                    Circle()
                                        .fill(Color.white.opacity(0.25))
                                        .frame(width: 44, height: 44)
                                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                                        .font(.system(size: 16, weight: .bold))
                                        .foregroundColor(.white)
                                }
                            }
                            .buttonStyle(.plain)
                            .help(NSLocalizedString("nowPlaying.fullscreen", comment: ""))
                            .transition(.opacity)
                        }
                    }
                    .scaleEffect(isHoveringArtwork ? 1.02 : 1.0)
                    .animation(.spring(response: 0.35, dampingFraction: 0.7), value: isHoveringArtwork)
                    .onHover { isHoveringArtwork = $0 }
                    
                    // Track Title & Artist
                    VStack(spacing: 4) {
                        Button(action: { onTrackTap?(track) }) {
                            Text(track.title)
                                .font(.system(size: 16, weight: .bold, design: .rounded))
                                .lineLimit(2)
                                .multilineTextAlignment(.center)
                                .foregroundColor(.primary)
                                .padding(.horizontal, 16)
                        }
                        .buttonStyle(.plain)
                        
                        Button(action: { onUserTap?(track.user) }) {
                            HStack(spacing: 5) {
                                RemoteImage(url: track.user.avatarURL, cornerRadius: 8)
                                    .frame(width: 18, height: 18)
                                Text(track.user.username)
                                    .font(.system(size: 12.5, weight: .medium))
                                    .foregroundColor(.secondary)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.top, 4)
                    
                    // Modern Progress Bar (No waveform)
                    ModernProgressBar(value: $player.progress, duration: TimeInterval(track.duration))
                        .frame(maxWidth: 300)
                        .padding(.top, 2)
                    
                    // Playback Controls
                    posterControls
                        .padding(.top, 2)
                    
                    // Stats: Like, Repost, Playback
                    HStack(spacing: 16) {
                        Button(action: { toggleLikeTrack(track)() }) {
                            HStack(spacing: 4) {
                                Image(systemName: isLiked ? "heart.fill" : "heart")
                                Text(format(count: track.likeCount))
                            }
                            .font(.system(size: 11.5, weight: .medium))
                            .foregroundColor(isLiked ? Color(hex: 0xFF5500) : .secondary)
                        }
                        .buttonStyle(.plain)
                        
                        Button(action: { toggleRepostTrack(track)() }) {
                            HStack(spacing: 4) {
                                Image(systemName: isRepost ? "arrow.triangle.2.circlepath.circle.fill" : "arrow.triangle.2.circlepath")
                                Text(format(count: track.repostCount))
                            }
                            .font(.system(size: 11.5, weight: .medium))
                            .foregroundColor(isRepost ? Color(hex: 0xFF5500) : .secondary)
                        }
                        .buttonStyle(.plain)
                        
                        HStack(spacing: 3) {
                            Image(systemName: "play.fill")
                                .font(.system(size: 8))
                            Text(format(count: track.playbackCount))
                        }
                        .font(.system(size: 11.5))
                        .foregroundColor(.secondary)
                    }
                    .padding(.top, 2)
                }
                
                Spacer(minLength: 16)
            }
            .padding(.horizontal, 16)
            .padding(.top, 24)
            .padding(.bottom, 16)
        }
    }
    
    private var posterControls: some View {
        let isCurrent = player.currentStream?.id == track?.id
        let isPlayingThis = isCurrent && player.isPlaying
        
        return HStack(spacing: 20) {
            Button(action: { player.shuffleQueue.toggle() }) {
                Image(systemName: "shuffle")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(player.shuffleQueue ? Color(hex: 0xFF5500) : .secondary)
            }
            .buttonStyle(.plain)
            
            Button(action: player.advanceBackward) {
                Image(systemName: "backward.fill")
                    .font(.system(size: 16))
                    .foregroundColor(.primary)
            }
            .buttonStyle(.plain)
            
            Button(action: {
                if let track = track {
                    if isCurrent {
                        player.togglePlayback()
                    } else {
                        player.play([track], from: 0)
                        inspectedTrack = nil
                    }
                }
            }) {
                ZStack {
                    Circle()
                        .fill(Color(hex: 0xFF5500))
                        .frame(width: 44, height: 44)
                        .shadow(color: Color(hex: 0xFF5500).opacity(0.35), radius: 5, x: 0, y: 1.5)
                    
                    Image(systemName: isPlayingThis ? "pause.fill" : "play.fill")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundColor(.white)
                        .offset(x: isPlayingThis ? 0 : 1.5)
                }
            }
            .buttonStyle(.plain)
            
            Button(action: player.advanceForward) {
                Image(systemName: "forward.fill")
                    .font(.system(size: 16))
                    .foregroundColor(.primary)
            }
            .buttonStyle(.plain)
            
            Button(action: player.toggleRepeatMode) {
                Image(systemName: repeatIconName)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(player.repeatMode != .off ? Color(hex: 0xFF5500) : .secondary)
            }
            .buttonStyle(.plain)
            .help(repeatTooltip)
        }
    }
    
    private var repeatIconName: String {
        switch player.repeatMode {
        case .off, .all: return "repeat"
        case .one: return "repeat.1"
        }
    }
    
    private var repeatTooltip: String {
        switch player.repeatMode {
        case .off: return NSLocalizedString("player.repeatOff", comment: "")
        case .all: return NSLocalizedString("player.repeatAll", comment: "")
        case .one: return NSLocalizedString("player.repeatOne", comment: "")
        }
    }
    
    // MARK: - Lyrics Parser
    
    private struct ParsedLyricsSection: Identifiable {
        let id = UUID()
        let header: String?
        let lines: [String]
    }
    
    private func parseLyricsSections(_ raw: String) -> [ParsedLyricsSection] {
        let rawBlocks = raw.components(separatedBy: "\n\n")
        var sections = [ParsedLyricsSection]()
        
        for block in rawBlocks {
            let trimmedBlock = block.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmedBlock.isEmpty { continue }
            
            var blockLines = trimmedBlock.components(separatedBy: "\n")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
            if blockLines.isEmpty { continue }
            
            var header: String? = nil
            if isHeaderLine(blockLines[0]) {
                let firstLine = blockLines.removeFirst()
                let lower = firstLine.lowercased()
                // Skip Genius song title headers
                if !lower.contains("текст песни") && !lower.contains("текст трека") && !lower.contains("lyrics") {
                    header = firstLine
                }
            }
            
            // Also skip if the first line is song title in plain text
            if let first = blockLines.first {
                let lower = first.lowercased()
                if lower.contains("текст песни") || lower.contains("текст трека") || lower.hasSuffix("lyrics") {
                    blockLines.removeFirst()
                }
            }
            
            if !blockLines.isEmpty || header != nil {
                sections.append(ParsedLyricsSection(header: header, lines: blockLines))
            }
        }
        return sections
    }
    
    private func isHeaderLine(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        return (trimmed.hasPrefix("[") && trimmed.hasSuffix("]")) || (trimmed.hasPrefix("(") && trimmed.hasSuffix(")"))
    }
}

// Backwards compatibility wrapper for sheet if needed
public struct NowPlayingView: View {
    @Binding var isPresented: Bool
    @State private var mode: NowPlayingMode
    var onTrackTap: ((Track) -> Void)?
    var onUserTap: ((User) -> Void)?
    
    public init(
        isPresented: Binding<Bool>,
        initialMode: NowPlayingMode = .lyrics,
        onTrackTap: ((Track) -> Void)? = nil,
        onUserTap: ((User) -> Void)? = nil
    ) {
        self._isPresented = isPresented
        self._mode = State(initialValue: initialMode)
        self.onTrackTap = onTrackTap
        self.onUserTap = onUserTap
    }
    
    public var body: some View {
        NowPlayingPanel(
            isPresented: $isPresented,
            mode: $mode,
            onTrackTap: onTrackTap,
            onUserTap: onUserTap
        )
    }
}
