//
//  StreamPlayer.swift
//  Nuage
//
//  Created by Laurin Brandner on 25.12.19.
//  Copyright © 2019 Laurin Brandner. All rights reserved.
//

import AppKit
import SwiftUI
import AVFoundation
import Combine
import MediaPlayer
import URLImage
import SoundCloud

protocol Streamable {
    
    func prepare() -> AnyPublisher<AVURLAsset, Error>
    
}

private let volumeKey = "volume"

public enum RepeatMode: Int, CaseIterable {
    case off = 0
    case all = 1
    case one = 2
}
    
class StreamPlayer: ObservableObject {
    
    public static weak var shared: StreamPlayer?
    
    private var subscriptions = Set<AnyCancellable>()
    
    private var player: AVPlayer
    private(set) var queue = [Track]() {
        didSet {
            reloadQueueOrder()
        }
    }
    private var queueOrder = [Int]()
    private(set) var currentStreamIndex: Int? {
        didSet {
            currentStream = self.currentStreamIndex.map { queue[queueOrder[$0]] }
        }
    }
    
    @Published private(set) var currentStream: Track?
    @Published var isWaveMode: Bool = false
    
    var playbackQueue: [Track] {
        guard queueOrder.count == queue.count else {
            return queue
        }
        return queueOrder.compactMap { idx in
            guard idx >= 0 && idx < queue.count else { return nil }
            return queue[idx]
        }
    }
    
    @AppStorage("shuffleQueue") var shuffleQueue: Bool = false {
        didSet {
            reloadQueueOrder()
        }
    }
    @AppStorage("repeatQueue") var repeatQueue: Bool = false
    @AppStorage("repeatModeRaw") var repeatModeRaw: Int = 0
    
    var repeatMode: RepeatMode {
        get { RepeatMode(rawValue: repeatModeRaw) ?? (repeatQueue ? .all : .off) }
        set {
            objectWillChange.send()
            repeatModeRaw = newValue.rawValue
            repeatQueue = (newValue != .off)
        }
    }
    
    func toggleRepeatMode() {
        switch repeatMode {
        case .off: repeatMode = .all
        case .all: repeatMode = .one
        case .one: repeatMode = .off
        }
    }
    
    @Published var volume: Float = 0.5 {
        didSet {
            if volume > 1 { volume = 1 }
            else if volume < 0 { volume = 0 }
            
            player.volume = volume
            UserDefaults.standard.set(volume, forKey: volumeKey)
        }
    }
    
    private var shouldSeek = true
    @Published var progress: TimeInterval = 0.0 {
        didSet {
            if shouldSeek {
                let time = CMTime(seconds: progress, preferredTimescale: 1)
                player.seek(to: time)
                updateNowPlayingInfo(with: time)
            }
        }
    }
    
    @Published private(set) var isPlaying = false
    
    // MARK: - Initialization
    
    init() {
        self.player = AVPlayer()
        Self.shared = self
        self.player.allowsExternalPlayback = false
        
        let defaults = UserDefaults.standard
        if defaults.object(forKey: volumeKey) != nil {
            self.volume = defaults.float(forKey: volumeKey)
        }
        
        let interval = CMTime(value: 1, timescale: 1)
        player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            guard let self = self else { return }
            self.shouldSeek = false
            self.progress = time.seconds
            self.shouldSeek = true
        }
        
        player.publisher(for: \.timeControlStatus)
            .map { $0 != .paused }
            .assign(to: \.isPlaying, on: self)
            .store(in: &subscriptions)
        
        player.publisher(for: \.timeControlStatus)
            .sink { _ in self.updateNowPlayingInfo() }
            .store(in: &subscriptions)
        
        addRemoteCommandTargets()
        setupKeyboardMonitor()
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    // MARK: - Playback
    
    func restartPlayback() {
        player.seek(to: .zero)
        player.play()
    }
    
    func togglePlayback() {
        if isPlaying {
            pause()
        }
        else {
            resume()
        }
    }
    
