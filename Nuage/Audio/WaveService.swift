//
//  WaveService.swift
//  Nuage
//
//  Created on 04.10.2026.
//

import SwiftUI
import Combine
import SoundCloud

final class WaveService: ObservableObject {
    
    static let shared = WaveService()
    
    @Published var waveTracks: [Track] = []
    @Published var seedTracks: [Track] = []
    @Published var isLoading: Bool = false
    @Published var isLoadingMore: Bool = false
    
    var cachedLikes: [Track] = []
    private var lastLoadMoreTime: Date = .distantPast
    private var loadTask: Task<Void, Never>? = nil
    private var loadMoreTask: Task<Void, Never>? = nil
    
    private var subscriptions = Set<AnyCancellable>()
    
    private init() {
        loadCachedLikes()
    }
    
    func loadCachedLikes() {
        if let data = UserDefaults.standard.data(forKey: "likes"),
           let tracks = try? JSONDecoder().decode([Track].self, from: data),
           !tracks.isEmpty {
            self.cachedLikes = tracks
        }
    }
    
    // MARK: - Playback Helper
    
    func playWave(likes: [Track] = [], player: StreamPlayer, force: Bool = false) {
        if !likes.isEmpty {
            self.cachedLikes = likes
        } else if cachedLikes.isEmpty {
            loadCachedLikes()
        }
        
        let sourceLikes = !cachedLikes.isEmpty ? cachedLikes : likes
        
        if !force && !waveTracks.isEmpty {
            player.play(waveTracks, from: 0, isWave: true)
            return
        }
        
        if !sourceLikes.isEmpty {
            if !force && waveTracks.isEmpty {
                let initialBatch = Array(sourceLikes.shuffled().prefix(50))
                self.waveTracks = initialBatch
                player.play(initialBatch, from: 0, isWave: true)
            }
            generateWave(likes: sourceLikes, force: true, autoPlayOnCompletion: true)
        } else {
            // Cold start fallback: fetch likes from SoundCloud live
            if let user = SoundCloud.shared.user {
                SoundCloud.shared.get(all: .trackLikes(of: user))
                    .map { $0.map { $0.item } }
                    .receive(on: RunLoop.main)
                    .sink(receiveCompletion: { _ in }, receiveValue: { [weak self] fetched in
                        guard let self = self, !fetched.isEmpty else { return }
                        self.cachedLikes = fetched
                        player.play(fetched.shuffled(), from: 0, isWave: true)
                        self.generateWave(likes: fetched, force: true, autoPlayOnCompletion: true)
                    })
                    .store(in: &subscriptions)
            } else {
                // If user is not yet loaded, try stream or history
                SoundCloud.shared.get(all: .history())
                    .map { (items: [HistoryItem]) -> [Track] in items.map { $0.track } }
                    .receive(on: RunLoop.main)
                    .sink(receiveCompletion: { _ in }, receiveValue: { [weak self] (historyTracks: [Track]) in
                        guard let self = self, !historyTracks.isEmpty else { return }
                        self.cachedLikes = historyTracks
                        player.play(historyTracks.shuffled(), from: 0, isWave: true)
                        self.generateWave(likes: historyTracks, force: true, autoPlayOnCompletion: true)
                    })
                    .store(in: &subscriptions)
            }
        }
    }
    
    // MARK: - Initial Wave Generation
    
    func generateWave(likes: [Track], force: Bool = false, autoPlayOnCompletion: Bool = false) {
        self.cachedLikes = likes
        guard !likes.isEmpty else {
            waveTracks = []
            seedTracks = []
            isLoading = false
            return
        }
        
        if !force && !waveTracks.isEmpty {
            return
        }
        
        loadTask?.cancel()
        loadMoreTask?.cancel()
        isLoading = true
        
        // Pick 6 diverse seeds across different liked artists
        var artistDict: [String: [Track]] = [:]
        for track in likes {
            artistDict[track.user.username, default: []].append(track)
        }
        
        var diverseSeeds: [Track] = []
        for (_, tracks) in artistDict.shuffled() {
            if let randomTrack = tracks.randomElement() {
                diverseSeeds.append(randomTrack)
            }
            if diverseSeeds.count >= 6 { break }
        }
        
        if diverseSeeds.count < 6 {
            for track in likes.shuffled() {
                if !diverseSeeds.contains(track) {
                    diverseSeeds.append(track)
                }
                if diverseSeeds.count >= 6 { break }
            }
        }
        self.seedTracks = diverseSeeds
        
        loadTask = Task { @MainActor in
            var collectedTracks: [Track] = []
            
            // Fetch stations concurrently in parallel for high speed and variety
            await withTaskGroup(of: [Track]?.self) { group in
                for seed in diverseSeeds {
                    group.addTask {
                        if Task.isCancelled { return nil }
                        if let station = await self.fetchStation(for: seed) {
                            if Task.isCancelled { return nil }
                            if let directTracks = station.tracks, !directTracks.isEmpty {
                                return directTracks
                            } else if let trackIDs = station.trackIDs, !trackIDs.isEmpty {
                                let sampleIDs = Array(trackIDs.prefix(12))
                                return await self.fetchTracks(ids: sampleIDs)
                            }
                        }
                        return nil
                    }
                }
                
                for await result in group {
                    if let tracks = result {
                        collectedTracks.append(contentsOf: tracks)
                    }
                }
            }
            
            if !Task.isCancelled {
                finalizeWave(collected: collectedTracks, seeds: diverseSeeds, likes: likes, autoPlay: autoPlayOnCompletion)
            }
        }
    }
    
