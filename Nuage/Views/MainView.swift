//
//  MainView.swift
//  Nuage
//
//  Created by Laurin Brandner on 26.12.19.
//  Copyright © 2019 Laurin Brandner. All rights reserved.
//

import SwiftUI
import AppKit
import Combine
import SoundCloud

struct MainView: View {

    @ObservedObject private var soundCloud = SoundCloud.shared
    @ObservedObject private var socialService = SoundCloudSocialService.shared

    @AppStorage("sidebarSelection") private var sidebarSelection: SidebarItem = .stream
    @State private var navigationPath = NavigationPath()

    @State private var searchQuery = ""
    @State private var showingRightPanel = false
    @State private var showingFullscreenNowPlaying = false
    @State private var showProfilePopover = false
    @State private var showNotificationsPopover = false
    @State private var showMessagesPopover = false
    @State private var showVoiceControlSettings = false
    @State private var itemToShare: ShareableItem? = nil
    @State private var rightPanelMode: NowPlayingMode = .lyrics
    @State private var inspectedTrack: Track? = nil
    @State private var refreshID = UUID()
    @State private var subscriptions = Set<AnyCancellable>()

    @EnvironmentObject private var commandSubjects: CommandSubject
    @EnvironmentObject private var player: StreamPlayer
    @Environment(\.playlists) private var playlists: [AnyPlaylist]
    @Environment(\.likes) private var likes: [Track]
    @Environment(\.toggleLikeTrack) private var toggleLikeTrack: (Track) -> () -> ()
    @Environment(\.toggleRepostTrack) private var toggleRepostTrack: (Track) -> () -> ()
    @Environment(\.posts) private var posts: [Post]
    @Environment(\.logOut) private var logOut: () -> ()

    @Environment(\.showLikedPlaylists) private var showLikedPlaylists: Bool
    @Environment(\.showCreatedPlaylists) private var showCreatedPlaylists: Bool

    @ViewBuilder
    private var navigationStackView: some View {
        NavigationStack(path: $navigationPath) {
            Group {
                if !searchQuery.isEmpty {
                    SearchList(query: searchQuery)
                        .id("search-\(searchQuery)-\(refreshID)")
                }
                else {
                    root(for: sidebarSelection)
                        .id("\(sidebarSelection.id)-\(refreshID)")
                }
            }
            .navigationDestinationWithPlaybackContext(for: Track.self) { TrackDetail(track: $0).id("track-\($0.id)-\(refreshID)") }
            .navigationDestination(for: Track.self) { TrackDetail(track: $0).id("track-\($0.id)-\(refreshID)") }
            .navigationDestination(for: User.self) { UserDetail(user: $0).id("user-\($0.id)-\(refreshID)") }
            .navigationDestination(for: URL.self) { URLDetail(url: $0).id("url-\($0.absoluteString)-\(refreshID)") }
            .navigationDestination(for: AnyPlaylist.self) { playlist in
                PlaylistDetail(playlist: playlist)
                    .id("playlist-\(playlist.id)-\(refreshID)")
            }
            .navigationDestination(for: UserPlaylist.self) { playlist in
                PlaylistDetail(playlist: .user(playlist))
                    .id("playlist-\(playlist.id)-\(refreshID)")
            }
            .navigationDestination(for: SystemPlaylist.self) { playlist in
                PlaylistDetail(playlist: .system(playlist))
                    .id("playlist-\(playlist.id)-\(refreshID)")
            }
            .navigationDestination(for: Station.self) { station in
                Group {
                    switch station {
                    case .track(let track): TrackList(request: .trackStation(basedOn: track))
                    case .artist(let user): TrackList(request: .artistStation(basedOn: user))
                    }
                }
                .id("station-\(refreshID)")
            }
        }
        .frame(minWidth: 400, maxWidth: .infinity)
    }

    @ViewBuilder
    private var nowPlayingRightPanel: some View {
        if showingRightPanel {
            Divider()
            NowPlayingPanel(
                isPresented: $showingRightPanel,
                mode: $rightPanelMode,
                inspectedTrack: $inspectedTrack,
                onTrackTap: { track in
                    navigationPath.append(track, with: player.queue, startPlaybackAt: track, player: player)
                },
                onUserTap: { user in
                    navigationPath.append(user)
                }
            )
            .frame(width: 320)
            .transition(.move(edge: .trailing))
        }
    }