    func resume(from startIndex: Int? = nil) {
        guard let idx = startIndex ?? currentStreamIndex, idx < queue.count else { return }
        
        let newStream = queue[queueOrder[idx]]
        if currentStream == newStream {
            player.play()
        }
        else {
            self.currentStreamIndex = idx
            self.shouldSeek = false
            self.progress = 0
            self.shouldSeek = true
            
            let track = currentStream!
            track.prepare()
                .receive(on: RunLoop.main)
                .sink(receiveCompletion: { [weak self] completion in
                    if case let .failure(error) = completion  {
                        print("Failed to stream track: \(error)")
                        guard let self = self else { return }
                        self.player.replaceCurrentItem(with: nil)
                        VoiceControlService.shared.triggerCustomHUD(NSLocalizedString("player.hud.trackUnavailable", comment: ""), icon: "exclamationmark.triangle")
                        if self.queue.count > idx + 1 || self.isWaveMode {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
                                self?.advanceForward()
                            }
                        } else {
                            self.pause()
                        }
                    }
                }, receiveValue: { [weak self] asset in
                    guard let self = self else { return }
                    
                    let item = AVPlayerItem(asset: asset)
                    EqualizerService.shared.attach(to: item)
                    
                    self.player.replaceCurrentItem(with: item)
                    self.player.play()
                    
                    NotificationCenter.default.addObserver(self, selector: #selector(self.itemDidFinishPlaying), name: Notification.Name.AVPlayerItemDidPlayToEndTime, object: item)
                    
                    self.updateNowPlayingInfo()
                }).store(in: &subscriptions)
        }
    }
    
    func pause() {
        player.pause()
    }
    
    func play(_ tracks: [Track], from idx: Int, isWave: Bool? = nil) {
        guard !(currentStreamIndex == idx && queue == tracks) else {
            restartPlayback()
            return
        }
        
        pause()
        queue = tracks
        
        if let isWave = isWave {
            self.isWaveMode = isWave
        } else {
            self.isWaveMode = (!tracks.isEmpty && tracks == WaveService.shared.waveTracks)
        }
        
        if shuffleQueue {
            let otherIndices = Array(0..<tracks.count).filter { $0 != idx }.shuffled()
            queueOrder = [idx] + otherIndices
            resume(from: 0)
        } else {
            queueOrder = Array(0..<tracks.count)
            resume(from: idx)
        }
    }
    
    @objc func itemDidFinishPlaying() {
        if repeatMode == .one {
            restartPlayback()
        } else {
            advanceForward()
        }
    }
    
    @objc func advanceForward() {
        guard let idx = currentStreamIndex else { return }
        player.replaceCurrentItem(with: nil)
        if queue.count > idx + 1 {
            resume(from: idx + 1)
            if isWaveMode && queue.count - (idx + 1) <= 6 {
                WaveService.shared.loadMoreTracks(player: self)
            } else if queue.count - (idx + 1) <= 2 && !WaveService.shared.cachedLikes.isEmpty {
                let existingIDs = Set(queue.map { $0.id })
                let available = WaveService.shared.cachedLikes.filter { !existingIDs.contains($0.id) }
                let picks = Array((available.isEmpty ? WaveService.shared.cachedLikes : available).shuffled().prefix(6))
                if !picks.isEmpty {
                    enqueue(picks)
                }
            }
        }
        else if repeatMode != .off {
            resume(from: 0)
        }
        else if isWaveMode {
            // "Моя волна" is endless: auto-replenish queue and keep playing smoothly
            WaveService.shared.loadMoreTracks(player: self)
            if !queue.isEmpty {
                resume(from: 0)
            }
        }
        else if !WaveService.shared.cachedLikes.isEmpty {
            // Auto-replenish queue when the last track finishes so music never stops abruptly
            let existingIDs = Set(queue.map { $0.id })
            let available = WaveService.shared.cachedLikes.filter { !existingIDs.contains($0.id) }
            let picks = Array((available.isEmpty ? WaveService.shared.cachedLikes : available).shuffled().prefix(10))
            if !picks.isEmpty {
                enqueue(picks)
                resume(from: (currentStreamIndex ?? 0) + 1)
            } else {
                queue = []
                pause()
            }
        }
        else {
            queue = []
            pause()
        }
    }
    
