//
//  CommentRow.swift
//  Nuage
//
//  Created by Laurin Brandner on 19.02.21.
//

import SwiftUI
import Combine
import SoundCloud

struct CommentRow: View {
    
    var comment: Comment
    var onReply: (() -> Void)? = nil
    var onDelete: (() -> Void)? = nil
    
    @State private var isReplyHovered = false
    @State private var isTrashHovered = false
    @State private var isHovering = false
    
    private var isCurrentUserComment: Bool {
        guard let currentUserID = SoundCloud.shared.user?.id else { return false }
        return comment.user.id == currentUserID
    }
    
    var body: some View {
        HStack(alignment: .top, spacing: comment.isReply ? 8 : 12) {
            if comment.isReply {
                Image(systemName: "arrow.turn.down.right")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(Color.secondary.opacity(0.55))
                    .padding(.top, 6)
            }
            
            NavigationLink(value: comment.user) {
                RemoteImage(url: comment.user.avatarURL, cornerRadius: comment.isReply ? 14 : 18)
                    .frame(width: comment.isReply ? 28 : 36, height: comment.isReply ? 28 : 36)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 8) {
                    NavigationLink(value: comment.user) {
                        Text(comment.user.username)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.primary)
                    }
                    .buttonStyle(.plain)
                    
                    if let target = comment.replyTargetUsername {
                        HStack(spacing: 3) {
                            Image(systemName: "arrowshape.turn.up.left.fill")
                                .font(.system(size: 8))
                            Text("@\(target)")
                                .font(.system(size: 11, weight: .medium))
                        }
                        .foregroundColor(Color(hex: 0xFF5500))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            Capsule()
                                .fill(Color(hex: 0xFF5500).opacity(0.12))
                        )
                    }
                    
                    if comment.timestamp > 0 {
                        Text(format(time: comment.timestamp))
                            .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(
                                Capsule()
                                    .fill(Color(hex: 0xFF5500).opacity(0.12))
                            )
                            .foregroundColor(Color(hex: 0xFF5500))
                    }
                    
                    Spacer()
                    
                    Text(comment.date.formatted(date: .abbreviated, time: .omitted))
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                    
                    if let onReply = onReply {
                        Button(action: onReply) {
                            HStack(spacing: 3) {
                                Image(systemName: "arrowshape.turn.up.left.fill")
                                    .font(.system(size: 10))
                                Text(LocalizedStringKey("comments.reply"))
                                    .font(.system(size: 11, weight: .medium))
                            }
                            .foregroundColor(isReplyHovered ? Color(hex: 0xFF5500) : .secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(
                                RoundedRectangle(cornerRadius: 4, style: .continuous)
                                    .fill(isReplyHovered ? Color(hex: 0xFF5500).opacity(0.1) : Color.clear)
                            )
                        }
                        .buttonStyle(.plain)
                        .help(NSLocalizedString("comments.replyToUser", comment: ""))
                        .onHover { isReplyHovered = $0 }
                    }
                    
                    if isCurrentUserComment, let onDelete = onDelete {
                        Button(action: onDelete) {
                            Image(systemName: "trash")
                                .font(.system(size: 11.5))
                                .foregroundColor(isTrashHovered ? .red : .secondary.opacity(0.85))
                        }
                        .buttonStyle(.plain)
                        .help(NSLocalizedString("comments.deleteComment", comment: ""))
                        .onHover { isTrashHovered = $0 }
                    }
                }
                
                Text(comment.isReply && !comment.bodyWithoutReplyTarget.isEmpty ? comment.bodyWithoutReplyTarget : comment.body)
                    .font(.system(size: 13))
                    .foregroundColor(.primary)
                    .textSelection(.enabled)
            }
        }
        .padding(.leading, comment.isReply ? 24 : 0)
        .padding(.vertical, 6)
        .padding(.horizontal, 6)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isHovering ? Color.primary.opacity(0.04) : Color.clear)
        )
        .onHover { inside in
            withAnimation(.easeInOut(duration: 0.12)) {
                isHovering = inside
            }
        }
        .contextMenu {
            if let onReply = onReply {
                Button(action: onReply) {
                    Label(LocalizedStringKey("comments.reply"), systemImage: "arrowshape.turn.up.left")
                }
            }
            if isCurrentUserComment, let onDelete = onDelete {
                Button(role: .destructive, action: onDelete) {
                    Label(LocalizedStringKey("comments.deleteComment"), systemImage: "trash")
                }
            }
        }
    }

}
