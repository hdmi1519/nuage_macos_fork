//
//  ModernProgressBar.swift
//  Nuage
//
//  Created on 03.10.2026.
//

import SwiftUI
import Combine
import SoundCloud

// MARK: - Timed Comments Service

@MainActor
public class TimedCommentsService: ObservableObject {
    public static let shared = TimedCommentsService()
    
    @Published public private(set) var comments: [Comment] = []
    @Published public private(set) var currentTrackID: String? = nil
    @Published public private(set) var isLoading: Bool = false
    @Published public var hoveredComment: Comment? = nil
    
    private var cache = [String: [Comment]]()
    private var cancellables = Set<AnyCancellable>()
    
    private init() {}
    
    public func fetchComments(for track: Track) {
        let trackID = track.id
        if currentTrackID == trackID && !comments.isEmpty {
            return
        }
        currentTrackID = trackID
        
        if let cached = cache[trackID] {
            self.comments = cached
            return
        }
        
        isLoading = true
        SoundCloud.shared.get(.comments(of: track))
            .receive(on: RunLoop.main)
            .sink(receiveCompletion: { [weak self] _ in
                self?.isLoading = false
            }, receiveValue: { [weak self] page in
                guard let self = self else { return }
                self.isLoading = false
                self.cache[trackID] = page.collection
                if self.currentTrackID == trackID {
                    self.comments = page.collection
                }
            })
            .store(in: &cancellables)
    }
    
    public func addComment(_ comment: Comment) {
        comments.insert(comment, at: 0)
        if let trackID = currentTrackID {
            var cached = cache[trackID] ?? []
            cached.insert(comment, at: 0)
            cache[trackID] = cached
        }
    }
    
    public func timedComments(for duration: TimeInterval) -> [Comment] {
        guard duration > 0 else { return [] }
        return comments.filter { comment in
            comment.timestamp > 0 && comment.timestamp <= duration
        }.sorted { $0.timestamp < $1.timestamp }
    }
    
    public func activeComment(at time: TimeInterval, window: TimeInterval = 3.5) -> Comment? {
        let matching = comments.filter { comment in
            comment.timestamp > 0 && (time >= comment.timestamp - 0.2) && (time <= comment.timestamp + window)
        }
        return matching.min(by: { abs(time - $0.timestamp) < abs(time - $1.timestamp) })
    }
    
    public func comment(near time: TimeInterval, threshold: TimeInterval = 3.5) -> Comment? {
        let matching = comments.filter { comment in
            comment.timestamp > 0 && abs(time - comment.timestamp) <= threshold
        }
        return matching.min(by: { abs(time - $0.timestamp) < abs(time - $1.timestamp) })
    }
}

// MARK: - Comment Capsule View

struct CommentCapsuleView: View {
    let comment: Comment
    var onSeek: (() -> Void)? = nil
    
    @State private var isHovered = false
    
    var body: some View {
        Button(action: { onSeek?() }) {
            HStack(alignment: .center, spacing: 9) {
                // User Avatar
                RemoteImage(url: comment.user.avatarURL, cornerRadius: 10)
                    .frame(width: 20, height: 20)
                    .clipShape(Circle())
                    .overlay(Circle().stroke(Color.white.opacity(0.25), lineWidth: 0.8))
                
                // Username
                Text(comment.user.username)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(Color(hex: 0xFF5500))
                    .lineLimit(1)
                
                // Timestamp badge
                Text(format(time: comment.timestamp))
                    .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
                    .foregroundColor(.white.opacity(0.85))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color.white.opacity(0.14)))
                
                // Comment text
                Text(comment.body)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(
                Capsule()
                    .fill(Color(nsColor: .windowBackgroundColor).opacity(0.96))
                    .shadow(color: Color.black.opacity(0.4), radius: 8, x: 0, y: 4)
            )
            .overlay(
                Capsule()
                    .stroke(isHovered ? Color(hex: 0xFF5500).opacity(0.8) : Color.white.opacity(0.22), lineWidth: 1)
            )
            .scaleEffect(isHovered ? 1.02 : 1.0)
            .animation(.easeInOut(duration: 0.15), value: isHovered)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .help(String(format: NSLocalizedString("player.clickToJump", comment: ""), format(time: comment.timestamp)))
    }
}

// MARK: - Modern Progress Bar

struct ModernProgressBar: View {
    @Binding var value: TimeInterval
    var duration: TimeInterval
    var showCommentMarkers: Bool = false
    var onSeek: ((TimeInterval) -> Void)? = nil
    