    func advanceBackward() {
        guard let idx = currentStreamIndex else { return }
        
        if player.currentTime() < CMTime(value: 15, timescale: 1) {
            player.replaceCurrentItem(with: nil)
            if idx > 0 {
                resume(from: idx - 1)
            }
            else {
                currentStreamIndex = nil
            }
        }
        else {
            restartPlayback()
        }
    }
    
    func seekForward() {
        progress += 15
    }
    
    func seekBackward() {
        progress -= 15
    }
    
    func reset() {
        pause()
        player.replaceCurrentItem(with: nil)
        queue = []
        isWaveMode = false
        currentStreamIndex = nil
        DiscordRPCService.shared.clearPresence()
    }
    
    func enqueue(_ streams: [Track], playNext: Bool = false) {
        guard streams.count > 0 else { return }
        
        let startNewIdx = queue.count
        queue.append(contentsOf: streams)
        
        let newIndices = Array(startNewIdx..<queue.count)
        if playNext, let currentIdx = currentStreamIndex {
            queueOrder.insert(contentsOf: newIndices, at: currentIdx + 1)
        } else {
            if shuffleQueue {
                queueOrder.append(contentsOf: newIndices.shuffled())
            } else {
                queueOrder.append(contentsOf: newIndices)
            }
        }
    }
    
    func playTrackInQueue(atPlaybackIndex index: Int) {
        guard index >= 0 && index < queueOrder.count else { return }
        resume(from: index)
    }
    
    func removeFromQueue(atPlaybackIndex index: Int) {
        guard index >= 0 && index < queueOrder.count else { return }
        let originalIdx = queueOrder[index]
        queueOrder.remove(at: index)
        queueOrder = queueOrder.map { $0 > originalIdx ? $0 - 1 : $0 }
        queue.remove(at: originalIdx)
        
        if let current = currentStreamIndex {
            if index < current {
                currentStreamIndex = current - 1
            } else if index == current {
                if current < queueOrder.count {
                    resume(from: current)
                } else if !queueOrder.isEmpty {
                    resume(from: queueOrder.count - 1)
                } else {
                    reset()
                }
            }
        }
    }
    
    func clearUpcomingQueue() {
        guard let current = currentStreamIndex, current + 1 < queueOrder.count else { return }
        let toRemoveOriginal = Array((current + 1)..<queueOrder.count).map { queueOrder[$0] }.sorted(by: >)
        queueOrder.removeSubrange((current + 1)..<queueOrder.count)
        for idx in toRemoveOriginal {
            queue.remove(at: idx)
            queueOrder = queueOrder.map { $0 > idx ? $0 - 1 : $0 }
        }
    }
    
    private func reloadQueueOrder() {
        if !shuffleQueue {
            let current = currentStream
            queueOrder = Array(0..<queue.count)
            if let current = current, let idx = queue.firstIndex(of: current) {
                currentStreamIndex = idx
            }
        } else {
            if let current = currentStream, let currentQueueIdx = queue.firstIndex(of: current) {
                let otherIndices = Array(0..<queue.count).filter { $0 != currentQueueIdx }.shuffled()
                queueOrder = [currentQueueIdx] + otherIndices
                currentStreamIndex = 0
            } else {
                queueOrder = Array(0..<queue.count).shuffled()
            }
        }
    }
    
    // MARK: - MPNowPlayingInfoCenter
    