    @ViewBuilder
    private var bottomPlayerSection: some View {
        if player.queue.count > 0 {
            Divider()
            PlayerView(
                onTrackDetailTap: {
                    if let track = player.currentStream {
                        navigationPath.append(track, with: player.queue, startPlaybackAt: track, player: player)
                    }
                },
                onUserDetailTap: { user in
                    navigationPath.append(user)
                },
                onStationTap: { station in
                    navigationPath.append(station)
                },
                showingPanel: $showingRightPanel,
                panelMode: $rightPanelMode,
                onPanelOpen: {
                    inspectedTrack = nil
                }
            )
        }
    }

    @ViewBuilder
    private var keyboardShortcuts: some View {
        Color.clear
            .background(
                Button("") {
                    if !navigationPath.isEmpty {
                        navigationPath.removeLast()
                    }
                }
                .keyboardShortcut("[", modifiers: .command)
                .opacity(0)
                .allowsHitTesting(false)
            )
            .background(
                Button("") {
                    commandSubjects.search.send()
                }
                .keyboardShortcut("f", modifiers: .command)
                .opacity(0)
                .allowsHitTesting(false)
            )
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                NavigationSplitView(sidebar: sidebar) {
                    navigationStackView
                }
                nowPlayingRightPanel
            }
            .animation(.easeInOut(duration: 0.22), value: showingRightPanel)