    // MARK: - Infinite Wave Replenishment (Strictly controlled & throttled)
    
    func loadMoreTracks(likes: [Track]? = nil, player: StreamPlayer? = nil, force: Bool = false) {
        let sourceLikes = (likes?.isEmpty == false ? likes : nil) ?? cachedLikes
        
        guard !sourceLikes.isEmpty, !isLoading, !isLoadingMore else { return }
        guard waveTracks.count < 100 else { return }
        
        if !force {
            guard Date().timeIntervalSince(lastLoadMoreTime) > 20 else { return }
            guard let player = player, player.isPlaying && player.isWaveMode else { return }
        }
        
        lastLoadMoreTime = Date()
        isLoadingMore = true
        
        let availableLikes = sourceLikes.shuffled()
        let count = min(3, availableLikes.count)
        let selectedSeeds = Array(availableLikes.prefix(count))
        
        loadMoreTask?.cancel()
        loadMoreTask = Task { @MainActor in
            var collectedTracks: [Track] = []
            
            await withTaskGroup(of: [Track]?.self) { group in
                for seed in selectedSeeds {
                    group.addTask {
                        if Task.isCancelled { return nil }
                        if let station = await self.fetchStation(for: seed) {
                            if Task.isCancelled { return nil }
                            if let directTracks = station.tracks, !directTracks.isEmpty {
                                return directTracks
                            } else if let trackIDs = station.trackIDs, !trackIDs.isEmpty {
                                let sampleIDs = Array(trackIDs.prefix(10))
                                return await self.fetchTracks(ids: sampleIDs)
                            }
                        }
                        return nil
                    }
                }
                
                for await result in group {
                    if let tracks = result {
                        collectedTracks.append(contentsOf: tracks)
                    }
                }
            }
            
            if Task.isCancelled {
                self.isLoadingMore = false
                return
            }
            
            var existingIDs = Set(self.waveTracks.map { $0.id })
            var newTracks: [Track] = []
            
            for track in collectedTracks.shuffled() {
                if !existingIDs.contains(track.id) && newTracks.count < 20 {
                    existingIDs.insert(track.id)
                    newTracks.append(track)
                }
            }
            
            // Add 1-2 random unplayed likes as familiar anchor points
            for liked in sourceLikes.shuffled() {
                if !existingIDs.contains(liked.id) {
                    existingIDs.insert(liked.id)
                    newTracks.append(liked)
                    break
                }
            }
            
            if !newTracks.isEmpty {
                self.waveTracks.append(contentsOf: newTracks)
                if let player = player, player.isWaveMode {
                    player.enqueue(newTracks)
                }
            }
            
            self.isLoadingMore = false
        }
    }
    
    // MARK: - Helpers
    
    private func finalizeWave(collected: [Track], seeds: [Track], likes: [Track], autoPlay: Bool = false) {
        var finalPlaylist: [Track] = []
        var seenIDs = Set<String>()
        
        for track in collected.shuffled() {
            if !seenIDs.contains(track.id) {
                seenIDs.insert(track.id)
                finalPlaylist.append(track)
            }
        }
        
        // Intersperse about 20% favorites from user's full likes library
        let sampleLikes = likes.shuffled().prefix(max(3, finalPlaylist.count / 4))
        for (i, likedTrack) in sampleLikes.enumerated() {
            if !seenIDs.contains(likedTrack.id) {
                seenIDs.insert(likedTrack.id)
                let insertIndex = min(finalPlaylist.count, (i + 1) * 3)
                finalPlaylist.insert(likedTrack, at: insertIndex)
            }
        }
        
        if finalPlaylist.count < 5 {
            for track in likes.shuffled() {
                if !seenIDs.contains(track.id) {
                    seenIDs.insert(track.id)
                    finalPlaylist.append(track)
                }
            }
        }
        
        // Cap initial wave to a clean 45-50 tracks
        self.waveTracks = Array(finalPlaylist.prefix(50))
        self.isLoading = false
        
        if autoPlay, let player = StreamPlayer.shared {
            player.play(self.waveTracks, from: 0, isWave: true)
        }
    }
    
    private func fetchStation(for track: Track) async -> SystemPlaylist? {
        await withCheckedContinuation { continuation in
            var cancellable: AnyCancellable?
            var didResume = false
            cancellable = SoundCloud.shared.get(.trackStation(basedOn: track))
                .receive(on: RunLoop.main)
                .first()
                .sink(receiveCompletion: { _ in
                    if !didResume {
                        didResume = true
                        continuation.resume(returning: nil)
                    }
                    _ = cancellable
                }, receiveValue: { playlist in
                    if !didResume {
                        didResume = true
                        continuation.resume(returning: playlist)
                    }
                })
        }
    }
    
    private func fetchTracks(ids: [String]) async -> [Track]? {
        await withCheckedContinuation { continuation in
            var cancellable: AnyCancellable?
            var didResume = false
            cancellable = SoundCloud.shared.get(.tracks(ids))
                .receive(on: RunLoop.main)
                .first()
                .sink(receiveCompletion: { _ in
                    if !didResume {
                        didResume = true
                        continuation.resume(returning: nil)
                    }
                    _ = cancellable
                }, receiveValue: { tracks in
                    if !didResume {
                        didResume = true
                        continuation.resume(returning: tracks)
                    }
                })
        }
    }
}
