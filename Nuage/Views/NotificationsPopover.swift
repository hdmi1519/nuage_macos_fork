//
//  NotificationsPopover.swift
//  Nuage
//

import SwiftUI
import Combine
import SoundCloud

struct NotificationsPopover: View {
    
    @ObservedObject private var social = SoundCloudSocialService.shared
    var onNavigateToTrack: ((Track) -> Void)?
    var onNavigateToUser: ((User) -> Void)?
    var onDismiss: (() -> Void)?
    
    @State private var subscriptions = Set<AnyCancellable>()
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text(LocalizedStringKey("notifications.title"))
                    .font(.system(size: 16, weight: .bold))
                
                Spacer()
                
                Button {
                    social.markNotificationsAsRead()
                } label: {
                    Text(LocalizedStringKey("notifications.readAll"))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.accentColor)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 10)
            
            Divider()
            
            // Content
            if social.isLoadingNotifications && social.notifications.isEmpty {
                VStack {
                    Spacer()
                    ProgressView()
                        .scaleEffect(0.8)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if social.notifications.isEmpty {
                VStack(spacing: 8) {
                    Spacer()
                    Image(systemName: "bell.slash")
                        .font(.system(size: 28))
                        .foregroundColor(.secondary.opacity(0.5))
                    Text(LocalizedStringKey("notifications.empty"))
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(social.notifications, id: \.id) { item in
                            NotificationRowView(item: item) {
                                if let track = item.track {
                                    onDismiss?()
                                    onNavigateToTrack?(track)
                                } else if let user = item.user {
                                    onDismiss?()
                                    onNavigateToUser?(user)
                                }
                            } onFollowTapped: { user in
                                toggleFollow(user: user)
                            }
                            
                            Divider()
                                .opacity(0.4)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .frame(width: 390, height: 460)
        .onAppear {
            social.fetchNotifications()
            social.markNotificationsAsRead()
        }
    }
    
    private func toggleFollow(user: User) {
        SoundCloud.shared.perform(.follow(user))
            .receive(on: RunLoop.main)
            .sink(receiveCompletion: { _ in }, receiveValue: { _ in })
            .store(in: &subscriptions)
    }
}

private struct NotificationRowView: View {
    
    let item: ActivityItem
    let action: () -> Void
    let onFollowTapped: (User) -> Void
    
    @State private var isHovered = false
    @State private var isFollowing = false
    
    var body: some View {
        Button(action: action) {
            HStack(alignment: .center, spacing: 12) {
                // Initiator Avatar
                if let avatarURL = item.user?.avatarURL {
                    AsyncImage(url: avatarURL) { phase in
                        if let img = phase.image {
                            img.resizable().scaledToFill()
                        } else {
                            Image(systemName: "person.crop.circle.fill")
                                .resizable()
                                .foregroundColor(.secondary)
                        }
                    }
                    .frame(width: 38, height: 38)
                    .clipShape(Circle())
                    .overlay(Circle().stroke(Color.primary.opacity(0.12), lineWidth: 0.5))
                } else {
                    Image(systemName: "person.crop.circle.fill")
                        .resizable()
                        .frame(width: 38, height: 38)
                        .foregroundColor(.secondary)
                }
                
                // Description and comment
                VStack(alignment: .leading, spacing: 3) {
                    headlineText
                        .font(.system(size: 13))
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    
                    if let comment = item.commentBody, !comment.isEmpty {
                        Text("\"\(comment)\"")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                    }
                    
                    if let date = item.createdAt {
                        HStack(spacing: 4) {
                            Image(systemName: "clock")
                                .font(.system(size: 9))
                                .foregroundColor(.secondary)
                            Text(formatRelativeDate(date))
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }
                        .padding(.top, 1)
                    }
                }
                
                Spacer(minLength: 8)
                
                // Right Accessory: Track artwork or Follow back button
                if let track = item.track, let artURL = track.artworkURL {
                    AsyncImage(url: artURL) { phase in
                        if let img = phase.image {
                            img.resizable().scaledToFill()
                        } else {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color.secondary.opacity(0.2))
                        }
                    }
                    .frame(width: 38, height: 38)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .stroke(Color.primary.opacity(0.1), lineWidth: 0.5)
                    )
                } else if item.type == "affiliation", let user = item.user {
                    Button {
                        isFollowing.toggle()
                        onFollowTapped(user)
                    } label: {
                        Text(isFollowing ? LocalizedStringKey("notifications.following") : LocalizedStringKey("notifications.followBack"))
                            .font(.system(size: 11, weight: .semibold))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(
                                Capsule()
                                    .fill(isFollowing ? Color.secondary.opacity(0.15) : Color.white)
                            )
                            .foregroundColor(isFollowing ? .secondary : .black)
                            .overlay(
                                Capsule()
                                    .stroke(Color.primary.opacity(0.15), lineWidth: 0.5)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
            .background(isHovered ? Color.primary.opacity(0.06) : Color.clear)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
        }
    }
    
    private var headlineText: Text {
        let username = item.user?.username ?? NSLocalizedString("notifications.defaultUser", comment: "")
        let boldName = Text(username).bold().foregroundColor(.primary)
        
        switch item.type {
        case "mention":
            return boldName + Text(NSLocalizedString("notifications.mentionedYou", comment: ""))
        case "affiliation":
            return boldName + Text(NSLocalizedString("notifications.followedYou", comment: ""))
        case "trackLike":
            return boldName + Text(NSLocalizedString("notifications.likedTrack", comment: ""))
        case "trackRepost":
            return boldName + Text(NSLocalizedString("notifications.sharedTrack", comment: ""))
        case "comment":
            return boldName + Text(NSLocalizedString("notifications.commented", comment: ""))
        default:
            return boldName + Text(NSLocalizedString("notifications.newAction", comment: ""))
        }
    }
    
    private func formatRelativeDate(_ date: Date) -> String {
        let now = Date()
        let interval = now.timeIntervalSince(date)
        
        if interval < 60 {
            return NSLocalizedString("messages.justNow", comment: "")
        } else if interval < 3600 {
            let mins = Int(interval / 60)
            return String(format: NSLocalizedString("messages.minutesAgo", comment: ""), mins)
        } else if interval < 86400 {
            let hours = Int(interval / 3600)
            return String(format: NSLocalizedString("messages.hoursAgo", comment: ""), hours)
        } else if interval < 86400 * 7 {
            let days = Int(interval / 86400)
            return String(format: NSLocalizedString("messages.daysAgo", comment: ""), days)
        } else {
            let formatter = DateFormatter()
            formatter.locale = Locale.current
            formatter.dateFormat = "d MMMM yyyy"
            return formatter.string(from: date)
        }
    }
}
