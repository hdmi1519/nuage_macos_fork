//
//  FullscreenNowPlayingView.swift
//  Nuage
//
//  Created on 04.10.2026.
//

import SwiftUI
import SoundCloud
import Combine

public struct FullscreenNowPlayingView: View {
    @Binding var isPresented: Bool
    
    @EnvironmentObject private var player: StreamPlayer
    @Environment(\.likes) private var likes: [Track]
    @Environment(\.posts) private var posts: [Post]
    @Environment(\.toggleLikeTrack) private var toggleLikeTrack: (Track) -> () -> ()
    @Environment(\.toggleRepostTrack) private var toggleRepostTrack: (Track) -> () -> ()
    
    @StateObject private var lyricsService = GeniusLyricsService.shared
    
    @State private var showingTranslation: Bool = false
    @State private var autoScroll: Bool = true
    @State private var userScrollResumeWorkItem: DispatchWorkItem? = nil
    @State private var isHoveringClose = false
    @State private var isHoveringArtwork = false
    @State private var hoveredLineId: Int? = nil
    @State private var lastScrolledId: Int? = nil
    
    public init(isPresented: Binding<Bool>) {
        self._isPresented = isPresented
    }
    
    private var track: Track? {
        player.currentStream
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
    
    // MARK: - Lyric Line Model & Parsing
    
    struct LyricLine: Identifiable {
        let id: Int
        let text: String
        let isHeader: Bool
        let lineIndex: Int
        let isLastInBlock: Bool
    }
    
    private var parsedLines: [LyricLine] {
        guard let raw = activeLyrics, !raw.isEmpty else { return [] }
        let rawBlocks = raw.components(separatedBy: "\n\n")
        var items = [LyricLine]()
        var currentId = 0
        var lyricLineCount = 0
        
        for block in rawBlocks {
            let trimmedBlock = block.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmedBlock.isEmpty { continue }
            
            var blockLines = trimmedBlock.components(separatedBy: "\n")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
            if blockLines.isEmpty { continue }
            
            if let first = blockLines.first, isHeaderLine(first) {
                let header = blockLines.removeFirst()
                let lower = header.lowercased()
                if !lower.contains("текст песни") && !lower.contains("текст трека") && !lower.contains("lyrics") {
                    items.append(LyricLine(id: currentId, text: header, isHeader: true, lineIndex: -1, isLastInBlock: false))
                    currentId += 1
                }
            }
            
            for (idx, line) in blockLines.enumerated() {
                let lower = line.lowercased()
                if lower.contains("текст песни") || lower.contains("текст трека") || lower.hasSuffix("lyrics") {
                    continue
                }
                let isLast = (idx == blockLines.count - 1)
                if isHeaderLine(line) {
                    items.append(LyricLine(id: currentId, text: line, isHeader: true, lineIndex: -1, isLastInBlock: false))
                } else {
                    items.append(LyricLine(id: currentId, text: line, isHeader: false, lineIndex: lyricLineCount, isLastInBlock: isLast))
                    lyricLineCount += 1
                }
                currentId += 1
            }
        }
        return items
    }
    
    private var actualLyricLines: [LyricLine] {
        parsedLines.filter { !$0.isHeader }
    }
    
    // MARK: - Intelligent Timing Engine
    
    /// Pre-calculates exact start timestamps for each line based on character weights and song structure
    private var lineTimeTable: [Int: (startTime: Double, endTime: Double)] {
        guard let track = track else { return [:] }
        let duration = max(1.0, TimeInterval(track.duration))
        let lines = actualLyricLines
        guard !lines.isEmpty else { return [:] }
        
        // Realistic intro & outro calibration for modern music
        let introDelay = max(12.0, min(24.0, duration * 0.11))
        let outroBuffer = max(14.0, min(28.0, duration * 0.12))
        let singingDuration = max(1.0, duration - introDelay - outroBuffer)
        
        // Calculate weighted length of each line (longer lines get proportionally more singing time)
        var weights = [Double]()
        for line in lines {
            let charCount = Double(max(15, line.text.count))
            // Extra pause weighting for the last line of a verse/chorus block
            let pauseBonus = line.isLastInBlock ? 30.0 : 0.0
            weights.append(charCount + pauseBonus)
        }
        let totalWeight = max(1.0, weights.reduce(0, +))
        
        var table = [Int: (startTime: Double, endTime: Double)]()
        var currentStart = introDelay
        
        for (i, line) in lines.enumerated() {
            let lineDuration = (weights[i] / totalWeight) * singingDuration
            let lineEnd = currentStart + lineDuration
            table[line.id] = (startTime: currentStart, endTime: lineEnd)
            currentStart = lineEnd
        }
        
        return table
    }
    
    private func currentActiveLineId() -> Int? {
        guard let track = track, !actualLyricLines.isEmpty else { return nil }
        let progress = player.progress
        let table = lineTimeTable
        let lines = actualLyricLines
        
        // If before intro finishes, highlight first line softly
        if let first = lines.first, let firstTimes = table[first.id], progress < firstTimes.startTime {
            return first.id
        }
        
        // Find line matching current playback time
        for line in lines {
            if let times = table[line.id] {
                if progress >= times.startTime && progress < times.endTime {
                    return line.id
                }
            }
        }
        
        // If past all lines, keep last line active
        return lines.last?.id
    }
    
    private func seekToLine(_ line: LyricLine) {
        guard let times = lineTimeTable[line.id] else { return }
        player.progress = max(0.0, times.startTime)
    }
    
    private func isHeaderLine(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        return (trimmed.hasPrefix("[") && trimmed.hasSuffix("]")) || (trimmed.hasPrefix("(") && trimmed.hasSuffix(")"))
    }
    
    public var body: some View {
        GeometryReader { geo in
            let windowWidth = geo.size.width
            let windowHeight = geo.size.height
            
            ZStack(alignment: .topLeading) {
                // 1. Strictly bounded Ambient Backdrop
                ZStack {
                    Color(hex: 0x0C0D11)
                    
                    if let track = track {
                        let artworkURL = track.artworkURL ?? track.user.avatarURL
                        RemoteImage(url: artworkURL, cornerRadius: 0)
                            .frame(width: windowWidth, height: windowHeight)
                            .clipped()
                            .blur(radius: 75)
                            .opacity(0.35)
                    }
                    
                    LinearGradient(
                        colors: [
                            Color.black.opacity(0.55),
                            Color.black.opacity(0.72),
                            Color.black.opacity(0.90)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                }
                .frame(width: windowWidth, height: windowHeight)
                .clipped()
                
                // 2. Exact Window-Fitting Main Layout
                VStack(spacing: 0) {
                    // Top Navigation Header
                    topHeaderBar
                        .frame(width: windowWidth, height: 50)
                    
                    // Main Columns Area
                    HStack(alignment: .center, spacing: 44) {
                        // Left Column: Player & Artwork
                        leftPlayerColumn
                            .frame(width: 360)
                            .frame(maxHeight: .infinity)
                        
                        // Right Column: Lyrics Scroll
                        rightLyricsColumn
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                    .padding(.horizontal, 36)
                    .padding(.bottom, 16)
                    .frame(width: windowWidth, height: max(200, windowHeight - 50))
                }
                .frame(width: windowWidth, height: windowHeight)
            }
            .frame(width: windowWidth, height: windowHeight)
            .clipped()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            let win = (NSApp.keyWindow ?? NSApp.mainWindow ?? NSApp.windows.first)
            win?.toolbar?.isVisible = false
            win?.titleVisibility = .hidden
            if let track = track {
                lyricsService.fetchLyrics(for: track)
            }
        }
        .onDisappear {
            let win = (NSApp.keyWindow ?? NSApp.mainWindow ?? NSApp.windows.first)
            win?.toolbar?.isVisible = true
            win?.titleVisibility = .visible
        }
        .onChange(of: track?.id) { _ in
            showingTranslation = false
            autoScroll = true
            lastScrolledId = nil
            if let track = track {
                lyricsService.fetchLyrics(for: track)
            }
        }
        .onExitCommand {
            dismiss()
        }
    }
    
    private func dismiss() {
        let win = (NSApp.keyWindow ?? NSApp.mainWindow ?? NSApp.windows.first)
        win?.toolbar?.isVisible = true
        win?.titleVisibility = .visible
        withAnimation(.easeInOut(duration: 0.22)) {
            isPresented = false
        }
    }
    
    // MARK: - Top Header Bar (Clean, no cheesy playback pills on the left)
    
    private var topHeaderBar: some View {
        HStack(alignment: .center, spacing: 14) {
            // Left: Clean breathing room for macOS window controls (traffic lights)
            Spacer()
                .frame(width: 80)
            
            Spacer()
            
            // Language Switcher & Genius Link
            languageAndGeniusControls
            
            // Prominent Close Button
            Button(action: dismiss) {
                ZStack {
                    Circle()
                        .fill(isHoveringClose ? Color.white.opacity(0.24) : Color.white.opacity(0.12))
                        .frame(width: 32, height: 32)
                    
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(isHoveringClose ? .white : .white.opacity(0.85))
                }
            }
            .buttonStyle(.plain)
            .help(NSLocalizedString("fullscreen.close", comment: ""))
            .keyboardShortcut(.cancelAction)
            .onHover { isHoveringClose = $0 }
            .padding(.trailing, 22)
        }
    }
    
    // MARK: - Language & Genius Controls
    
    @ViewBuilder
    private var languageAndGeniusControls: some View {
        HStack(spacing: 8) {
            // Language Switcher Capsule
            HStack(spacing: 2) {
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        showingTranslation = false
                    }
                }) {
                    Text(lyricsService.originalLanguageCode)
                        .font(.system(size: 11, weight: !showingTranslation ? .bold : .medium))
                        .foregroundColor(!showingTranslation ? Color(hex: 0xFF5500) : .white.opacity(0.65))
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4)
                        .background(
                            Capsule()
                                .fill(!showingTranslation ? Color(hex: 0xFF5500).opacity(0.22) : Color.clear)
                        )
                }
                .buttonStyle(.plain)
                .help(String(format: NSLocalizedString("lyrics.originalWithLang", comment: ""), lyricsService.originalLanguageCode))
                
                if lyricsService.translatedLyrics != nil {
                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.18)) {
                            showingTranslation = true
                        }
                    }) {
                        Text(lyricsService.translationLanguageCode)
                            .font(.system(size: 11, weight: showingTranslation ? .bold : .medium))
                            .foregroundColor(showingTranslation ? Color(hex: 0xFF5500) : .white.opacity(0.65))
                            .padding(.horizontal, 9)
                            .padding(.vertical, 4)
                            .background(
                                Capsule()
                                    .fill(showingTranslation ? Color(hex: 0xFF5500).opacity(0.22) : Color.clear)
                            )
                    }
                    .buttonStyle(.plain)
                    .help(String(format: NSLocalizedString("lyrics.translationWithLang", comment: ""), lyricsService.translationLanguageCode))
                } else if lyricsService.isLoadingTranslation {
                    HStack(spacing: 4) {
                        ProgressView().controlSize(.mini)
                        Text(lyricsService.translationLanguageCode)
                            .font(.system(size: 11))
                            .foregroundColor(.white.opacity(0.50))
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                } else {
                    Text(lyricsService.translationLanguageCode)
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.30))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .help(String(format: NSLocalizedString("lyrics.translationNotFound", comment: ""), lyricsService.translationLanguageCode))
                }
            }
            .padding(3)
            .background(
                Capsule()
                    .fill(Color.white.opacity(0.09))
            )
            
            if let url = activeSongInfo?.geniusURL {
                Link(destination: url) {
                    HStack(spacing: 4) {
                        Image(systemName: "safari")
                            .font(.system(size: 11))
                        Text("Genius ↗")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .foregroundColor(Color(hex: 0xFF5500))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(
                        Capsule()
                            .fill(Color(hex: 0xFF5500).opacity(0.16))
                    )
                }
                .buttonStyle(.plain)
                .help(showingTranslation ? NSLocalizedString("lyrics.openTranslationOnGenius", comment: "") : NSLocalizedString("lyrics.openOnGenius", comment: ""))
            }
        }
    }
    
    // MARK: - Left Player Column
    
    private var leftPlayerColumn: some View {
        VStack(spacing: 16) {
            Spacer(minLength: 0)
            
            if let track = track {
                let artworkURL = track.artworkURL ?? track.user.avatarURL
                
                // Artwork with ambient glow
                ZStack {
                    RemoteImage(url: artworkURL, cornerRadius: 20)
                        .frame(width: 270, height: 270)
                        .blur(radius: 24)
                        .opacity(0.40)
                        .offset(y: 8)
                    
                    RemoteImage(url: artworkURL, cornerRadius: 18)
                        .frame(width: 260, height: 260)
                        .overlay(
                            RoundedRectangle(cornerRadius: 18)
                                .stroke(Color.white.opacity(0.15), lineWidth: 1)
                        )
                        .shadow(color: Color.black.opacity(0.45), radius: 18, x: 0, y: 8)
                }
                .scaleEffect(isHoveringArtwork ? 1.02 : 1.0)
                .animation(.spring(response: 0.35, dampingFraction: 0.7), value: isHoveringArtwork)
                .onHover { isHoveringArtwork = $0 }
                
                // Title & Artist
                VStack(spacing: 5) {
                    Text(track.title)
                        .font(.system(size: 21, weight: .bold, design: .rounded))
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                        .foregroundColor(.white)
                        .padding(.horizontal, 10)
                    
                    Text(track.user.username)
                        .font(.system(size: 14.5, weight: .medium))
                        .foregroundColor(.white.opacity(0.75))
                        .lineLimit(1)
                }
                .padding(.top, 4)
                
                // Scrubber / Progress Bar
                ModernProgressBar(value: $player.progress, duration: TimeInterval(track.duration))
                    .frame(maxWidth: 300)
                    .padding(.top, 4)
                
                // Playback Controls: Shuffle, Backward, Play/Pause, Forward, Repeat
                HStack(spacing: 20) {
                    Button(action: {
                        player.shuffleQueue.toggle()
                    }) {
                        Image(systemName: "shuffle")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(player.shuffleQueue ? Color(hex: 0xFF5500) : .white.opacity(0.65))
                    }
                    .buttonStyle(.plain)
                    .help(LocalizedStringKey("menu.shuffle"))
                    
                    Button(action: player.advanceBackward) {
                        Image(systemName: "backward.fill")
                            .font(.system(size: 19))
                            .foregroundColor(.white)
                    }
                    .buttonStyle(.plain)
                    
                    Button(action: player.togglePlayback) {
                        ZStack {
                            Circle()
                                .fill(Color(hex: 0xFF5500))
                                .frame(width: 52, height: 52)
                                .shadow(color: Color(hex: 0xFF5500).opacity(0.4), radius: 8, x: 0, y: 2)
                            
                            Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                                .font(.system(size: 20, weight: .bold))
                                .foregroundColor(.white)
                                .offset(x: player.isPlaying ? 0 : 2)
                        }
                    }
                    .buttonStyle(.plain)
                    
                    Button(action: player.advanceForward) {
                        Image(systemName: "forward.fill")
                            .font(.system(size: 19))
                            .foregroundColor(.white)
                    }
                    .buttonStyle(.plain)
                    
                    Button(action: player.toggleRepeatMode) {
                        Image(systemName: repeatIconName)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(player.repeatMode != .off ? Color(hex: 0xFF5500) : .white.opacity(0.65))
                    }
                    .buttonStyle(.plain)
                    .help(repeatTooltip)
                }
                .padding(.top, 4)
                
                // Social stats & volume
                HStack(spacing: 18) {
                    Button(action: { toggleLikeTrack(track)() }) {
                        HStack(spacing: 4) {
                            Image(systemName: isLiked ? "heart.fill" : "heart")
                            Text(format(count: track.likeCount))
                        }
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(isLiked ? Color(hex: 0xFF5500) : .white.opacity(0.75))
                    }
                    .buttonStyle(.plain)
                    
                    Button(action: { toggleRepostTrack(track)() }) {
                        HStack(spacing: 4) {
                            Image(systemName: isRepost ? "arrow.triangle.2.circlepath.circle.fill" : "arrow.triangle.2.circlepath")
                            Text(format(count: track.repostCount))
                        }
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(isRepost ? Color(hex: 0xFF5500) : .white.opacity(0.75))
                    }
                    .buttonStyle(.plain)
                    
                    // Volume Control
                    HStack(spacing: 6) {
                        Image(systemName: player.volume == 0 ? "speaker.slash.fill" : "speaker.wave.2.fill")
                            .font(.system(size: 11))
                            .foregroundColor(.white.opacity(0.7))
                        
                        Slider(value: $player.volume, in: 0...1)
                            .frame(width: 80)
                            .controlSize(.mini)
                    }
                }
                .padding(.top, 4)
            } else {
                Text(LocalizedStringKey("playlists.empty"))
                    .foregroundColor(.secondary)
            }
            
            Spacer(minLength: 0)
        }
    }
    
    // MARK: - Right Lyrics Column (Smooth, Non-Jittery Sync with Click-to-Seek)
    
    private var rightLyricsColumn: some View {
        ZStack(alignment: .bottom) {
            if lyricsService.isLoading {
                VStack(spacing: 12) {
                    ProgressView()
                        .controlSize(.regular)
                    Text(LocalizedStringKey("lyrics.loading"))
                        .font(.system(size: 14))
                        .foregroundColor(.white.opacity(0.7))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if parsedLines.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "quote.bubble")
                        .font(.system(size: 40))
                        .foregroundColor(.white.opacity(0.4))
                    Text(LocalizedStringKey("lyrics.notFound"))
                        .font(.system(size: 18, weight: .semibold, design: .rounded))
                        .foregroundColor(.white.opacity(0.85))
                    Text(LocalizedStringKey("lyrics.notFoundDescription"))
                        .font(.system(size: 13))
                        .foregroundColor(.white.opacity(0.55))
                    
                    if let track = track {
                        Button(LocalizedStringKey("lyrics.tryAgain")) {
                            lyricsService.fetchLyrics(for: track)
                        }
                        .buttonStyle(.bordered)
                        .padding(.top, 4)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollViewReader { proxy in
                    let lines = parsedLines
                    let activeId = currentActiveLineId()
                    
                    ScrollView(.vertical, showsIndicators: false) {
                        VStack(alignment: .leading, spacing: 14) {
                            // Top breathing clearance - comfortable and fully visible
                            Color.clear.frame(height: 24)
                            
                            ForEach(lines) { line in
                                if line.isHeader {
                                    Text(line.text)
                                        .font(.system(size: 13.5, weight: .bold, design: .rounded))
                                        .foregroundColor(Color(hex: 0xFF5500))
                                        .padding(.top, 14)
                                        .id(line.id)
                                } else {
                                    let isActive = (line.id == activeId)
                                    let isHovered = (hoveredLineId == line.id)
                                    
                                    Button(action: {
                                        seekToLine(line)
                                        withAnimation(.spring(response: 0.42, dampingFraction: 0.85)) {
                                            proxy.scrollTo(line.id, anchor: .center)
                                        }
                                    }) {
                                        // SAME constant font size (22pt) prevents vertical line jumping/jitter!
                                        Text(line.text)
                                            .font(.system(size: 22, weight: isActive ? .bold : .medium, design: .rounded))
                                            .foregroundColor(isActive ? .white : (isHovered ? .white.opacity(0.80) : .white.opacity(0.38)))
                                            .multilineTextAlignment(.leading)
                                            .scaleEffect(isActive ? 1.015 : 1.0, anchor: .leading)
                                            .animation(.easeInOut(duration: 0.20), value: isActive)
                                            .padding(.vertical, 2)
                                            .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)
                                    .id(line.id)
                                    .onHover { isHovering in
                                        if isHovering {
                                            hoveredLineId = line.id
                                        } else if hoveredLineId == line.id {
                                            hoveredLineId = nil
                                        }
                                    }
                                }
                            }
                            
                            // Bottom breathing clearance
                            Color.clear.frame(height: 80)
                        }
                        .padding(.horizontal, 20)
                    }
                    .onChange(of: player.progress) { _ in
                        if autoScroll, let targetId = currentActiveLineId() {
                            // ONLY scroll when target line actually CHANGES, avoiding redundant micro-jitters!
                            if targetId != lastScrolledId {
                                lastScrolledId = targetId
                                withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) {
                                    proxy.scrollTo(targetId, anchor: .center)
                                }
                            }
                        }
                    }
                    .simultaneousGesture(
                        DragGesture().onChanged { _ in
                            autoScroll = false
                            userScrollResumeWorkItem?.cancel()
                            let work = DispatchWorkItem {
                                withAnimation {
                                    autoScroll = true
                                }
                            }
                            userScrollResumeWorkItem = work
                            DispatchQueue.main.asyncAfter(deadline: .now() + 5.0, execute: work)
                        }
                    )
                }
            }
            
            // Re-sync Floating Pill when user scrolled away
            if !autoScroll && !parsedLines.isEmpty {
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.28)) {
                        autoScroll = true
                        if let targetId = currentActiveLineId() {
                            lastScrolledId = nil
                        }
                    }
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 11, weight: .bold))
                        Text(LocalizedStringKey("lyrics.sync"))
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(
                        Capsule()
                            .fill(Color(hex: 0xFF5500))
                            .shadow(color: Color.black.opacity(0.35), radius: 6, x: 0, y: 2)
                    )
                }
                .buttonStyle(.plain)
                .padding(.bottom, 14)
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
    }
}
