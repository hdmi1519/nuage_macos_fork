//
//  TrackDetail.swift
//  Nuage
//
//  Created by Laurin Brandner on 18.11.20.
//  Copyright © 2020 Laurin Brandner. All rights reserved.
//

import SwiftUI
import Combine
import SoundCloud
import Introspect

struct TrackDetail: View {
    
    var track: Track
    
    @State private var subscriptions = Set<AnyCancellable>()
    @State private var isHoveringArtwork = false
    @State private var isCopied = false
    
    // Comments State
    @State private var comments: [Comment] = []
    @State private var nextPageURL: URL?
    @State private var isLoadingComments = true
    @State private var isLoadingMoreComments = false
    @State private var commentsErrorMessage: String?
    
    // Comment Input State
    @State private var commentText = ""
    @State private var isSubmittingComment = false
    @State private var attachTimestamp = false
    @State private var submitErrorMessage: String?
    @State private var replyingTo: Comment? = nil
    @FocusState private var isCommentFieldFocused: Bool
    
    @EnvironmentObject private var player: StreamPlayer
    @Environment(\.likes) private var likes: [Track]
    @Environment(\.posts) private var posts: [Post]
    @Environment(\.toggleLikeTrack) private var toggleLikeTrack: (Track) -> () -> ()
    @Environment(\.toggleRepostTrack) private var toggleRepostTrack: (Track) -> () -> ()
    @Environment(\.onPlay) private var onPlay: () -> ()
    
    private var isCurrent: Bool {
        player.currentStream == track
    }
    
    private var isPlayingThis: Bool {
        isCurrent && player.isPlaying
    }
    
    private var isLiked: Bool {
        likes.contains(track)
    }
    
    private var isRepost: Bool {
        posts.filter { $0.isTrack && $0.isRepost }
            .compactMap { $0.tracks.first }
            .contains(track)
    }
    
    private func togglePlay() {
        if isCurrent {
            player.togglePlayback()
        } else {
            onPlay()
            if player.currentStream != track {
                player.play([track], from: 0)
            }
        }
    }
    