            bottomPlayerSection
        }
        .background(keyboardShortcuts)
        .overlay(TitlebarSeparatorEnforcer(trigger: "\(navigationPath.count)-\(searchQuery)-\(showingRightPanel)-\(player.queue.count)-\(player.currentStream?.id ?? "")-\(sidebarSelection.id)-\(rightPanelMode.id)"))
        .toolbarRole(.editor)
        .toolbar(content: toolbar)
        .touchBar { TouchBar() }
        .onChange(of: sidebarSelection) { _ in
            navigationPath = NavigationPath()
        }
        .onChange(of: searchQuery) { newQuery in
            if let url = detectSoundCloudURL(from: newQuery), newQuery.contains("/") {
                searchQuery = ""
                navigationPath.append(url)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .openTrackLyrics), perform: handleOpenLyrics)
        .onReceive(NotificationCenter.default.publisher(for: .openTrackPoster), perform: handleOpenPoster)
        .onReceive(NotificationCenter.default.publisher(for: .shareTrackToFriend), perform: handleShareTrack)
        .onReceive(NotificationCenter.default.publisher(for: .sharePlaylistToFriend), perform: handleSharePlaylist)
        .sheet(item: $itemToShare) { item in
            ShareItemSheet(item: item)
        }
        .sheet(isPresented: $showVoiceControlSettings) {
            VoiceControlSettingsView()
        }
        .onAppear {
            if !likes.isEmpty {
                WaveService.shared.cachedLikes = likes
            }
        }
        .onChange(of: likes) { newLikes in
            if !newLikes.isEmpty {
                WaveService.shared.cachedLikes = newLikes
            }
        }
        .modifier(VoiceControlReceiverModifier(
            player: player,
            likes: likes,
            posts: posts,
            toggleLikeTrack: toggleLikeTrack,
            toggleRepostTrack: toggleRepostTrack,
            showVoiceControlSettings: $showVoiceControlSettings,
            searchQuery: $searchQuery
        ))
        .onOpenURL(perform: handleOpenURL)
        .onReceive(NotificationCenter.default.publisher(for: .openFullscreenNowPlaying), perform: handleOpenFullscreenNowPlaying)
        .onChange(of: showingFullscreenNowPlaying, perform: handleFullscreenChange)
        .overlay {
            if showingFullscreenNowPlaying {
                FullscreenNowPlayingView(isPresented: $showingFullscreenNowPlaying)
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
                    .zIndex(100)
            }
        }
        .animation(.easeInOut(duration: 0.26), value: showingFullscreenNowPlaying)
        .handlesExternalEvents(preferring: ["*"], allowing: ["*"])
    }

    private func handleShareTrack(_ notification: Notification) {
        if let track = notification.object as? Track {
            itemToShare = .track(track)
        }
    }

    private func handleSharePlaylist(_ notification: Notification) {
        if let playlist = notification.object as? AnyPlaylist {
            itemToShare = .playlist(playlist)
        } else if let userP = notification.object as? UserPlaylist {
            itemToShare = .playlist(.user(userP))
        } else if let sysP = notification.object as? SystemPlaylist {
            itemToShare = .playlist(.system(sysP))
        }
    }

    private func handleOpenURL(_ url: URL) {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: true) else { return }
        components.scheme = "https"
        guard let newURL = components.url else { return }
        navigationPath.append(newURL)
    }

    private func handleFullscreenChange(_ isShowing: Bool) {
        for window in NSApp.windows {
            if window.isKeyWindow || window.isMainWindow || window.toolbar != nil {
                window.toolbar?.isVisible = !isShowing
                window.titleVisibility = isShowing ? .hidden : .visible
            }
        }
    }

    private func handleOpenLyrics(_ notification: Notification) {
        if let track = notification.object as? Track {
            inspectedTrack = track
        } else if inspectedTrack == nil {
            inspectedTrack = player.currentStream
        }
        rightPanelMode = .lyrics
        withAnimation(.easeInOut(duration: 0.22)) {
            showingRightPanel = true
        }
    }

    private func handleOpenPoster(_ notification: Notification) {
        if let track = notification.object as? Track {
            inspectedTrack = track
        } else if inspectedTrack == nil {
            inspectedTrack = player.currentStream
        }
        rightPanelMode = .poster
        withAnimation(.easeInOut(duration: 0.22)) {
            showingRightPanel = true
        }
    }

    private func handleOpenFullscreenNowPlaying(_ notification: Notification) {
        if let track = notification.object as? Track {
            if player.currentStream?.id != track.id {
                player.play([track], from: 0)
            }
        }
        withAnimation(.easeInOut(duration: 0.28)) {
            showingFullscreenNowPlaying = true
        }
    }

    @ViewBuilder private func sidebar() -> some View {
        List(selection: $sidebarSelection) {
            sidebarMenu(for: .discover)
            sidebarMenu(for: .stream)
            sidebarMenu(for: .wave)
            sidebarMenu(for: .likes)
            sidebarMenu(for: .reposts)
            sidebarMenu(for: .history)
            sidebarMenu(for: .following)
            sidebarMenu(for: .playlists)
        }
    }

    @ViewBuilder private func sidebarMenu(for detail: SidebarItem) -> some View {
        NavigationLink(value: detail) {
            HStack(spacing: 8) {
                if let imageName = detail.imageName {
                    Image(systemName: imageName)
                        .frame(width: 20, alignment: .center)
                }
                Text(detail.title)

                if detail == .wave {
                    Spacer(minLength: 4)
                    Text(LocalizedStringKey("badge.new"))
                        .font(.system(size: 8.5, weight: .heavy, design: .rounded))
                        .foregroundColor(.white)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(
                            Capsule()
                                .fill(
                                    LinearGradient(
                                        colors: [Color(hex: 0xFF5500), Color(hex: 0xFF2200)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                        )
                        .shadow(color: Color(hex: 0xFF5500).opacity(0.35), radius: 2, x: 0, y: 1)
                }
            }
        }
    }

    @ViewBuilder private func root(for item: SidebarItem) -> some View {
        Group {
            switch item {
            case .discover:
                DiscoverView()
            case .stream:
                let stream = SoundCloud.shared.get(.stream(), count: 50)
                PostList(for: stream)
            case .wave:
                MyWaveView()
                    .id("wave-\(refreshID)")
            case .likes:
                let likes = SoundCloud.shared.$user.filter { $0 != nil}
                    .flatMap { SoundCloud.shared.get(.trackLikes(of: $0!), count: 50) }
                    .eraseToAnyPublisher()
                TrackList(for: likes)
            case .reposts:
                let repostsPub = SoundCloud.shared.$user.filter { $0 != nil }
                    .flatMap { SoundCloud.shared.get(.userReposts(of: $0!), count: 50) }
                    .eraseToAnyPublisher()
                PostList(for: repostsPub)
            case .history:
                let history = SoundCloud.shared.get(.history(), count: 50)
                TrackList(for: history)
            case .following:
                let following = SoundCloud.shared.$user.filter { $0 != nil }
                    .flatMap { SoundCloud.shared.get(.followings(of: $0!), count: 50) }
                    .eraseToAnyPublisher()
                UserGrid(for: following)
            case .playlists:
                PlaylistsView()
            case .userPlaylist(_, let id):
                TrackList(request: .userPlaylist(id))
            case .systemPlaylist(_, let urn):
                TrackList(request: .systemPlaylist(urn))
            }
        }
            .navigationTitle(item.title)
            .id(item == .likes ? "\(item.id)-\(likes.count)-\(refreshID)" : (item == .reposts ? "\(item.id)-\(posts.count)-\(refreshID)" : "\(item.id)-\(refreshID)"))
    }

    @ToolbarContentBuilder private func toolbar() -> some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            Button {
                commandSubjects.filter.send()
            } label: {
                Image(systemName: "line.3.horizontal.decrease")
            }
            .help(LocalizedStringKey("menu.filter"))
        }

        ToolbarItem(placement: .principal) {
            ZStack(alignment: .trailing) {
                SearchField(
                    text: $searchQuery,
                    prompt: NSLocalizedString("menu.search", comment: ""),
                    focusPublisher: commandSubjects.search.eraseToAnyPublisher(),
                    onURLDetected: { url in
                        searchQuery = ""
                        navigationPath.append(url)
                    }
                )
                .frame(width: 220)

                if searchQuery.isEmpty {
                    Text("⌘F")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundColor(Color(nsColor: .tertiaryLabelColor))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .fill(Color(nsColor: .quaternaryLabelColor))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .stroke(Color(nsColor: .separatorColor).opacity(0.4), lineWidth: 0.5)
                        )
                        .padding(.trailing, 8)
                        .allowsHitTesting(false)
                }
            }
            .padding(.leading, 8)
        }

        ToolbarItem(placement: .primaryAction) {
            HStack(spacing: 6) {
                RefreshButton(action: refreshContent)
                    .padding(.leading, 8)

                // Notifications
                Button {
                    showNotificationsPopover.toggle()
                } label: {
                    ZStack(alignment: .topTrailing) {
                        Image(systemName: "bell")
                            .font(.system(size: 13.5, weight: .regular))
                            .foregroundColor(showNotificationsPopover ? .accentColor : .primary)
                            .frame(width: 24, height: 24)

                        if socialService.unreadNotificationsCount > 0 {
                            Circle()
                                .fill(Color.orange)
                                .frame(width: 7, height: 7)
                                .offset(x: -1, y: 1)
                        }
                    }
                }
                .buttonStyle(.plain)
                .help(NSLocalizedString("notifications.title", comment: ""))
                .popover(isPresented: $showNotificationsPopover, arrowEdge: .bottom) {
                    NotificationsPopover(
                        onNavigateToTrack: { track in
                            navigationPath.append(track)
                        },
                        onNavigateToUser: { user in
                            navigationPath.append(user)
                        },
                        onDismiss: {
                            showNotificationsPopover = false
                        }
                    )
                }

                // Messages
                Button {
                    showMessagesPopover.toggle()
                } label: {
                    ZStack(alignment: .topTrailing) {
                        Image(systemName: "envelope")
                            .font(.system(size: 13, weight: .regular))
                            .foregroundColor(showMessagesPopover ? .accentColor : .primary)
                            .frame(width: 24, height: 24)

                        if socialService.unreadConversationsCount > 0 {
                            Circle()
                                .fill(Color.orange)
                                .frame(width: 7, height: 7)
                                .offset(x: -1, y: 1)
                        }
                    }
                }
                .buttonStyle(.plain)
                .help(NSLocalizedString("messages.title", comment: ""))
                .popover(isPresented: $showMessagesPopover, arrowEdge: .bottom) {
                    MessagesPopover(
                        onNavigateToURL: { url in
                            navigationPath.append(url)
                        },
                        onDismiss: {
                            showMessagesPopover = false
                        }
                    )
                }

                // Profile Avatar
                Button {
                    showProfilePopover.toggle()
                } label: {
                    avatarView
                }
                .buttonStyle(.plain)
                .popover(isPresented: $showProfilePopover, arrowEdge: .bottom) {
                    profileMenuPopover
                }
            }
            .fixedSize()
            .padding(.trailing, 4)
        }
    }

    private func refreshContent() {
        refreshID = UUID()
        commandSubjects.reload.send()
    }

    private var avatarView: some View {
        Group {
            if let avatarURL = soundCloud.user?.avatarURL {
                AsyncImage(url: avatarURL) { phase in
                    if let image = phase.image {
                        image
                            .resizable()
                            .scaledToFill()
                    } else {
                        Image(systemName: "person.crop.circle.fill")
                            .resizable()
                            .scaledToFit()
                            .foregroundColor(.secondary)
                    }
                }
                .frame(width: 26, height: 26)
                .clipShape(Circle())
                .overlay(Circle().stroke(Color.primary.opacity(0.18), lineWidth: 1))
            } else {
                Image(systemName: "person.crop.circle.fill")
                    .resizable()
                    .frame(width: 26, height: 26)
                    .foregroundColor(.secondary)
            }
        }
        .contentShape(Circle())
        .onHover { isHovered in
            if isHovered {
                NSCursor.pointingHand.push()
            } else {
                NSCursor.pop()
            }
        }
    }

    private var profileMenuPopover: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let user = soundCloud.user {
                Button {
                    showProfilePopover = false
                    navigationPath.append(user)
                } label: {
                    HStack(spacing: 10) {
                        AsyncImage(url: user.avatarURL) { phase in
                            if let img = phase.image {
                                img.resizable().scaledToFill()
                            } else {
                                Image(systemName: "person.crop.circle.fill")
                            }
                        }
                        .frame(width: 28, height: 28)
                        .clipShape(Circle())

                        VStack(alignment: .leading, spacing: 1) {
                            Text(user.username)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(.primary)
                                .lineLimit(1)
                            Text(LocalizedStringKey("profile.viewProfile"))
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }

                        Spacer()

                        Image(systemName: "chevron.right")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Divider()
                    .padding(.vertical, 2)
            }

            Button(role: .destructive) {
                showProfilePopover = false
                logOut()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "rectangle.portrait.and.arrow.right")
                        .font(.system(size: 12))
                    Text(LocalizedStringKey("profile.logout"))
                        .font(.system(size: 12.5, weight: .medium))
                }
                .foregroundColor(.red)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(6)
        .frame(width: 230)
    }

}

