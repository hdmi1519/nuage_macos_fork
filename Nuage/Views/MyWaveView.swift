//
//  MyWaveView.swift
//  Nuage
//
//  Created on 04.10.2026.
//

import SwiftUI
import Combine
import Introspect
import SoundCloud

struct MyWaveView: View {
    
    @Environment(\.likes) private var likes: [Track]
    @EnvironmentObject private var player: StreamPlayer
    @EnvironmentObject private var commandSubjects: CommandSubject
    @ObservedObject private var waveService = WaveService.shared
    
    @State private var isSpinning: Bool = false
    @State private var didInitialLoad: Bool = false
    
    private var waveTracks: [Track] {
        waveService.waveTracks
    }
    
    private var seedTracks: [Track] {
        waveService.seedTracks
    }
    
    private var isLoading: Bool {
        waveService.isLoading
    }
    
    private var isPlayingWave: Bool {
        guard let current = player.currentStream, !waveTracks.isEmpty else { return false }
        return player.isPlaying && (player.isWaveMode || waveTracks.contains(where: { $0.id == current.id }))
    }
    
    var body: some View {
        Group {
            if likes.isEmpty {
                emptyLikesState
            } else if isLoading && waveTracks.isEmpty {
                loadingState
            } else {
                ScrollView {
                    // True LazyVStack virtualization for silky 120fps scrolling
                    LazyVStack(alignment: .leading, spacing: 4) {
                        heroCard
                            .padding(.bottom, 12)
                        
                        if !waveTracks.isEmpty {
                            HStack {
                                Text(LocalizedStringKey("wave.tracksInStream"))
                                    .font(.system(size: 15, weight: .bold))
                                
                                Spacer()
                                
                                HStack(spacing: 5) {
                                    Image(systemName: "infinity")
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundColor(Color(hex: 0xFF5500))
                                    
                                    Text("\(waveTracks.count) \(NSLocalizedString("playlists.tracksCount", comment: ""))")
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundColor(.secondary)
                                }
                            }
                            .padding(.horizontal, 4)
                            .padding(.vertical, 6)
                            
                            ForEach(waveTracks) { track in
                                TrackRow(track: track)
                                    .playbackStart(at: track)
                                    .trackContextMenu(with: track)
                            }
                            
                            bottomStreamFooter
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
                    .padding(.bottom, 24)
                }
                .playbackContext(waveTracks)
                .introspectScrollView { scrollView in
                    scrollView.scrollerStyle = .overlay
                    scrollView.verticalScroller?.controlSize = .small
                }
            }
        }
        .navigationTitle(NSLocalizedString("sidebar.wave", comment: "Моя волна"))
        .onAppear {
            if !didInitialLoad {
                didInitialLoad = true
                waveService.generateWave(likes: likes)
            }
        }
        .onReceive(commandSubjects.reload) {
            triggerRefresh()
        }
        .onReceive(player.$currentStream) { current in
            guard let current = current, player.isPlaying, player.isWaveMode else { return }
            if let idx = waveTracks.firstIndex(where: { $0.id == current.id }) {
                if waveTracks.count - idx <= 4 {
                    waveService.loadMoreTracks(likes: likes, player: player)
                }
            }
        }
    }
    
    // MARK: - Hero Banner
    
    private var heroCard: some View {
        ZStack(alignment: .leading) {
            // 1. Deep Midnight Slate & Indigo Base (Rich, cinematic dark mode)
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(hex: 0x1E2436), // Deep midnight slate
                            Color(hex: 0x151926), // Twilight indigo
                            Color(hex: 0x10121D)  // Deep night obsidian
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            
            // 2. Soft Ambient Lighting Wash (Warm ember & cobalt sheen, no harsh neon)
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(hex: 0xFF5500).opacity(0.14),
                            Color(hex: 0x2A3E6D).opacity(0.15),
                            Color.clear
                        ],
                        startPoint: .topLeading,
                        endPoint: .center
                    )
                )
            
            // 3. Subtle 1px Glass Border
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.14),
                            Color.white.opacity(0.04)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
            