    private func copyLink() {
        let text = track.permalinkURL.absoluteString
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
    
    private func loadComments() {
        isLoadingComments = true
        commentsErrorMessage = nil
        SoundCloud.shared.get(.comments(of: track))
            .receive(on: RunLoop.main)
            .sink(receiveCompletion: { completion in
                isLoadingComments = false
                if case .failure(let error) = completion {
                    commentsErrorMessage = error.localizedDescription
                }
            }, receiveValue: { page in
                comments = page.collection
                nextPageURL = page.next
            })
            .store(in: &subscriptions)
    }
    
    private func loadNextCommentsPage() {
        guard let next = nextPageURL, !isLoadingMoreComments else { return }
        isLoadingMoreComments = true
        SoundCloud.shared.get(next: next)
            .receive(on: RunLoop.main)
            .sink(receiveCompletion: { _ in
                isLoadingMoreComments = false
            }, receiveValue: { page in
                comments.append(contentsOf: page.collection)
                nextPageURL = page.next
                isLoadingMoreComments = false
            })
            .store(in: &subscriptions)
    }
    
    private func replyToComment(_ comment: Comment) {
        replyingTo = comment
        let prefix = "@\(comment.user.username) "
        if !commentText.hasPrefix(prefix) {
            commentText = prefix + commentText
        }
        if comment.timestamp > 0 {
            attachTimestamp = true
        }
        isCommentFieldFocused = true
    }
    
    private func cancelReply() {
        if let reply = replyingTo {
            let prefix = "@\(reply.user.username) "
            if commentText.hasPrefix(prefix) {
                commentText.removeFirst(prefix.count)
            }
        }
        replyingTo = nil
    }

    private func postComment() {
        let text = commentText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isSubmittingComment else { return }
        
        isSubmittingComment = true
        submitErrorMessage = nil
        let timestamp: TimeInterval? = attachTimestamp ? (isCurrent ? player.progress : (replyingTo?.timestamp ?? nil)) : nil
        
        SoundCloud.shared.get(.comment(text, at: timestamp, on: track))
            .receive(on: RunLoop.main)
            .sink(receiveCompletion: { completion in
                isSubmittingComment = false
                if case .failure(let error) = completion {
                    submitErrorMessage = String(format: NSLocalizedString("track.submitError", comment: ""), error.localizedDescription)
                }
            }, receiveValue: { newComment in
                isSubmittingComment = false
                commentText = ""
                replyingTo = nil
                submitErrorMessage = nil
                withAnimation(.easeInOut(duration: 0.25)) {
                    comments.insert(newComment, at: 0)
                }
            })
            .store(in: &subscriptions)
    }
    
    private func deleteComment(_ comment: Comment) {
        withAnimation(.easeInOut(duration: 0.2)) {
            comments.removeAll { $0.id == comment.id }
        }
        SoundCloud.shared.perform(.deleteComment(comment))
            .receive(on: RunLoop.main)
            .sink(receiveCompletion: { completion in
                if case .failure(let err) = completion {
                    withAnimation {
                        comments.insert(comment, at: 0)
                    }
                    commentsErrorMessage = String(format: NSLocalizedString("track.deleteCommentError", comment: ""), err.localizedDescription)
                }
            }, receiveValue: { _ in })
            .store(in: &subscriptions)
    }
    
    var body: some View {
        let duration = format(time: track.duration)
        let url = track.artworkURL ?? track.user.avatarURL
        
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 18) {
                // 1. Hero Header
                HStack(alignment: .top, spacing: 20) {
                    // Artwork with play/pause overlay
                    ZStack {
                        RemoteImage(url: url, cornerRadius: 14)
                            .frame(width: 130, height: 130)
                            .shadow(color: Color.black.opacity(0.18), radius: 8, x: 0, y: 4)
                        
                        if isHoveringArtwork || isCurrent {
                            RoundedRectangle(cornerRadius: 14)
                                .fill(Color.black.opacity(isCurrent ? 0.45 : 0.35))
                                .frame(width: 130, height: 130)
                            
                            Button(action: togglePlay) {
                                ZStack {
                                    Circle()
                                        .fill(Color(hex: 0xFF5500))
                                        .frame(width: 46, height: 46)
                                        .shadow(color: Color.black.opacity(0.3), radius: 4, x: 0, y: 2)
                                    
                                    Image(systemName: isPlayingThis ? "pause.fill" : "play.fill")
                                        .font(.system(size: 19, weight: .bold))
                                        .foregroundColor(.white)
                                        .offset(x: isPlayingThis ? 0 : 2)
                                }
                            }
                            .buttonStyle(.plain)
                            .transition(.opacity)
                        }
                    }
                    .frame(width: 130, height: 130)
                    .onHover { inside in
                        withAnimation(.easeInOut(duration: 0.15)) {
                            isHoveringArtwork = inside
                        }
                    }
                    
                    // Info & Actions Column
                    VStack(alignment: .leading, spacing: 8) {
                        Text(LocalizedStringKey("track.single"))
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.secondary)
                        
                        Text(track.title)
                            .font(.system(size: 22, weight: .bold))
                            .lineLimit(2)
                            .foregroundColor(.primary)
                        
                        // Artist Link
                        NavigationLink(value: track.user) {
                            HStack(spacing: 8) {
                                RemoteImage(url: track.user.avatarURL, cornerRadius: 10)
                                    .frame(width: 20, height: 20)
                                    .clipShape(Circle())
                                Text(track.user.username)
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundColor(.primary)
                            }
                        }
                        .buttonStyle(.plain)
                        
                        // Stats Ribbon (Plays, Duration, Date)
                        HStack(spacing: 14) {
                            HStack(spacing: 4) {
                                Image(systemName: "play.fill")
                                    .font(.system(size: 9))
                                Text(format(count: track.playbackCount))
                            }
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                            
                            HStack(spacing: 4) {
                                Image(systemName: "clock")
                                    .font(.system(size: 9))
                                Text(duration)
                            }
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                            
                            HStack(spacing: 4) {
                                Image(systemName: "calendar")
                                    .font(.system(size: 9))
                                Text(track.date.formatted(date: .abbreviated, time: .omitted))
                            }
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                        }
                        
                        // Actions Row
                        HStack(spacing: 16) {
                            Button(action: { toggleLikeTrack(track)() }) {
                                HStack(spacing: 4) {
                                    Image(systemName: isLiked ? "heart.fill" : "heart")
                                    Text(format(count: track.likeCount))
                                }
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(isLiked ? Color(hex: 0xFF5500) : .secondary)
                            }
                            .buttonStyle(.plain)
                            
                            Button(action: { toggleRepostTrack(track)() }) {
                                HStack(spacing: 4) {
                                    Image(systemName: isRepost ? "arrow.triangle.2.circlepath.circle.fill" : "arrow.triangle.2.circlepath")
                                    Text(format(count: track.repostCount))
                                }
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(isRepost ? Color(hex: 0xFF5500) : .secondary)
                            }
                            .buttonStyle(.plain)
                            
                            Button(action: copyLink) {
                                HStack(spacing: 4) {
                                    Image(systemName: isCopied ? "checkmark" : "link")
                                    Text(LocalizedStringKey(isCopied ? "track.copied" : "track.copyLink"))
                                }
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(isCopied ? .green : .secondary)
                            }
                            .buttonStyle(.plain)
                            
                            NavigationLink(value: Station.track(track)) {
                                HStack(spacing: 4) {
                                    Image(systemName: "dot.radiowaves.left.and.right")
                                    Text(LocalizedStringKey("user.station"))
                                }
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.secondary)
                            }
                            .buttonStyle(.plain)
                            
                            Button {
                                NotificationCenter.default.post(name: .openTrackLyrics, object: track)
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: "quote.bubble.fill")
                                    Text(LocalizedStringKey("lyrics.title"))
                                }
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.secondary)
                            }
                            .buttonStyle(.plain)
                            
