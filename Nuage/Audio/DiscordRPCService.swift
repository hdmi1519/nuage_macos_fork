//
//  DiscordRPCService.swift
//  Nuage
//
//  Created by hdmi1519 on 04.10.2026.
//

import Foundation
import Combine
import AppKit
import SoundCloud
import Darwin

// MARK: - Discord RPC Models

private struct DiscordHandshake: Encodable {
    let v: Int = 1
    let client_id: String
}

private struct DiscordButton: Encodable {
    let label: String
    let url: String
}

private struct DiscordAssets: Encodable {
    let large_image: String?
    let large_text: String?
    let small_image: String?
    let small_text: String?
}

private struct DiscordTimestamps: Encodable {
    let start: Int?
    let end: Int?
}

private struct DiscordActivity: Encodable {
    let type: Int = 2 // 2 = Listening to
    let name: String
    let details: String
    let state: String
    let timestamps: DiscordTimestamps?
    let assets: DiscordAssets?
    let buttons: [DiscordButton]?
}

private struct DiscordActivityArgs: Encodable {
    let pid: Int32
    let activity: DiscordActivity?
}

private struct DiscordCommandPayload: Encodable {
    let cmd: String = "SET_ACTIVITY"
    let args: DiscordActivityArgs
    let nonce: String
}

// MARK: - DiscordRPCService

public final class DiscordRPCService: ObservableObject {
    
    public static let shared = DiscordRPCService()
    
    private let clientID = "802958833214423081" // Registered SoundCloud Discord Application ID
    private let defaultLogoURL = "https://a-v2.sndcdn.com/assets/images/sc-icons/ios-a62dfc8f.png"
    
    @Published public private(set) var isConnected: Bool = false
    
    private var socketFD: Int32 = -1
    private let queue = DispatchQueue(label: "ch.laurinbrandner.nuage.discord-rpc", qos: .utility)
    private var reconnectTimer: DispatchSourceTimer?
    private var subscriptions = Set<AnyCancellable>()
    
    // Cached state to prevent redundant packets
    private var lastTrackID: String?
    private var lastIsPlaying: Bool?
    private var lastReportedProgress: Double = -1
    
    private init() {
        setupObservers()
        startConnectionLoop()
    }
    
    deinit {
        stopConnectionLoop()
        disconnect()
    }
    
    private var isEnabled: Bool {
        UserDefaults.standard.object(forKey: "enableDiscordPresence") as? Bool ?? true
    }
    
    // MARK: - Setup & Observers
    
    private func setupObservers() {
        NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self = self else { return }
                if self.isEnabled {
                    self.triggerCurrentTrackUpdate()
                } else {
                    self.clearPresence()
                }
            }
            .store(in: &subscriptions)
        
        NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)
            .sink { [weak self] _ in
                self?.clearPresence()
                self?.disconnect()
            }
            .store(in: &subscriptions)
    }
    
    private func startConnectionLoop() {
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now(), repeating: .seconds(8))
        timer.setEventHandler { [weak self] in
            guard let self = self else { return }
            guard self.isEnabled else { return }
            if self.socketFD < 0 {
                self.tryConnect()
            }
        }
        timer.resume()
        self.reconnectTimer = timer
    }
    
    private func stopConnectionLoop() {
        reconnectTimer?.cancel()
        reconnectTimer = nil
    }
    
    // MARK: - Socket Connection (UNIX Domain Socket)
    
    private func candidateSocketPaths() -> [String] {
        var paths = [String]()
        
        let tmpDir = ProcessInfo.processInfo.environment["TMPDIR"] ?? ""
        let dirs = [tmpDir, "/tmp/", "/var/tmp/"].filter { !$0.isEmpty }
        
        for dir in dirs {
            let normalizedDir = dir.hasSuffix("/") ? dir : dir + "/"
            for i in 0...9 {
                let p = "\(normalizedDir)discord-ipc-\(i)"
                if FileManager.default.fileExists(atPath: p) {
                    paths.append(p)
                }
            }
        }
        
        if paths.isEmpty {
            for dir in dirs {
                let normalizedDir = dir.hasSuffix("/") ? dir : dir + "/"
                paths.append("\(normalizedDir)discord-ipc-0")
            }
        }
        
        return paths
    }
    
    private func tryConnect() {
        guard isEnabled else { return }
        disconnect()
        
        let paths = candidateSocketPaths()
        for path in paths {
            let fd = socket(AF_UNIX, SOCK_STREAM, 0)
            guard fd >= 0 else { continue }
            
            // Set socket send/recv timeout (2 seconds)
            var timeout = timeval(tv_sec: 2, tv_usec: 0)
            setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
            setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
            
            // Disable SIGPIPE
            var nosigpipe: Int32 = 1
            setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &nosigpipe, socklen_t(MemoryLayout<Int32>.size))
            
            var addr = sockaddr_un()
            addr.sun_family = sa_family_t(AF_UNIX)
            _ = withUnsafeMutablePointer(to: &addr.sun_path.0) { ptr in
                path.withCString { cstr in
                    strncpy(ptr, cstr, 103)
                }
            }
            
            let connectRes = withUnsafePointer(to: &addr) { ptr in
                ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                    connect(fd, sa, socklen_t(MemoryLayout<sockaddr_un>.size))
                }
            }
            
            if connectRes == 0 {
                self.socketFD = fd
                if performHandshake() {
                    print("[DiscordRPC] Connected to \(path)")
                    DispatchQueue.main.async {
                        self.isConnected = true
                        self.triggerCurrentTrackUpdate()
                    }
                    return
                } else {
                    close(fd)
                    self.socketFD = -1
                }
            } else {
                close(fd)
            }
        }
    }
    
    private func performHandshake() -> Bool {
        guard socketFD >= 0 else { return false }
        
        let handshakeObj = DiscordHandshake(client_id: clientID)
        guard let data = try? JSONEncoder().encode(handshakeObj),
              let jsonString = String(data: data, encoding: .utf8) else {
            return false
        }
        
        guard sendPacket(opcode: 0, payload: jsonString) else {
            return false
        }
        
        guard let (respOpcode, respPayload) = readPacket() else {
            return false
        }
        
        if respOpcode == 1 && respPayload.contains("DISPATCH") {
            return true
        }
        
        return false
    }
    
    private func disconnect() {
        if socketFD >= 0 {
            close(socketFD)
            socketFD = -1
        }
        if isConnected {
            DispatchQueue.main.async {
                self.isConnected = false
            }
        }
    }
    
    // MARK: - Packet I/O
    
    private func sendPacket(opcode: UInt32, payload: String) -> Bool {
        guard socketFD >= 0 else { return false }
        guard let data = payload.data(using: .utf8) else { return false }
        
        var headerData = Data()
        var op = opcode.littleEndian
        var len = UInt32(data.count).littleEndian
        headerData.append(Data(bytes: &op, count: MemoryLayout<UInt32>.size))
        headerData.append(Data(bytes: &len, count: MemoryLayout<UInt32>.size))
        
        let fullPacket = headerData + data
        let written = fullPacket.withUnsafeBytes { ptr -> Int in
            guard let baseAddress = ptr.baseAddress else { return -1 }
            return write(socketFD, baseAddress, fullPacket.count)
        }
        
        if written != fullPacket.count {
            disconnect()
            return false
        }
        return true
    }
    
    private func readPacket() -> (UInt32, String)? {
        guard socketFD >= 0 else { return nil }
        
        var headerBuffer = [UInt8](repeating: 0, count: 8)
        let headerRead = read(socketFD, &headerBuffer, 8)
        guard headerRead == 8 else {
            disconnect()
            return nil
        }
        
        let opcode = headerBuffer[0..<4].withUnsafeBytes { $0.load(as: UInt32.self) }.littleEndian
        let length = headerBuffer[4..<8].withUnsafeBytes { $0.load(as: UInt32.self) }.littleEndian
        
        guard length > 0 && length < 1024 * 1024 else { return (opcode, "") }
        
        var payloadBuffer = [UInt8](repeating: 0, count: Int(length))
        var totalRead = 0
        while totalRead < Int(length) {
            let n = read(socketFD, &payloadBuffer[totalRead], Int(length) - totalRead)
            guard n > 0 else {
                disconnect()
                return nil
            }
            totalRead += n
        }
        
        let payloadString = String(decoding: payloadBuffer, as: UTF8.self)
        return (opcode, payloadString)
    }
    
    // MARK: - Activity Management
    
    public func update(track: Track?, isPlaying: Bool, progress: Double) {
        queue.async { [weak self] in
            guard let self = self else { return }
            
            guard self.isEnabled else {
                self.clearPresenceInternal()
                return
            }
            
            guard let track = track else {
                self.clearPresenceInternal()
                return
            }
            
            if self.socketFD < 0 {
                self.tryConnect()
                guard self.socketFD >= 0 else { return }
            }
            
            // Clean progress & duration to prevent any NaN/infinite crashes
            let safeProgress: Double = (progress.isFinite && !progress.isNaN) ? max(0.0, progress) : 0.0
            let rawDuration = Double(track.duration)
            let safeDuration: Double = (rawDuration.isFinite && !rawDuration.isNaN) ? max(0.0, rawDuration) : 0.0
            
            // Throttle duplicate updates if track and state haven't changed and progress is close
            if self.lastTrackID == track.id,
               self.lastIsPlaying == isPlaying,
               abs(self.lastReportedProgress - safeProgress) < 2.0 && isPlaying {
                return
            }
            
            self.lastTrackID = track.id
            self.lastIsPlaying = isPlaying
            self.lastReportedProgress = safeProgress
            
            let pid = ProcessInfo.processInfo.processIdentifier
            let now = Date().timeIntervalSince1970
            
            // Discord timestamps must be UNIX epoch in SECONDS
            var timestamps: DiscordTimestamps? = nil
            if isPlaying && safeDuration > 0 {
                let clampedProgress = min(safeProgress, safeDuration)
                let startSec = Int(now - clampedProgress)
                let endSec = Int(now - clampedProgress + safeDuration)
                timestamps = DiscordTimestamps(start: startSec, end: endSec)
            }
            
            let artworkURLStr = track.artworkURL?.absoluteString ?? track.user.avatarURL.absoluteString
            let statusText = isPlaying ? "Playing" : "Paused"
            let assets = DiscordAssets(
                large_image: artworkURLStr,
                large_text: track.title,
                small_image: self.defaultLogoURL,
                small_text: statusText
            )
            
            var buttons: [DiscordButton]? = nil
            let permalink = track.permalinkURL.absoluteString
            if !permalink.isEmpty && (permalink.hasPrefix("http://") || permalink.hasPrefix("https://")) {
                buttons = [DiscordButton(label: "Listen on SoundCloud", url: permalink)]
            }
            
            let activity = DiscordActivity(
                name: track.title,
                details: track.title,
                state: track.user.username,
                timestamps: timestamps,
                assets: assets,
                buttons: buttons
            )
            
            let payload = DiscordCommandPayload(
                args: DiscordActivityArgs(pid: pid, activity: activity),
                nonce: UUID().uuidString
            )
            
            if let data = try? JSONEncoder().encode(payload),
               let jsonString = String(data: data, encoding: .utf8) {
                let sent = self.sendPacket(opcode: 1, payload: jsonString)
                if sent {
                    print("[DiscordRPC] Updated activity: \(track.title) - \(track.user.username) (playing: \(isPlaying))")
                }
            }
        }
    }
    
    public func clearPresence() {
        queue.async { [weak self] in
            self?.clearPresenceInternal()
        }
    }
    
    private func clearPresenceInternal() {
        guard socketFD >= 0 else { return }
        
        lastTrackID = nil
        lastIsPlaying = nil
        lastReportedProgress = -1
        
        let pid = ProcessInfo.processInfo.processIdentifier
        let payload = DiscordCommandPayload(
            args: DiscordActivityArgs(pid: pid, activity: nil),
            nonce: UUID().uuidString
        )
        
        if let data = try? JSONEncoder().encode(payload),
           let jsonString = String(data: data, encoding: .utf8) {
            _ = sendPacket(opcode: 1, payload: jsonString)
            print("[DiscordRPC] Cleared activity")
        }
    }
    
    private func triggerCurrentTrackUpdate() {
        DispatchQueue.main.async {
            guard let player = StreamPlayer.shared else { return }
            DiscordRPCService.shared.update(
                track: player.currentStream,
                isPlaying: player.isPlaying,
                progress: player.progress
            )
        }
    }
}
