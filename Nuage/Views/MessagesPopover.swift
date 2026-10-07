//
//  MessagesPopover.swift
//  Nuage
//

import SwiftUI
import Combine
import SoundCloud

struct MessagesPopover: View {
    
    @ObservedObject private var social = SoundCloudSocialService.shared
    @State private var selectedConversation: Conversation? = nil
    
    var onNavigateToURL: ((URL) -> Void)?
    var onDismiss: (() -> Void)?
    
    var body: some View {
        Group {
            if let conversation = selectedConversation {
                ConversationChatView(
                    conversation: conversation,
                    onBack: {
                        selectedConversation = nil
                    },
                    onNavigateToURL: { url in
                        onDismiss?()
                        onNavigateToURL?(url)
                    }
                )
            } else {
                conversationListView
            }
        }
        .frame(width: 380, height: 460)
        .onAppear {
            social.fetchConversations()
        }
    }
    
    private var conversationListView: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text(LocalizedStringKey("messages.title"))
                    .font(.system(size: 16, weight: .bold))
                
                Spacer()
                
                if social.isLoadingConversations {
                    ProgressView()
                        .scaleEffect(0.6)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 10)
            
            Divider()
            
            // List
            if social.isLoadingConversations && social.conversations.isEmpty {
                VStack {
                    Spacer()
                    ProgressView()
                        .scaleEffect(0.8)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if social.conversations.isEmpty {
                VStack(spacing: 8) {
                    Spacer()
                    Image(systemName: "tray")
                        .font(.system(size: 28))
                        .foregroundColor(.secondary.opacity(0.5))
                    Text(LocalizedStringKey("messages.empty"))
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(social.conversations, id: \.id) { conv in
                            ConversationRowView(
                                conversation: conv,
                                currentUserId: SoundCloud.shared.user?.id,
                                action: {
                                    selectedConversation = conv
                                },
                                onDelete: {
                                    if let partner = conv.otherUser(currentUserId: SoundCloud.shared.user?.id) {
                                        social.deleteConversation(with: partner.id)
                                            .sink(receiveCompletion: { _ in }, receiveValue: { _ in })
                                            .store(in: &social.subscriptions)
                                    }
                                }
                            )
                            
                            Divider()
                                .opacity(0.4)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
    }
}

private struct ConversationRowView: View {
    
    let conversation: Conversation
    let currentUserId: String?
    let action: () -> Void
    var onDelete: (() -> Void)? = nil
    
    @ObservedObject private var aliasService = UserAliasService.shared
    @State private var isHovered = false
    @State private var showAliasSheet = false
    @State private var tempAlias = ""
    
    private var partner: User? {
        conversation.otherUser(currentUserId: currentUserId)
    }
    
    var body: some View {
        HStack(spacing: 12) {
                // Partner Avatar
                if let avatarURL = partner?.avatarURL {
                    AsyncImage(url: avatarURL) { phase in
                        if let img = phase.image {
                            img.resizable().scaledToFill()
                        } else {
                            Image(systemName: "person.crop.circle.fill")
                                .resizable()
                                .foregroundColor(.secondary)
                        }
                    }
                    .frame(width: 40, height: 40)
                    .clipShape(Circle())
                    .overlay(Circle().stroke(Color.primary.opacity(0.12), lineWidth: 0.5))
                } else {
                    Image(systemName: "person.crop.circle.fill")
                        .resizable()
                        .frame(width: 40, height: 40)
                        .foregroundColor(.secondary)
                }
                
                // Name and last message
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 5) {
                        Text(partner?.username ?? NSLocalizedString("messages.defaultPartner", comment: ""))
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.primary)
                            .lineLimit(1)
                        
                        if let partner = partner, let alias = aliasService.alias(for: partner.id) {
                            Text("(\(alias))")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(.accentColor)
                                .lineLimit(1)
                        }
                        
                        Spacer()
                        
                        let isActionVisible = isHovered || showAliasSheet
                        
                        ZStack(alignment: .trailing) {
                            if let sentAt = conversation.lastMessage?.sentAt {
                                HStack(spacing: 6) {
                                    if partner.flatMap({ aliasService.alias(for: $0.id) }) != nil {
                                        Image(systemName: "tag.fill")
                                            .font(.system(size: 9))
                                            .foregroundColor(.accentColor.opacity(0.7))
                                    }
                                    
                                    Text(formatRelativeTime(sentAt))
                                        .font(.system(size: 11))
                                        .foregroundColor(.secondary)
                                }
                                .opacity(isActionVisible ? 0 : 1)
                            }
                            
                            HStack(spacing: 6) {
                                Button {
                                    tempAlias = partner.flatMap { aliasService.alias(for: $0.id) } ?? ""
                                    showAliasSheet = true
                                } label: {
                                    Image(systemName: partner.flatMap { aliasService.alias(for: $0.id) } != nil ? "tag.fill" : "tag")
                                        .font(.system(size: 12))
                                        .foregroundColor(showAliasSheet ? .accentColor : .secondary)
                                        .frame(width: 22, height: 22)
                                        .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .help(NSLocalizedString("messages.setAlias", comment: ""))
                                .popover(isPresented: $showAliasSheet, arrowEdge: .trailing) {
                                    AliasEditPopover(
                                        username: partner?.username ?? "",
                                        currentAlias: tempAlias,
                                        onSave: { newAlias in
                                            if let partner = partner {
                                                aliasService.setAlias(newAlias, for: partner.id)
                                            }
                                            showAliasSheet = false
                                        }
                                    )
                                }
                                
                                if let onDelete = onDelete {
                                    Button(action: onDelete) {
                                        Image(systemName: "trash")
                                            .font(.system(size: 11))
                                            .foregroundColor(.secondary)
                                            .frame(width: 20, height: 22)
                                            .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)
                                    .help(NSLocalizedString("messages.deleteChat", comment: ""))
                                }
                            }
                            .opacity(isActionVisible ? 1 : 0)
                            .allowsHitTesting(isActionVisible)
                        }
                    }
                    
                    HStack {
                        Text(conversation.lastMessage?.content ?? NSLocalizedString("messages.noMessages", comment: ""))
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                        
                        Spacer()
                        
                        if !conversation.isRead {
                            Circle()
                                .fill(Color.orange)
                                .frame(width: 7, height: 7)
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
            .background(isHovered ? Color.primary.opacity(0.06) : Color.clear)
            .onTapGesture {
                action()
            }
            .onHover { hovering in
                isHovered = hovering
            }
        .contextMenu {
            Button {
                tempAlias = partner.flatMap { aliasService.alias(for: $0.id) } ?? ""
                showAliasSheet = true
            } label: {
                Label(LocalizedStringKey("messages.setAlias"), systemImage: "tag")
            }
            
            if let onDelete = onDelete {
                Divider()
                Button(role: .destructive, action: onDelete) {
                    Label(LocalizedStringKey("messages.deleteChat"), systemImage: "trash")
                }
            }
        }
    }
    
    private func formatRelativeTime(_ date: Date) -> String {
        let interval = Date().timeIntervalSince(date)
        if interval < 60 {
            return NSLocalizedString("messages.justNow", comment: "")
        } else if interval < 3600 {
            return String(format: NSLocalizedString("messages.minutesAgo", comment: ""), Int(interval / 60))
        } else if interval < 86400 {
            return String(format: NSLocalizedString("messages.hoursAgo", comment: ""), Int(interval / 3600))
        } else {
            return String(format: NSLocalizedString("messages.daysAgo", comment: ""), Int(interval / 86400))
        }
    }
}

private struct ConversationChatView: View {
    
    let conversation: Conversation
    let onBack: () -> Void
    let onNavigateToURL: (URL) -> Void
    
    @ObservedObject private var social = SoundCloudSocialService.shared
    @ObservedObject private var aliasService = UserAliasService.shared
    @State private var messages: [ConversationMessage] = []
    @State private var messageText: String = ""
    @State private var isSending: Bool = false
    @State private var isLoading: Bool = true
    @State private var showDeleteConfirm: Bool = false
    @State private var showEditAlias = false
    @State private var tempAliasText: String = ""
    @State private var subscriptions = Set<AnyCancellable>()
    
    private var partner: User? {
        conversation.otherUser(currentUserId: SoundCloud.shared.user?.id)
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Top Bar
            HStack(spacing: 10) {
                Button(action: onBack) {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 12, weight: .bold))
                        Text(LocalizedStringKey("messages.back"))
                            .font(.system(size: 12, weight: .medium))
                    }
                    .foregroundColor(.accentColor)
                }
                .buttonStyle(.plain)
                
                Spacer()
                
                if let partner = partner {
                    HStack(spacing: 6) {
                        if let avatarURL = partner.avatarURL as URL? {
                            AsyncImage(url: avatarURL) { phase in
                                if let img = phase.image {
                                    img.resizable().scaledToFill()
                                } else {
                                    Image(systemName: "person.crop.circle.fill")
                                        .resizable()
                                }
                            }
                            .frame(width: 20, height: 20)
                            .clipShape(Circle())
                        }
                        
                        Text(partner.username)
                            .font(.system(size: 13, weight: .bold))
                            .lineLimit(1)
                        
                        if let alias = aliasService.alias(for: partner.id) {
                            Text("(\(alias))")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(.accentColor)
                                .lineLimit(1)
                        }
                        
                        Button {
                            tempAliasText = aliasService.alias(for: partner.id) ?? ""
                            showEditAlias = true
                        } label: {
                            Image(systemName: aliasService.alias(for: partner.id) != nil ? "tag.fill" : "tag.circle")
                                .font(.system(size: 13))
                                .foregroundColor(aliasService.alias(for: partner.id) != nil ? .accentColor : .secondary)
                        }
                        .buttonStyle(.plain)
                        .help(NSLocalizedString("messages.setAlias", comment: ""))
                        .popover(isPresented: $showEditAlias, arrowEdge: .bottom) {
                            AliasEditPopover(
                                username: partner.username,
                                currentAlias: tempAliasText,
                                onSave: { newAlias in
                                    aliasService.setAlias(newAlias, for: partner.id)
                                    showEditAlias = false
                                }
                            )
                        }
                    }
                }
                
                Spacer()
                
                // Delete conversation button
                HStack(spacing: 8) {
                    Button(action: { showDeleteConfirm = true }) {
                        Image(systemName: "trash")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help(NSLocalizedString("messages.deleteConversation", comment: ""))
                }
                .frame(width: 50, alignment: .trailing)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            
            Divider()
            
            // Messages List
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 10) {
                        if isLoading {
                            ProgressView()
                                .scaleEffect(0.8)
                                .padding(.top, 20)
                        } else if messages.isEmpty {
                            Text(LocalizedStringKey("messages.noMessagesYet"))
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                                .padding(.top, 40)
                        } else {
                            ForEach(messages) { msg in
                                MessageBubbleView(
                                    message: msg,
                                    isMe: msg.sender?.id == SoundCloud.shared.user?.id,
                                    onLinkTapped: onNavigateToURL
                                )
                                .id(msg.id)
                            }
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                }
                .onChange(of: messages.count) { _ in
                    if let last = messages.last {
                        withAnimation {
                            proxy.scrollTo(last.id, anchor: .bottom)
                        }
                    }
                }
            }
            
            Divider()
            
            // Input Bar
            HStack(spacing: 8) {
                TextField(LocalizedStringKey("messages.typeMessage"), text: $messageText)
                    .textFieldStyle(.plain)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(Color(nsColor: .controlBackgroundColor))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(Color.primary.opacity(0.12), lineWidth: 0.5)
                    )
                    .onSubmit {
                        sendMessage()
                    }
                
                Button(action: sendMessage) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 24))
                        .foregroundColor(messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSending ? .secondary.opacity(0.4) : .accentColor)
                }
                .buttonStyle(.plain)
                .disabled(messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSending)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .onAppear {
            loadMessages()
        }
        .confirmationDialog(
            String(format: NSLocalizedString("messages.deleteChatConfirmTitle", comment: ""), partner?.username ?? NSLocalizedString("messages.defaultPartner", comment: "")),
            isPresented: $showDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button(LocalizedStringKey("messages.delete"), role: .destructive) {
                if let partnerId = partner?.id {
                    social.deleteConversation(with: partnerId)
                        .sink(receiveCompletion: { _ in }, receiveValue: { _ in })
                        .store(in: &social.subscriptions)
                    onBack()
                }
            }
            Button(LocalizedStringKey("playlists.cancel"), role: .cancel) { }
        } message: {
            Text(LocalizedStringKey("messages.deleteConfirm"))
        }
    }
    
    private func loadMessages() {
        guard let partnerId = partner?.id else { return }
        isLoading = true
        
        social.fetchMessages(for: partnerId)
            .sink(receiveCompletion: { completion in
                isLoading = false
            }, receiveValue: { fetched in
                self.messages = fetched
            })
            .store(in: &subscriptions)
    }
    
    private func sendMessage() {
        let text = messageText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, let partnerId = partner?.id, !isSending else { return }
        
        isSending = true
        messageText = ""
        
        // Optimistic insert
        let tempMsg = ConversationMessage(
            content: text,
            conversationId: conversation.id,
            sender: SoundCloud.shared.user,
            sentAt: Date()
        )
        messages.append(tempMsg)
        
        social.sendMessage(to: partnerId, content: text)
            .sink(receiveCompletion: { completion in
                isSending = false
                if case .failure(let error) = completion {
                    print("Send message error: \(error)")
                }
            }, receiveValue: { sentConversation in
                if let lastMsg = sentConversation.lastMessage {
                    if let idx = messages.firstIndex(where: { $0.id == tempMsg.id }) {
                        messages[idx] = lastMsg
                    } else if !messages.contains(where: { $0.id == lastMsg.id }) {
                        messages.append(lastMsg)
                    }
                }
            })
            .store(in: &subscriptions)
    }
}

private struct MessageBubbleView: View {
    