                            Button {
                                NotificationCenter.default.post(name: .openTrackPoster, object: track)
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: "photo")
                                    Text(LocalizedStringKey("poster.title"))
                                }
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.secondary)
                            }
                            .buttonStyle(.plain)
                            
                            Button {
                                NotificationCenter.default.post(name: .shareTrackToFriend, object: track)
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: "paperplane")
                                    Text(LocalizedStringKey("track.share"))
                                }
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.top, 2)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                
                // 2. Description (if present)
                if let description = track.description, !description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(LocalizedStringKey("track.description.header"))
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.primary)
                        
                        Text(description.withAttributedLinks())
                            .font(.system(size: 12.5))
                            .lineSpacing(3)
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 4)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                
                // 3. Comments Section Header & Input
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 8) {
                        Image(systemName: "bubble.left.and.bubble.right")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.secondary)
                        Text(LocalizedStringKey("track.comments.header"))
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(.primary)
                        
                        if !comments.isEmpty {
                            Text("\(comments.count)")
                                .font(.system(size: 11, weight: .semibold))
                                .padding(.horizontal, 7)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(Color.primary.opacity(0.08)))
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    // Comment Input
                    VStack(alignment: .leading, spacing: 6) {
                        if let reply = replyingTo {
                            HStack(spacing: 6) {
                                Image(systemName: "arrowshape.turn.up.left.fill")
                                    .font(.system(size: 10))
                                    .foregroundColor(Color(hex: 0xFF5500))
                                Text(LocalizedStringKey("track.replyTo"))
                                    .font(.system(size: 11.5))
                                    .foregroundColor(.secondary)
                                Text("@\(reply.user.username)")
                                    .font(.system(size: 11.5, weight: .semibold))
                                    .foregroundColor(.primary)
                                Spacer()
                                Button(action: cancelReply) {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.system(size: 12))
                                        .foregroundColor(.secondary)
                                }
                                .buttonStyle(.plain)
                                .help(NSLocalizedString("track.cancelReply", comment: ""))
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .fill(Color(hex: 0xFF5500).opacity(0.08))
                            )
                        }
                        
                        HStack(alignment: .center, spacing: 12) {
                            if let avatarURL = SoundCloud.shared.user?.avatarURL {
                                RemoteImage(url: avatarURL, cornerRadius: 16)
                                    .frame(width: 32, height: 32)
                                    .clipShape(Circle())
                                    .shadow(color: Color.black.opacity(0.12), radius: 2, x: 0, y: 1)
                            }
                            
                            HStack(spacing: 8) {
                                TextField(LocalizedStringKey("track.comment.placeholder"), text: $commentText)
                                    .textFieldStyle(.plain)
                                    .font(.system(size: 13))
                                    .focused($isCommentFieldFocused)
                                    .onSubmit {
                                        postComment()
                                    }
                                
                                if isCurrent {
                                    Button {
                                        withAnimation(.easeInOut(duration: 0.15)) {
                                            attachTimestamp.toggle()
                                        }
                                    } label: {
                                        HStack(spacing: 4) {
                                            Image(systemName: attachTimestamp ? "clock.fill" : "clock")
                                                .font(.system(size: 10))
                                            Text(format(time: player.progress))
                                                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                        }
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(
                                            Capsule()
                                                .fill(attachTimestamp ? Color(hex: 0xFF5500) : Color.primary.opacity(0.08))
                                        )
                                        .foregroundColor(attachTimestamp ? .white : .secondary)
                                    }
                                    .buttonStyle(.plain)
                                    .help(attachTimestamp ? NSLocalizedString("track.timestampAttached", comment: "") : NSLocalizedString("track.attachTimestamp", comment: ""))
                                }
                                
                                Button(action: postComment) {
                                    ZStack {
                                        Circle()
                                            .fill(commentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? Color.primary.opacity(0.06) : Color(hex: 0xFF5500))
                                            .frame(width: 28, height: 28)
                                        
                                        if isSubmittingComment {
                                            ProgressView()
                                                .scaleEffect(0.55)
                                                .frame(width: 14, height: 14)
                                        } else {
                                            Image(systemName: "arrow.up")
                                                .font(.system(size: 12, weight: .bold))
                                                .foregroundColor(commentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? .secondary.opacity(0.4) : .white)
                                        }
                                    }
                                }
                                .buttonStyle(.plain)
                                .disabled(commentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSubmittingComment)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(Color(nsColor: .controlBackgroundColor))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .stroke(Color.primary.opacity(0.12), lineWidth: 0.8)
                            )
                        }
                        
                        if let error = submitErrorMessage {
                            Text(error)
                                .font(.system(size: 11.5))
                                .foregroundColor(.red)
                                .padding(.leading, 44)
                        }
                    }
                    
                    Divider()
                        .padding(.vertical, 2)
                }
                .padding(.top, 4)
                
                // 4. Comments List
                if isLoadingComments {
                    HStack {
                        Spacer()
                        ProgressView()
                            .scaleEffect(0.8)
                            .padding(.vertical, 24)
                        Spacer()
                    }
                } else if let error = commentsErrorMessage, comments.isEmpty {
                    VStack(spacing: 8) {
                        Text(String(format: NSLocalizedString("track.loadCommentsError", comment: ""), "\(error)"))
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                        Button(LocalizedStringKey("url.retry"), action: loadComments)
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
                } else if comments.isEmpty {
                    HStack {
                        Spacer()
                        Text(LocalizedStringKey("track.noCommentsYet"))
                            .font(.system(size: 13))
                            .foregroundColor(.secondary)
                            .padding(.vertical, 20)
                        Spacer()
                    }
                } else {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(comments) { comment in
                            CommentRow(
                                comment: comment,
                                onReply: { replyToComment(comment) },
                                onDelete: { deleteComment(comment) }
                            )
                                .onAppear {
                                    if comment.id == comments.last?.id {
                                        loadNextCommentsPage()
                                    }
                                }
                            
                            Divider()
                                .opacity(0.3)
                        }
                        
                        if isLoadingMoreComments {
                            HStack {
                                Spacer()
                                ProgressView()
                                    .scaleEffect(0.7)
                                    .padding(.vertical, 10)
                                Spacer()
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 12)
            .padding(.bottom, 24)
        }
        .introspectScrollView { scrollView in
            scrollView.scrollerStyle = .overlay
            scrollView.verticalScroller?.controlSize = .small
        }
        .playbackContext([track])
        .onAppear {
            loadComments()
        }
        .navigationTitle(track.title)
    }
    
}
