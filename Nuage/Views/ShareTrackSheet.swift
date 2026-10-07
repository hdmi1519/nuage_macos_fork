//
//  ShareTrackSheet.swift
//  Nuage
//

import SwiftUI
import Combine
import SoundCloud

enum ShareableItem: Identifiable {
    case track(Track)
    case playlist(AnyPlaylist)
    
    var id: String {
        switch self {
        case .track(let t): return "track-\(t.id)"
        case .playlist(let p): return "playlist-\(p.id)"
        }
    }
    
    var title: String {
        switch self {
        case .track(let t): return t.title
        case .playlist(let p): return p.title
        }
    }
    
    var subtitle: String {
        switch self {
        case .track(let t): return t.user.username
        case .playlist(let p): return p.user.username
        }
    }
    
    var artworkURL: URL? {
        switch self {
        case .track(let t): return t.artworkURL
        case .playlist(let p): return p.artworkURL ?? p.tracks?.first?.artworkURL
        }
    }
    
    var isAlbum: Bool {
        switch self {
        case .track: return false
        case .playlist(let p): return p.userPlaylist?.isAlbum == true
        }
    }
    
    var headerTitle: String {
        switch self {
        case .track: return NSLocalizedString("share.track", comment: "")
        case .playlist: return isAlbum ? NSLocalizedString("share.album", comment: "") : NSLocalizedString("share.playlist", comment: "")
        }
    }
    
    var iconName: String {
        switch self {
        case .track: return "music.note"
        case .playlist: return isAlbum ? "opticaldisc" : "music.note.list"
        }
    }
}

struct ShareItemSheet: View {
    
    let item: ShareableItem
    @Environment(\.presentationMode) private var presentationMode
    @ObservedObject private var social = SoundCloudSocialService.shared
    
    @State private var searchQuery: String = ""
    @State private var commentText: String = ""
    @State private var sentUserIds = Set<String>()
    @State private var sendingUserIds = Set<String>()
    @State private var subscriptions = Set<AnyCancellable>()
    
    private var filteredFriends: [User] {
        let q = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if q.isEmpty {
            return social.friends
        }
        return social.friends.filter {
            $0.username.lowercased().contains(q) ||
            $0.firstName.lowercased().contains(q) ||
            $0.lastName.lowercased().contains(q)
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: item.iconName)
                        .foregroundColor(.accentColor)
                    Text(item.headerTitle)
                        .font(.system(size: 15, weight: .bold))
                }
                
                Spacer()
                
                Button {
                    presentationMode.wrappedValue.dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundColor(.secondary.opacity(0.7))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 12)
            
            Divider()
            
            // Preview Card
            HStack(spacing: 12) {
                if let artURL = item.artworkURL {
                    AsyncImage(url: artURL) { phase in
                        if let img = phase.image {
                            img.resizable().scaledToFill()
                        } else {
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Color.secondary.opacity(0.2))
                        }
                    }
                    .frame(width: 44, height: 44)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                } else {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.secondary.opacity(0.15))
                        .frame(width: 44, height: 44)
                        .overlay(
                            Image(systemName: item.iconName)
                                .font(.system(size: 18))
                                .foregroundColor(.secondary)
                        )
                }
                
                VStack(alignment: .leading, spacing: 3) {
                    Text(item.title)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                    
                    Text(item.subtitle)
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                
                Spacer()
            }
            .padding(12)
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.6))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            
            // Comment input
            TextField(LocalizedStringKey("share.messagePlaceholder"), text: $commentText)
                .textFieldStyle(.plain)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color(nsColor: .controlBackgroundColor))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(Color.primary.opacity(0.12), lineWidth: 0.5)
                )
                .padding(.horizontal, 16)
                .padding(.bottom, 10)
            
            // Search friends
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                    .font(.system(size: 12))
                
                TextField(LocalizedStringKey("share.searchFriends"), text: $searchQuery)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
            
            Divider()
            
            // Friends List
            if social.isLoadingFriends && social.friends.isEmpty {
                VStack {
                    Spacer()
                    ProgressView()
                    Spacer()
                }
                .frame(maxHeight: .infinity)
            } else if filteredFriends.isEmpty {
                VStack(spacing: 6) {
                    Spacer()
                    Text(LocalizedStringKey("share.noFriendsFound"))
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .frame(maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(filteredFriends, id: \.id) { friend in
                            friendRow(friend)
                            Divider().opacity(0.4)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .frame(width: 360, height: 420)
        .onAppear {
            social.fetchFriends()
        }
    }
    
    private func friendRow(_ friend: User) -> some View {
        let isSent = sentUserIds.contains(friend.id)
        let isSending = sendingUserIds.contains(friend.id)
        
        return HStack(spacing: 10) {
            AsyncImage(url: friend.avatarURL) { phase in
                if let img = phase.image {
                    img.resizable().scaledToFill()
                } else {
                    Image(systemName: "person.crop.circle.fill")
                        .resizable()
                        .foregroundColor(.secondary)
                }
            }
            .frame(width: 32, height: 32)
            .clipShape(Circle())
            
            VStack(alignment: .leading, spacing: 2) {
                Text(friend.username)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
            }
            
            Spacer()
            
            Button {
                sendItem(to: friend)
            } label: {
                if isSent {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark")
                            .font(.system(size: 11, weight: .bold))
                        Text(LocalizedStringKey("share.sent"))
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .foregroundColor(.green)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                } else if isSending {
                    ProgressView()
                        .scaleEffect(0.6)
                        .frame(width: 60)
                } else {
                    Text(LocalizedStringKey("share.send"))
                        .font(.system(size: 11, weight: .semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(Color.accentColor))
                        .foregroundColor(.white)
                }
            }
            .buttonStyle(.plain)
            .disabled(isSent || isSending)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }
    
    private func sendItem(to friend: User) {
        sendingUserIds.insert(friend.id)
        let note = commentText.isEmpty ? nil : commentText
        
        let publisher: AnyPublisher<Conversation, Error>
        switch item {
        case .track(let track):
            publisher = social.shareTrack(track, to: friend.id, note: note)
        case .playlist(let playlist):
            publisher = social.sharePlaylist(playlist, to: friend.id, note: note)
        }
        
        publisher
            .sink(receiveCompletion: { completion in
                sendingUserIds.remove(friend.id)
                if case .failure(let error) = completion {
                    print("Share item error: \(error)")
                }
            }, receiveValue: { _ in
                sentUserIds.insert(friend.id)
            })
            .store(in: &subscriptions)
    }
}

struct ShareTrackSheet: View {
    let track: Track
    
    var body: some View {
        ShareItemSheet(item: .track(track))
    }
}