    let message: ConversationMessage
    let isMe: Bool
    let onLinkTapped: (URL) -> Void
    
    private var detectedURL: URL? {
        // Direct match
        if let url = URL(string: message.content.trimmingCharacters(in: .whitespacesAndNewlines)),
           url.host?.contains("soundcloud.com") == true {
            return url
        }
        // Detector for message with text + URL
        let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
        let matches = detector?.matches(in: message.content, options: [], range: NSRange(location: 0, length: message.content.utf16.count))
        return matches?.first(where: { $0.url?.host?.contains("soundcloud.com") == true })?.url
    }
    
    private var remainingText: String {
        var text = message.content
        if let url = detectedURL {
            text = text.replacingOccurrences(of: url.absoluteString, with: "")
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    var body: some View {
        HStack {
            if isMe { Spacer(minLength: 40) }
            
            VStack(alignment: isMe ? .trailing : .leading, spacing: 4) {
                if !remainingText.isEmpty {
                    Text(remainingText)
                        .font(.system(size: 13))
                        .foregroundColor(isMe ? .white : .primary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(isMe ? Color.accentColor : Color(nsColor: .controlBackgroundColor))
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(Color.primary.opacity(isMe ? 0 : 0.08), lineWidth: 0.5)
                        )
                }
                
                // If there's a detected SoundCloud URL card
                if let url = detectedURL {
                    let isPlaylistOrAlbum = url.path.contains("/sets/")
                    Button {
                        onLinkTapped(url)
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: isPlaylistOrAlbum ? "music.note.list" : "music.note")
                                .font(.system(size: 14))
                                .foregroundColor(isMe ? .white : Color(hex: 0xFF5500))
                            
                            VStack(alignment: .leading, spacing: 2) {
                                Text(isPlaylistOrAlbum ? LocalizedStringKey("messages.playlistOrAlbum") : LocalizedStringKey("messages.track"))
                                    .font(.system(size: 11, weight: .bold))
                                Text(url.lastPathComponent.replacingOccurrences(of: "-", with: " "))
                                    .font(.system(size: 11))
                                    .lineLimit(1)
                            }
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(isMe ? Color.accentColor.opacity(0.85) : Color(nsColor: .controlBackgroundColor))
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(Color.primary.opacity(0.08), lineWidth: 0.5)
                        )
                    }
                    .buttonStyle(.plain)
                }
                
                if let date = message.sentAt {
                    Text(formatTime(date))
                        .font(.system(size: 9))
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 4)
                }
            }
            
            if !isMe { Spacer(minLength: 40) }
        }
    }
    
    private func formatTime(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f.string(from: date)
    }
}

private struct AliasEditPopover: View {
    let username: String
    @State var currentAlias: String
    let onSave: (String) -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "tag.fill")
                    .foregroundColor(.accentColor)
                    .font(.system(size: 12))
                Text(String(format: NSLocalizedString("messages.voiceNameFor", comment: ""), username))
                    .font(.system(size: 12, weight: .bold))
            }
            
            Text(LocalizedStringKey("messages.voiceNameHint"))
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            
            HStack(spacing: 8) {
                TextField(LocalizedStringKey("messages.enterNamePlaceholder"), text: $currentAlias)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12))
                    .onSubmit {
                        onSave(currentAlias)
                    }
                
                Button(LocalizedStringKey("playlists.save")) {
                    onSave(currentAlias)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
            
            if !currentAlias.isEmpty {
                Button(LocalizedStringKey("messages.clearName")) {
                    onSave("")
                }
                .buttonStyle(.plain)
                .font(.system(size: 10.5))
                .foregroundColor(.red.opacity(0.8))
            }
        }
        .padding(14)
        .frame(width: 270)
    }
}