    private func addRemoteCommandTargets() {
        let center = MPRemoteCommandCenter.shared()
        
        center.togglePlayPauseCommand.isEnabled = true
        center.togglePlayPauseCommand.addTarget { [weak self] _ in
            self?.togglePlayback()
            return .success
        }
        
        center.playCommand.isEnabled = true
        center.playCommand.addTarget { [weak self] _ in
            self?.resume()
            return .success
        }
        
        center.pauseCommand.isEnabled = true
        center.pauseCommand.addTarget { [weak self] _ in
            self?.pause()
            return .success
        }
        
        center.nextTrackCommand.isEnabled = true
        center.nextTrackCommand.addTarget { [weak self] _ in
            self?.advanceForward()
            return .success
        }
        
        center.previousTrackCommand.isEnabled = true
        center.previousTrackCommand.addTarget { [weak self] _ in
            self?.advanceBackward()
            return .success
        }
        
        center.changePlaybackPositionCommand.isEnabled = true
        center.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let event = event as? MPChangePlaybackPositionCommandEvent else {
                return .commandFailed
            }
            self?.progress = event.positionTime
            return .success
        }
        
        // Listen for hardware media keys (Play/Pause, Next, Previous) globally
        NSEvent.addGlobalMonitorForEvents(matching: .systemDefined) { [weak self] event in
            guard event.subtype.rawValue == 8 else { return }
            let data = event.data1
            let keyCode = Int32((data & 0xFFFF0000) >> 16)
            let keyFlags = (data & 0x0000FFFF)
            let keyState = (((keyFlags & 0xFF00) >> 8)) == 0xA
            if keyState {
                switch keyCode {
                case 16, 19:
                    self?.togglePlayback()
                case 17, 20:
                    self?.advanceForward()
                case 18, 21:
                    self?.advanceBackward()
                default: break
                }
            }
        }
    }
    
    private func setupKeyboardMonitor() {
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self else { return event }
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            if flags == .command {
                switch event.keyCode {
                case 124: // Right arrow (Next)
                    self.advanceForward()
                    return nil
                case 123: // Left arrow (Prev)
                    self.advanceBackward()
                    return nil
                case 126: // Up arrow (Vol Up)
                    self.volume = min(1.0, self.volume + 0.05)
                    return nil
                case 125: // Down arrow (Vol Down)
                    self.volume = max(0.0, self.volume - 0.05)
                    return nil
                default:
                    break
                }
            }
            return event
        }
    }
    
    private func updateNowPlayingInfo(with time: CMTime? = nil) {
        let center = MPNowPlayingInfoCenter.default()
        guard let currentStream = currentStream else {
            center.nowPlayingInfo = nil
            DiscordRPCService.shared.clearPresence()
            return
        }
        
        var info = center.nowPlayingInfo
        let currentID = info?[MPMediaItemPropertyPersistentID] as? String
        let rawTime = (time ?? player.currentTime()).seconds
        let currentTime = (rawTime.isFinite && !rawTime.isNaN) ? max(0.0, rawTime) : 0.0
        let rate = isPlaying ? 1.0 : 0.0
        
        DiscordRPCService.shared.update(track: currentStream, isPlaying: isPlaying, progress: currentTime)
        
        if currentID == currentStream.id {
            info![MPNowPlayingInfoPropertyElapsedPlaybackTime] = currentTime
            info![MPNowPlayingInfoPropertyPlaybackRate] = rate
        }
        else {
            info = [
                MPMediaItemPropertyPersistentID: currentStream.id,
                MPMediaItemPropertyTitle: currentStream.title,
                MPMediaItemPropertyArtist: currentStream.user.username,
                MPMediaItemPropertyAssetURL: currentStream.permalinkURL,
                MPMediaItemPropertyPlaybackDuration: currentStream.duration,
                MPNowPlayingInfoPropertyElapsedPlaybackTime: currentTime,
                MPNowPlayingInfoPropertyPlaybackRate: rate
            ]
            
            let url = currentStream.artworkURL ?? currentStream.user.avatarURL
            URLImageService.shared.remoteImagePublisher(url)
                .sink(receiveCompletion: { _ in },
                      receiveValue: { imageInfo in
                    let image = NSImage(cgImage: imageInfo.cgImage, size: imageInfo.size)
                    let artwork = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
                    info![MPMediaItemPropertyArtwork] = artwork
                    
                    center.nowPlayingInfo = info
                })
                .store(in: &self.subscriptions)
        }
        
        center.nowPlayingInfo = info
        center.playbackState = isPlaying ? .playing : .paused
    }
    
}