    @AppStorage("showTimedComments") private var showTimedComments: Bool = true
    @ObservedObject private var commentsService = TimedCommentsService.shared
    
    @State private var isHovering = false
    @State private var hoverX: CGFloat? = nil
    @State private var draggingValue: TimeInterval?
    
    var body: some View {
        let current = draggingValue ?? value
        let safeDuration = max(1, duration)
        let progress = min(max(0, current / safeDuration), 1.0)
        let font = Font.system(size: 11, design: .monospaced)
        
        let timedComments = (showTimedComments && showCommentMarkers) ? commentsService.timedComments(for: safeDuration) : []
        let activeComment = (showTimedComments && showCommentMarkers) ? (commentsService.hoveredComment ?? commentsService.activeComment(at: current, window: 3.5)) : nil
        
        HStack(spacing: 8) {
            Text(format(time: current))
                .font(font)
                .foregroundColor(.secondary)
                .frame(width: 44, alignment: .trailing)
            
            GeometryReader { geo in
                let width = geo.size.width
                let barHeight: CGFloat = isHovering ? 5 : 3.5
                
                ZStack(alignment: .leading) {
                    // Track Background
                    Capsule()
                        .fill(Color.primary.opacity(0.15))
                        .frame(height: barHeight)
                    
                    // Track Progress
                    Capsule()
                        .fill(Color(hex: 0xFF5500))
                        .frame(width: max(0, width * CGFloat(progress)), height: barHeight)
                    
                    // Comment Markers beneath the track (subtle 2px micro-dots that do not cut or fracture the progress bar)
                    if showTimedComments && showCommentMarkers && width > 0 {
                        let markers: [(id: String, x: CGFloat, isCurrent: Bool, isPassed: Bool)] = {
                            var list: [(id: String, x: CGFloat, isCurrent: Bool, isPassed: Bool)] = []
                            for comment in timedComments {
                                let cProg = min(max(0, comment.timestamp / safeDuration), 1.0)
                                let x = width * CGFloat(cProg)
                                let isCur = activeComment?.id == comment.id
                                let isPassed = cProg <= progress
                                
                                // Cluster close markers within 4pt to prevent visual clumps
                                if let last = list.last, abs(last.x - x) < 4 {
                                    if isCur {
                                        list[list.count - 1] = (comment.id, x, true, isPassed)
                                    }
                                    continue
                                }
                                list.append((comment.id, x, isCur, isPassed))
                            }
                            return list
                        }()
                        
                        ForEach(markers, id: \.id) { marker in
                            Circle()
                                .fill(
                                    marker.isCurrent
                                        ? Color(hex: 0xFF5500)
                                        : (marker.isPassed
                                            ? Color.white.opacity(0.7)
                                            : Color.white.opacity(0.3))
                                )
                                .frame(width: marker.isCurrent ? 3 : 2, height: marker.isCurrent ? 3 : 2)
                                .position(x: marker.x, y: (geo.size.height / 2) + (barHeight / 2) + 3.5)
                                .allowsHitTesting(false)
                        }
                    }
                    
                    // Knob
                    if isHovering || draggingValue != nil {
                        Circle()
                            .fill(Color.white)
                            .frame(width: 11, height: 11)
                            .shadow(color: Color.black.opacity(0.35), radius: 2, x: 0, y: 1)
                            .offset(x: max(0, min(width - 11, width * CGFloat(progress) - 5.5)))
                    }
                }
                .frame(maxHeight: .infinity, alignment: .center)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { gesture in
                            let percent = min(max(0, gesture.location.x / width), 1.0)
                            let newTime = TimeInterval(percent) * safeDuration
                            draggingValue = newTime
                        }
                        .onEnded { gesture in
                            let percent = min(max(0, gesture.location.x / width), 1.0)
                            let newTime = TimeInterval(percent) * safeDuration
                            draggingValue = nil
                            value = newTime
                            onSeek?(newTime)
                        }
                )
                .onContinuousHover { phase in
                    switch phase {
                    case .active(let location):
                        hoverX = location.x
                        if showTimedComments {
                            let hoverTime = (location.x / max(1, width)) * safeDuration
                            commentsService.hoveredComment = commentsService.comment(near: hoverTime, threshold: 3.5)
                        }
                    case .ended:
                        hoverX = nil
                        if showTimedComments {
                            commentsService.hoveredComment = nil
                        }
                    }
                }
            }
            .frame(height: 18)
            .onHover { isHovering = $0 }
            
            Text(format(time: duration))
                .font(font)
                .foregroundColor(.secondary)
                .frame(width: 44, alignment: .leading)
        }
    }
}