struct SearchField: NSViewRepresentable {
    @Binding var text: String
    var prompt: String
    var focusPublisher: AnyPublisher<(), Never>?
    var onURLDetected: ((URL) -> Void)? = nil

    func makeNSView(context: Context) -> NSSearchField {
        let field = NSSearchField()
        field.placeholderString = prompt
        field.focusRingType = .none
        field.delegate = context.coordinator
        field.target = context.coordinator
        field.action = #selector(Coordinator.action(_:))
        field.centersPlaceholder = false

        context.coordinator.cancellable = focusPublisher?.sink { [weak field] _ in
            field?.window?.makeFirstResponder(field)
        }

        return field
    }

    func updateNSView(_ nsView: NSSearchField, context: Context) {
        if nsView.stringValue != text {
            nsView.stringValue = text
        }
        nsView.placeholderString = prompt
        context.coordinator.onURLDetected = onURLDetected
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, onURLDetected: onURLDetected)
    }

    final class Coordinator: NSObject, NSSearchFieldDelegate {
        @Binding var text: String
        var onURLDetected: ((URL) -> Void)?
        var cancellable: AnyCancellable?

        init(text: Binding<String>, onURLDetected: ((URL) -> Void)? = nil) {
            self._text = text
            self.onURLDetected = onURLDetected
        }

        func controlTextDidChange(_ obj: Notification) {
            guard let field = obj.object as? NSSearchField else { return }
            let query = field.stringValue
            if let url = detectSoundCloudURL(from: query), query.contains("/") {
                field.stringValue = ""
                text = ""
                onURLDetected?(url)
                return
            }
            text = query
        }

        @objc func action(_ sender: NSSearchField) {
            let query = sender.stringValue
            if let url = detectSoundCloudURL(from: query) {
                sender.stringValue = ""
                text = ""
                onURLDetected?(url)
                return
            }
            text = query
        }
    }
}

