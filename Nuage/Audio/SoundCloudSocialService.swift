//
//  SoundCloudSocialService.swift
//  Nuage
//

import Foundation
import Combine
import SwiftUI
import SoundCloud

@MainActor
public class SoundCloudSocialService: ObservableObject {
    
    public static let shared = SoundCloudSocialService()
    
    @Published public private(set) var notifications: [ActivityItem] = []
    @Published public private(set) var unreadNotificationsCount: Int = 0
    @Published public private(set) var isLoadingNotifications: Bool = false
    
    @Published public private(set) var conversations: [Conversation] = []
    @Published public private(set) var unreadConversationsCount: Int = 0
    @Published public private(set) var isLoadingConversations: Bool = false
    
    @Published public private(set) var friends: [User] = []
    @Published public private(set) var isLoadingFriends: Bool = false
    
    var subscriptions = Set<AnyCancellable>()
    private var pollTimer: AnyCancellable?
    
    private let lastReadNotificationKey = "NuageLastReadNotificationUUID"
    
    private init() {
        // Observe login state
        SoundCloud.shared.$user
            .receive(on: RunLoop.main)
            .sink { [weak self] user in
                if user != nil {
                    self?.startPolling()
                } else {
                    self?.stopPolling()
                    self?.clearData()
                }
            }
            .store(in: &subscriptions)
    }
    
    public func startPolling() {
        pollTimer?.cancel()
        pollTimer = Timer.publish(every: 45, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.refreshAll()
            }
        refreshAll()
    }
    
    public func stopPolling() {
        pollTimer?.cancel()
        pollTimer = nil
    }
    
    private func clearData() {
        notifications = []
        unreadNotificationsCount = 0
        conversations = []
        unreadConversationsCount = 0
        friends = []
    }
    
    public func refreshAll() {
        fetchNotifications()
        fetchConversations()
        fetchFriends()
    }
    
    // MARK: - Notifications
    
    public func fetchNotifications() {
        guard SoundCloud.shared.user != nil else { return }
        isLoadingNotifications = true
        
        SoundCloud.shared.get(.activities())
            .receive(on: RunLoop.main)
            .sink(receiveCompletion: { [weak self] completion in
                self?.isLoadingNotifications = false
                if case .failure(let error) = completion {
                    print("SoundCloudSocialService fetchNotifications error: \(error)")
                }
            }, receiveValue: { [weak self] page in
                guard let self = self else { return }
                self.notifications = page.collection
                self.updateUnreadNotificationsCount()
            })
            .store(in: &subscriptions)
    }
    
    private func updateUnreadNotificationsCount() {
        guard let first = notifications.first else {
            unreadNotificationsCount = 0
            return
        }
        let lastReadUUID = UserDefaults.standard.string(forKey: lastReadNotificationKey)
        if lastReadUUID == first.id {
            unreadNotificationsCount = 0
        } else if let lastReadUUID = lastReadUUID, let idx = notifications.firstIndex(where: { $0.id == lastReadUUID }) {
            unreadNotificationsCount = idx
        } else {
            unreadNotificationsCount = min(notifications.count, 5)
        }
    }
    
    public func markNotificationsAsRead() {
        if let first = notifications.first {
            UserDefaults.standard.set(first.id, forKey: lastReadNotificationKey)
        }
        unreadNotificationsCount = 0
    }
    
    // MARK: - Conversations
    
    public func fetchConversations() {
        guard let user = SoundCloud.shared.user else { return }
        isLoadingConversations = true
        
        SoundCloud.shared.get(.conversations(of: user))
            .receive(on: RunLoop.main)
            .sink(receiveCompletion: { [weak self] completion in
                self?.isLoadingConversations = false
                if case .failure(let error) = completion {
                    print("SoundCloudSocialService fetchConversations error: \(error)")
                }
            }, receiveValue: { [weak self] page in
                guard let self = self else { return }
                self.conversations = page.collection
                let unreadInCollection = page.collection.filter { !$0.isRead }.count
                self.unreadConversationsCount = max(self.unreadConversationsCount, unreadInCollection)
            })
            .store(in: &subscriptions)
        
        SoundCloud.shared.get(.unreadConversations(of: user))
            .receive(on: RunLoop.main)
            .sink(receiveCompletion: { _ in }, receiveValue: { [weak self] unreadPage in
                self?.unreadConversationsCount = unreadPage.collection.count
            })
            .store(in: &subscriptions)
    }
    
    public func fetchMessages(for otherUserId: String) -> AnyPublisher<[ConversationMessage], Error> {
        return SoundCloud.shared.get(.conversationMessages(with: otherUserId))
            .map { $0.collection.reversed() }
            .receive(on: RunLoop.main)
            .eraseToAnyPublisher()
    }
    
    public func sendMessage(to otherUserId: String, content: String) -> AnyPublisher<Conversation, Error> {
        return SoundCloud.shared.get(.sendMessage(to: otherUserId, content: content))
            .receive(on: RunLoop.main)
            .handleEvents(receiveOutput: { [weak self] _ in
                self?.fetchConversations()
            })
            .eraseToAnyPublisher()
    }
    
    public func shareTrack(_ track: Track, to otherUserId: String, note: String? = nil) -> AnyPublisher<Conversation, Error> {
        var text = track.permalinkURL.absoluteString
        if let note = note, !note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            text = "\(note)\n\(text)"
        }
        return sendMessage(to: otherUserId, content: text)
    }
    
    public func sharePlaylist(_ playlist: AnyPlaylist, to otherUserId: String, note: String? = nil) -> AnyPublisher<Conversation, Error> {
        var text = playlist.permalinkURL.absoluteString
        if let note = note, !note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            text = "\(note)\n\(text)"
        }
        return sendMessage(to: otherUserId, content: text)
    }
    
    public func deleteConversation(with otherUserId: String) -> AnyPublisher<(), Error> {
        let myId = SoundCloud.shared.user?.id
        self.conversations.removeAll { conv in
            conv.otherUser(currentUserId: myId)?.id == otherUserId
        }
        
        return SoundCloud.shared.perform(.deleteConversation(with: otherUserId))
            .receive(on: RunLoop.main)
            .handleEvents(receiveOutput: { [weak self] _ in
                self?.fetchConversations()
            })
            .eraseToAnyPublisher()
    }
    
    // MARK: - Friends / Followings
    
    public func fetchFriends() {
        guard let user = SoundCloud.shared.user else { return }
        isLoadingFriends = true
        
        SoundCloud.shared.get(.followings(of: user))
            .receive(on: RunLoop.main)
            .sink(receiveCompletion: { [weak self] _ in
                self?.isLoadingFriends = false
            }, receiveValue: { [weak self] page in
                guard let self = self else { return }
                // Merge users from existing conversations and followings
                var combined: [User] = []
                var seenIds = Set<String>()
                
                // Add conversation partners first (recent contacts)
                for conv in self.conversations {
                    if let partner = conv.otherUser(currentUserId: SoundCloud.shared.user?.id) {
                        if !seenIds.contains(partner.id) {
                            seenIds.insert(partner.id)
                            combined.append(partner)
                        }
                    }
                }
                
                // Then add followings
                for u in page.collection {
                    if !seenIds.contains(u.id) {
                        seenIds.insert(u.id)
                        combined.append(u)
                    }
                }
                
                self.friends = combined
            })
            .store(in: &subscriptions)
    }
}