            // 4. Content
            HStack(alignment: .center, spacing: 20) {
                VStack(alignment: .leading, spacing: 14) {
                    // Header Row
                    HStack(spacing: 8) {
                        Text(LocalizedStringKey("badge.new"))
                            .font(.system(size: 9.5, weight: .heavy, design: .rounded))
                            .foregroundColor(.white)
                            .padding(.horizontal, 6.5)
                            .padding(.vertical, 2.5)
                            .background(
                                Capsule().fill(Color(hex: 0xFF5500))
                            )
                        
                        Text(LocalizedStringKey("wave.personalStream"))
                            .font(.system(size: 12.5, weight: .medium))
                            .foregroundColor(.white.opacity(0.85))
                    }
                    
                    // Title & Subtitle
                    VStack(alignment: .leading, spacing: 5) {
                        Text(LocalizedStringKey("sidebar.wave"))
                            .font(.system(size: 29, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                        
                        Text(LocalizedStringKey("wave.description"))
                            .font(.system(size: 13))
                            .foregroundColor(.white.opacity(0.78))
                            .lineSpacing(3)
                            .frame(maxWidth: 520, alignment: .leading)
                    }
                    
                    // Seed Artists & Tracks Chip
                    if !seedTracks.isEmpty {
                        let artists = Array(Set(seedTracks.map { $0.user.username })).prefix(4).joined(separator: ", ")
                        let totalArtists = Set(likes.map { $0.user.username }).count
                        let extraArtists = max(0, totalArtists - 4)
                        let labelText = extraArtists > 0 ? String(format: NSLocalizedString("wave.inspiredByAndMore", comment: ""), artists, extraArtists) : String(format: NSLocalizedString("wave.inspiredBy", comment: ""), artists)
                        
                        HStack(spacing: 6) {
                            Image(systemName: "sparkles")
                                .font(.system(size: 11))
                                .foregroundColor(Color(hex: 0xFFB300))
                            
                            Text(labelText)
                                .font(.system(size: 11.5, weight: .medium))
                                .foregroundColor(.white.opacity(0.92))
                                .lineLimit(1)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4.5)
                        .background(
                            Capsule().fill(Color.black.opacity(0.35))
                        )
                        .overlay(
                            Capsule().stroke(Color.white.opacity(0.12), lineWidth: 0.8)
                        )
                    }
                    
                    // Action Buttons
                    HStack(spacing: 12) {
                        // Play Button
                        Button(action: togglePlayWave) {
                            HStack(spacing: 7) {
                                Image(systemName: isPlayingWave ? "pause.fill" : "play.fill")
                                    .font(.system(size: 12.5, weight: .bold))
                                
                                Text(isPlayingWave ? LocalizedStringKey("wave.pauseWave") : LocalizedStringKey("wave.listenWave"))
                                    .font(.system(size: 13, weight: .bold))
                            }
                            .foregroundColor(.white)
                            .padding(.horizontal, 18)
                            .padding(.vertical, 9)
                            .background(
                                Capsule().fill(Color(hex: 0xFF5500))
                            )
                            .shadow(color: Color.black.opacity(0.25), radius: 3, x: 0, y: 1)
                        }
                        .buttonStyle(.plain)
                        
                        // Refresh Button
                        Button(action: triggerRefresh) {
                            HStack(spacing: 6) {
                                Image(systemName: "arrow.clockwise")
                                    .font(.system(size: 11.5, weight: .semibold))
                                    .rotationEffect(.degrees(isSpinning ? 360 : 0))
                                
                                Text(LocalizedStringKey("wave.refreshStream"))
                                    .font(.system(size: 12.5, weight: .medium))
                            }
                            .foregroundColor(.white)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 9)
                            .background(
                                Capsule().fill(Color.white.opacity(0.10))
                            )
                            .overlay(
                                Capsule().stroke(Color.white.opacity(0.18), lineWidth: 0.8)
                            )
                        }
                        .buttonStyle(.plain)
                        .disabled(isLoading)
                    }
                    .padding(.top, 4)
                }
                
                Spacer()
                
                // Real 3D Layered Album Art Showcase (Pure artwork, zero white glare)
                if !seedTracks.isEmpty {
                    artworkDeckView
                        .padding(.trailing, 12)
                }
            }
            .padding(22)
        }
        .frame(minHeight: 180)
    }
    
    // MARK: - Layered Album Artwork Stack
    
    private var artworkDeckView: some View {
        let displaySeeds = Array(seedTracks.prefix(3))
        return ZStack {
            // Subtle warm SoundCloud ambient glow behind deck (clean, no washed-out white)
            Circle()
                .fill(Color(hex: 0xFF5500).opacity(0.14))
                .frame(width: 130, height: 130)
                .blur(radius: 26)
            
            if displaySeeds.count >= 3 {
                RemoteImage(url: displaySeeds[2].artworkURL ?? displaySeeds[2].user.avatarURL, cornerRadius: 10)
                    .frame(width: 78, height: 78)
                    .rotationEffect(.degrees(-9))
                    .offset(x: -28, y: -6)
                    .shadow(color: Color.black.opacity(0.40), radius: 6, x: -2, y: 3)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(Color.white.opacity(0.15), lineWidth: 0.8)
                    )
                    .opacity(0.80)
            }
            
            if displaySeeds.count >= 2 {
                RemoteImage(url: displaySeeds[1].artworkURL ?? displaySeeds[1].user.avatarURL, cornerRadius: 10)
                    .frame(width: 84, height: 84)
                    .rotationEffect(.degrees(8))
                    .offset(x: 24, y: -3)
                    .shadow(color: Color.black.opacity(0.40), radius: 6, x: 2, y: 3)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(Color.white.opacity(0.15), lineWidth: 0.8)
                    )
                    .opacity(0.90)
            }
            
            if let frontTrack = displaySeeds.first {
                RemoteImage(url: frontTrack.artworkURL ?? frontTrack.user.avatarURL, cornerRadius: 12)
                    .frame(width: 96, height: 96)
                    .shadow(color: Color.black.opacity(0.50), radius: 8, x: 0, y: 4)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(Color.white.opacity(0.20), lineWidth: 0.8)
                    )
            }
        }
        .frame(width: 160, height: 110)
    }
    
    // MARK: - Bottom Stream Footer
    
    private var bottomStreamFooter: some View {
        HStack {
            Spacer()
            
            if waveService.isLoadingMore {
                HStack(spacing: 8) {
                    ProgressView()
                        .scaleEffect(0.75)
                    
                    Text(LocalizedStringKey("wave.pickingTracks"))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 16)
            } else {
                HStack(spacing: 12) {
                    HStack(spacing: 6) {
                        Image(systemName: "infinity")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(Color(hex: 0xFF5500))
                        
                        Text(LocalizedStringKey("wave.infiniteStreamHint"))
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    }
                    
                    if waveTracks.count < 90 {
                        Button(action: {
                            waveService.loadMoreTracks(likes: likes, player: player, force: true)
                        }) {
                            Text(LocalizedStringKey("wave.loadMore"))
                                .font(.system(size: 11.5, weight: .medium))
                                .foregroundColor(.primary)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .background(Capsule().fill(Color.primary.opacity(0.08)))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 18)
            }
            
            Spacer()
        }
    }
    
    // MARK: - States
    
    private var loadingState: some View {
        VStack(spacing: 14) {
            ProgressView()
                .scaleEffect(1.1)
            
            Text(LocalizedStringKey("wave.tuningWave"))
                .font(.system(size: 13.5, weight: .medium))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.vertical, 60)
    }
    
    private var emptyLikesState: some View {
        VStack(spacing: 16) {
            Image(systemName: "heart.slash")
                .font(.system(size: 44))
                .foregroundColor(.secondary.opacity(0.5))
            
            VStack(spacing: 6) {
                Text(LocalizedStringKey("wave.noLikesYet"))
                    .font(.system(size: 16, weight: .bold))
                
                Text(LocalizedStringKey("wave.noLikesHint"))
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 380)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
    }
    
    // MARK: - Actions
    
    private func togglePlayWave() {
        guard !waveTracks.isEmpty else { return }
        
        if isPlayingWave {
            player.togglePlayback()
        } else {
            if let current = player.currentStream, let idx = waveTracks.firstIndex(of: current) {
                player.play(waveTracks, from: idx, isWave: true)
            } else {
                player.play(waveTracks, from: 0, isWave: true)
            }
        }
    }
    
    private func triggerRefresh() {
        withAnimation(.easeInOut(duration: 0.45)) {
            isSpinning = true
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
            isSpinning = false
        }
        
        waveService.generateWave(likes: likes, force: true)
    }
}