private struct RefreshButton: View {
    let action: () -> Void
    @State private var isSpinning = false

    var body: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.45)) {
                isSpinning = true
            }
            action()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
                isSpinning = false
            }
        } label: {
            Image(systemName: "arrow.clockwise")
                .font(.system(size: 13, weight: .regular))
                .foregroundColor(.primary)
                .rotationEffect(.degrees(isSpinning ? 360 : 0))
                .frame(width: 24, height: 24)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(LocalizedStringKey("menu.refresh"))
    }
}

private final class WindowSeparatorLineView: NSView {
    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = NSColor.separatorColor.cgColor
        layer?.zPosition = 999999
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        wantsLayer = true
        layer?.backgroundColor = NSColor.separatorColor.cgColor
        layer?.zPosition = 999999
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        return nil
    }

    override func updateLayer() {
        super.updateLayer()
        layer?.backgroundColor = NSColor.separatorColor.cgColor
    }
}

private struct TitlebarSeparatorEnforcer: NSViewRepresentable {
    var trigger: String = ""

    func makeNSView(context: Context) -> EnforcerNSView {
        return EnforcerNSView()
    }

    func updateNSView(_ nsView: EnforcerNSView, context: Context) {
        nsView.enforce()
        DispatchQueue.main.async {
            nsView.enforce()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            nsView.enforce()
        }
    }
}

private final class EnforcerNSView: NSView {
    private let separatorView = WindowSeparatorLineView()
    private var windowObservation: NSKeyValueObservation?

    override func hitTest(_ point: NSPoint) -> NSView? {
        return nil
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        setupObservers()
        enforce()
    }

    override func layout() {
        super.layout()
        enforce()
    }

    func setupObservers() {
        guard let window = self.window ?? NSApp.mainWindow ?? NSApp.windows.first(where: { $0.toolbar != nil }) else { return }

        if windowObservation == nil {
            windowObservation = window.observe(\.titlebarSeparatorStyle, options: [.initial, .new]) { [weak self] win, _ in
                if win.titlebarSeparatorStyle != .none {
                    win.titlebarSeparatorStyle = .none
                }
                self?.enforce()
            }

            NotificationCenter.default.removeObserver(self)
            NotificationCenter.default.addObserver(self, selector: #selector(windowDidUpdate), name: NSWindow.didBecomeKeyNotification, object: window)
            NotificationCenter.default.addObserver(self, selector: #selector(windowDidUpdate), name: NSWindow.didResignKeyNotification, object: window)
            NotificationCenter.default.addObserver(self, selector: #selector(windowDidUpdate), name: NSWindow.didResizeNotification, object: window)
            NotificationCenter.default.addObserver(self, selector: #selector(windowDidUpdate), name: NSSplitView.didResizeSubviewsNotification, object: nil)
        }

        enforce()
    }

    @objc private func windowDidUpdate() {
        enforce()
    }

    func enforce() {
        guard let window = self.window ?? NSApp.mainWindow ?? NSApp.windows.first(where: { $0.toolbar != nil }) else { return }

        if window.titlebarSeparatorStyle != .none {
            window.titlebarSeparatorStyle = .none
        }

        let splitViews = findAllSplitViews(in: window.contentView)
        for sv in splitViews {
            if let svc = sv.delegate as? NSSplitViewController {
                for item in svc.splitViewItems {
                    if item.titlebarSeparatorStyle != .none {
                        item.titlebarSeparatorStyle = .none
                    }
                }
            }
        }

        ToolbarMenuDisabler.disable()
        if let tb = window.toolbar {
            if tb.allowsUserCustomization {
                tb.allowsUserCustomization = false
            }
        }
        disableToolbarMenu(in: window.contentView?.superview)

        updateSeparator(window: window, splitViews: splitViews)
        fixScrollbars(in: window.contentView)
    }

    private func disableToolbarMenu(in view: NSView?) {
        guard let view = view else { return }
        let className = NSStringFromClass(type(of: view))
        if className.contains("Toolbar") || className.contains("Titlebar") {
            view.menu = nil
        }
        for subview in view.subviews {
            disableToolbarMenu(in: subview)
        }
    }

    private func updateSeparator(window: NSWindow, splitViews: [NSSplitView]) {
        guard let frameView = window.contentView?.superview ?? window.contentView else { return }

        if separatorView.superview != frameView {
            separatorView.removeFromSuperview()
            frameView.addSubview(separatorView, positioned: .above, relativeTo: nil)
        } else {
            frameView.addSubview(separatorView, positioned: .above, relativeTo: nil)
        }
        separatorView.layer?.zPosition = 999999

        if let tb = window.toolbar, !tb.isVisible {
            separatorView.isHidden = true
            return
        }

        separatorView.isHidden = false

        var startX: CGFloat = 0
        if let primarySplit = splitViews.first,
           let sidebarView = primarySplit.subviews.first,
           !sidebarView.isHidden,
           sidebarView.frame.width > 30 {
            let sidebarRectInWindow = sidebarView.convert(sidebarView.bounds, to: nil)
            let sidebarRectInFrameView = frameView.convert(sidebarRectInWindow, from: nil)
            startX = max(0, sidebarRectInFrameView.maxX)
        }

        let scale = window.backingScaleFactor > 0 ? window.backingScaleFactor : 2.0
        let lineHeight: CGFloat = 1.0 / scale
        let totalWidth = frameView.bounds.width
        let lineW = max(0, totalWidth - startX)

        let contentRectInWindow = window.contentLayoutRect
        let contentRectInFrame = frameView.convert(contentRectInWindow, from: nil)

        let lineY: CGFloat
        if frameView.isFlipped {
            lineY = contentRectInFrame.minY
        } else {
            lineY = contentRectInFrame.maxY - lineHeight
        }

        separatorView.layer?.backgroundColor = NSColor.separatorColor.cgColor
        separatorView.frame = NSRect(
            x: startX,
            y: lineY,
            width: lineW,
            height: lineHeight
        )
    }

    private func fixScrollbars(in view: NSView?) {
        guard let view = view else { return }
        if let scrollView = view as? NSScrollView {
            if scrollView.scrollerStyle != .overlay {
                scrollView.scrollerStyle = .overlay
            }
            if let vs = scrollView.verticalScroller, vs.controlSize != .small {
                vs.controlSize = .small
            }
            if let hs = scrollView.horizontalScroller, hs.controlSize != .small {
                hs.controlSize = .small
            }
        }
        for subview in view.subviews {
            fixScrollbars(in: subview)
        }
    }

    private func findAllSplitViews(in view: NSView?) -> [NSSplitView] {
        guard let view = view else { return [] }
        var result: [NSSplitView] = []
        if let sv = view as? NSSplitView {
            result.append(sv)
        }
        for subview in view.subviews {
            result.append(contentsOf: findAllSplitViews(in: subview))
        }
        return result
    }

    deinit {
        separatorView.removeFromSuperview()
        windowObservation?.invalidate()
        NotificationCenter.default.removeObserver(self)
    }
}


struct MainView_Previews: PreviewProvider {

    static var previews: some View {
        let player: StreamPlayer = {
            let player = StreamPlayer()
            player.enqueue(Preview.tracks)
            return player
        }()

        MainView()
            .environmentObject(player)
            .environmentObject(CommandSubject())
    }

}

private struct VoiceControlReceiverModifier: ViewModifier {
    let player: StreamPlayer
    let likes: [Track]
    let posts: [Post]
    let toggleLikeTrack: (Track) -> () -> ()
    let toggleRepostTrack: (Track) -> () -> ()
    @Binding var showVoiceControlSettings: Bool
    @Binding var searchQuery: String
    @State private var subscriptions = Set<AnyCancellable>()
    
    func body(content: Content) -> some View {
        content
            .onReceive(NotificationCenter.default.publisher(for: .openVoiceControlSettings)) { _ in
                showVoiceControlSettings = true
            }
            .onReceive(NotificationCenter.default.publisher(for: .voiceControlLikeTrack)) { _ in
                guard let current = player.currentStream else { return }
                let isLiked = likes.contains { $0.id == current.id }
                if !isLiked {
                    toggleLikeTrack(current)()
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .voiceControlUnlikeTrack)) { _ in
                guard let current = player.currentStream else { return }
                let isLiked = likes.contains { $0.id == current.id }
                if isLiked {
                    toggleLikeTrack(current)()
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .voiceControlPlayWave)) { _ in
                let currentLikes = !WaveService.shared.cachedLikes.isEmpty ? WaveService.shared.cachedLikes : likes
                WaveService.shared.playWave(likes: currentLikes, player: player)
            }
            .onReceive(NotificationCenter.default.publisher(for: .voiceControlRefreshWave)) { _ in
                let currentLikes = !WaveService.shared.cachedLikes.isEmpty ? WaveService.shared.cachedLikes : likes
                WaveService.shared.playWave(likes: currentLikes, player: player, force: true)
            }
            .onReceive(NotificationCenter.default.publisher(for: .voiceControlPlayLikes)) { _ in
                if !WaveService.shared.cachedLikes.isEmpty {
                    player.play(WaveService.shared.cachedLikes, from: 0)
                } else if !likes.isEmpty {
                    player.play(likes, from: 0)
                } else if let data = UserDefaults.standard.data(forKey: "likes"),
                          let decoded = try? JSONDecoder().decode([Track].self, from: data),
                          !decoded.isEmpty {
                    player.play(decoded, from: 0)
                } else if let user = SoundCloud.shared.user {
                    SoundCloud.shared.get(all: .trackLikes(of: user))
                        .map { $0.map { $0.item } }
                        .receive(on: RunLoop.main)
                        .sink(receiveCompletion: { _ in }, receiveValue: { tracks in
                            if !tracks.isEmpty {
                                WaveService.shared.cachedLikes = tracks
                                player.play(tracks, from: 0)
                            }
                        })
                        .store(in: &subscriptions)
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .voiceControlRepostTrack)) { _ in
                guard let current = player.currentStream else { return }
                let isReposted = isTrackReposted(current)
                if !isReposted {
                    toggleRepostTrack(current)()
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .voiceControlUnrepostTrack)) { _ in
                guard let current = player.currentStream else { return }
                let isReposted = isTrackReposted(current)
                if isReposted {
                    toggleRepostTrack(current)()
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .voiceControlPlayReposts)) { _ in
                let repostedTracks = posts.filter { $0.isRepost && $0.isTrack }.compactMap { $0.tracks.first }
                if !repostedTracks.isEmpty {
                    player.play(repostedTracks, from: 0)
                } else if let user = SoundCloud.shared.user {
                    SoundCloud.shared.get(all: .userReposts(of: user))
                        .receive(on: RunLoop.main)
                        .sink(receiveCompletion: { _ in }, receiveValue: { fetchedPosts in
                            let tracks = fetchedPosts.filter { $0.isRepost && $0.isTrack }.compactMap { $0.tracks.first }
                            if !tracks.isEmpty {
                                player.play(tracks, from: 0)
                            }
                        })
                        .store(in: &subscriptions)
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .voiceControlPlayStream)) { _ in
                SoundCloud.shared.get(all: .stream())
                    .receive(on: RunLoop.main)
                    .sink(receiveCompletion: { _ in }, receiveValue: { streamPosts in
                        let tracks = streamPosts.flatMap { $0.tracks }
                        if !tracks.isEmpty {
                            player.play(tracks, from: 0)
                        }
                    })
                    .store(in: &subscriptions)
            }
            .onReceive(NotificationCenter.default.publisher(for: .voiceControlShareTrack)) { notification in
                guard let targetQuery = notification.object as? String else { return }
                guard let currentTrack = player.currentStream else {
                    VoiceControlService.shared.triggerCustomHUD(NSLocalizedString("voice.hud.nothingPlaying", comment: ""), icon: "music.note")
                    return
                }
                
                let conversations = SoundCloudSocialService.shared.conversations
                if let match = UserAliasService.shared.matchConversation(for: targetQuery, in: conversations) {
                    SoundCloudSocialService.shared.sendMessage(to: match.user.id, content: currentTrack.permalinkURL.absoluteString)
                        .receive(on: RunLoop.main)
                        .sink(receiveCompletion: { completion in
                            if case .failure = completion {
                                VoiceControlService.shared.triggerCustomHUD(String(format: NSLocalizedString("voice.hud.error", comment: ""), match.matchedName), icon: "exclamationmark.triangle")
                            }
                        }, receiveValue: { _ in
                            VoiceControlService.shared.triggerCustomHUD(String(format: NSLocalizedString("voice.hud.sent", comment: ""), match.matchedName), icon: "paperplane.fill")
                        })
                        .store(in: &subscriptions)
                } else {
                    VoiceControlService.shared.triggerCustomHUD(String(format: NSLocalizedString("voice.hud.contactNotFound", comment: ""), targetQuery), icon: "person.crop.circle.badge.questionmark")
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .voiceControlPostComment)) { notification in
                guard let text = notification.object as? String, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
                guard let currentTrack = player.currentStream else {
                    VoiceControlService.shared.triggerCustomHUD(NSLocalizedString("voice.hud.nothingPlaying", comment: ""), icon: "music.note")
                    return
                }
                let cleanText = text.trimmingCharacters(in: .whitespacesAndNewlines)
                let timestamp: TimeInterval? = player.progress
                
                SoundCloud.shared.get(.comment(cleanText, at: timestamp, on: currentTrack))
                    .receive(on: RunLoop.main)
                    .sink(receiveCompletion: { completion in
                        if case .failure(let error) = completion {
                            VoiceControlService.shared.triggerCustomHUD(NSLocalizedString("voice.hud.commentError", comment: ""), icon: "bubble.left.and.exclamationmark")
                            print("Failed to post comment: \(error)")
                        }
                    }, receiveValue: { newComment in
                        TimedCommentsService.shared.addComment(newComment)
                        VoiceControlService.shared.triggerCustomHUD(NSLocalizedString("voice.hud.commentAdded", comment: ""), icon: "bubble.left.fill")
                    })
                    .store(in: &subscriptions)
            }
            .onReceive(NotificationCenter.default.publisher(for: .voiceControlSearchAndPlay)) { notification in
                guard let query = notification.object as? String, !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
                let cleanedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
                searchQuery = cleanedQuery
                VoiceControlService.shared.triggerCustomHUD(String(format: NSLocalizedString("voice.hud.search", comment: ""), cleanedQuery), icon: "magnifyingglass")
                
                SoundCloud.shared.get(.search(cleanedQuery))
                    .receive(on: RunLoop.main)
                    .sink(receiveCompletion: { completion in
                        if case .failure(let error) = completion {
                            print("Voice search failed: \(error)")
                        }
                    }, receiveValue: { (page: Page<Some>) in
                        let tracks: [Track] = page.collection.compactMap { item in
                            if case .track(let track) = item {
                                return track
                            }
                            return nil
                        }
                        if !tracks.isEmpty {
                            player.play(tracks, from: 0)
                        } else {
                            VoiceControlService.shared.triggerCustomHUD(NSLocalizedString("voice.hud.nothingFound", comment: ""), icon: "magnifyingglass")
                        }
                    })
                    .store(in: &subscriptions)
            }
    }
    
    private func isTrackReposted(_ track: Track) -> Bool {
        for post in posts {
            if post.isRepost && post.isTrack {
                if let firstTrack = post.tracks.first, firstTrack.id == track.id {
                    return true
                }
            }
        }
        return false
    }
}
