//
//  NuageApp.swift
//  Nuage
//
//  Created by Laurin Brandner on 06.12.20.
//

import SwiftUI
import Combine
import WebKit
import SoundCloud

private let accessTokenKey = "accessToken"
private let accessTokenExpiryDateKey = "accessTokenExpiryDate"
private let userKey = "user"
private let playlistsKey = "playlists"
private let likesKey = "likes"
private let postsKey = "posts"

private struct ShowCreatedPlaylistsKey: EnvironmentKey {
    static let defaultValue = true
}

private struct ShowLikedPlaylistsKey: EnvironmentKey {
    static let defaultValue = true
}

private struct PlaylistKey: EnvironmentKey {
    static let defaultValue = [AnyPlaylist]()
}

private struct LikesKey: EnvironmentKey {
    static let defaultValue = [Track]()
}

private struct PostsKey: EnvironmentKey {
    static let defaultValue = [Post]()
}

private struct ToggleLikeTrackKey: EnvironmentKey {
    static let defaultValue: (Track) -> () -> () = { _ in return { fatalError("Did not set the toggleLike action") } }
}

private struct ToggleRepostTrackKey: EnvironmentKey {
    static let defaultValue: (Track) -> () -> () = { _ in return { fatalError("Did not set the toggleRepost action") } }
}

private struct ToggleLikePlaylistKey: EnvironmentKey {
    static let defaultValue: (AnyPlaylist) -> () -> () = { _ in return { fatalError("Did not set the toggleLike action") } }
}

private struct ToggleRepostPlaylistKey: EnvironmentKey {
    static let defaultValue: (UserPlaylist) -> () -> () = { _ in return { fatalError("Did not set the toggleRepost action") } }
}

extension EnvironmentValues {
    var showCreatedPlaylists: Bool {
        get { self[ShowCreatedPlaylistsKey.self] }
        set { self[ShowCreatedPlaylistsKey.self] = newValue }
    }
    
    var showLikedPlaylists: Bool {
        get { self[ShowLikedPlaylistsKey.self] }
        set { self[ShowLikedPlaylistsKey.self] = newValue }
    }
    
    var playlists: [AnyPlaylist] {
        get { self[PlaylistKey.self] }
        set { self[PlaylistKey.self] = newValue }
    }
    
    var likes: [Track] {
        get { self[LikesKey.self] }
        set { self[LikesKey.self] = newValue }
    }
    
    var posts: [Post] {
        get { self[PostsKey.self] }
        set { self[PostsKey.self] = newValue }
    }
    
    var toggleLikeTrack: (Track) -> () -> () {
        get { self[ToggleLikeTrackKey.self] }
        set { self[ToggleLikeTrackKey.self] = newValue }
    }
    
    var toggleRepostTrack: (Track) -> () -> () {
        get { self[ToggleRepostTrackKey.self] }
        set { self[ToggleRepostTrackKey.self] = newValue }
    }
    
    var toggleLikePlaylist: (AnyPlaylist) -> () -> () {
        get { self[ToggleLikePlaylistKey.self] }
        set { self[ToggleLikePlaylistKey.self] = newValue }
    }
    
    var toggleRepostPlaylist: (UserPlaylist) -> () -> () {
        get { self[ToggleRepostPlaylistKey.self] }
        set { self[ToggleRepostPlaylistKey.self] = newValue }
    }
    
    var logOut: () -> () {
        get { self[LogOutKey.self] }
        set { self[LogOutKey.self] = newValue }
    }
    
    var reloadPlaylists: () -> () {
        get { self[ReloadPlaylistsKey.self] }
        set { self[ReloadPlaylistsKey.self] = newValue }
    }
    
    var deletePlaylist: (UserPlaylist) -> () {
        get { self[DeletePlaylistKey.self] }
        set { self[DeletePlaylistKey.self] = newValue }
    }
    
    var saveCreatedPlaylist: (UserPlaylist) -> () {
        get { self[SaveCreatedPlaylistKey.self] }
        set { self[SaveCreatedPlaylistKey.self] = newValue }
    }
    
    var updateUserPlaylist: (UserPlaylist) -> () {
        get { self[UpdateUserPlaylistKey.self] }
        set { self[UpdateUserPlaylistKey.self] = newValue }
    }
}

private struct ReloadPlaylistsKey: EnvironmentKey {
    static let defaultValue: () -> () = { }
}

private struct DeletePlaylistKey: EnvironmentKey {
    static let defaultValue: (UserPlaylist) -> () = { _ in }
}

private struct SaveCreatedPlaylistKey: EnvironmentKey {
    static let defaultValue: (UserPlaylist) -> () = { _ in }
}

private struct UpdateUserPlaylistKey: EnvironmentKey {
    static let defaultValue: (UserPlaylist) -> () = { _ in }
}

private struct LogOutKey: EnvironmentKey {
    static let defaultValue: () -> () = { }
}

class CommandSubject: ObservableObject {
    var filter = PassthroughSubject<(), Never>()
    var search = PassthroughSubject<(), Never>()
    var reload = PassthroughSubject<(), Never>()
}

@main
struct NuageApp: App {
    
    @StateObject private var player = StreamPlayer()
    private var commandSubjects = CommandSubject()
    
    @AppStorage("appLanguage") private var appLanguage: String = Locale.current.languageCode ?? "en"
    @AppStorage("showTimedComments") private var showTimedComments: Bool = true
    @AppStorage("enableDiscordPresence") private var enableDiscordPresence: Bool = true
    
    @State private var showCreatedPlaylists = true
    @State private var showLikedPlaylists = true
    
    @State private var playlists: [AnyPlaylist]
    @State private var likes: [Track]
    @State private var posts: [Post]
    @State private var loggedIn: Bool
    @State private var subscriptions = Set<AnyCancellable>()
    
    var body: some Scene {
        WindowGroup {
            if loggedIn {
                MainView()
                    .frame(minWidth: 850, idealWidth: 1050, minHeight: 550, idealHeight: 650)
                    .environmentObject(player)
                    .environmentObject(commandSubjects)
                    .environment(\.showCreatedPlaylists, showCreatedPlaylists)
                    .environment(\.showLikedPlaylists, showLikedPlaylists)
                    .environment(\.playlists, playlists)
                    .environment(\.likes, likes)
                    .environment(\.posts, posts)
                    .environment(\.toggleLikeTrack, toggleLike)
                    .environment(\.toggleRepostTrack, toggleRepost)
                    .environment(\.toggleLikePlaylist, toggleLike)
                    .environment(\.toggleRepostPlaylist, toggleRepost)
                    .environment(\.reloadPlaylists, reloadLibrary)
                    .environment(\.deletePlaylist, deletePlaylistAction)
                    .environment(\.saveCreatedPlaylist, saveCreatedPlaylistAction)
                    .environment(\.updateUserPlaylist, updateUserPlaylistAction)
                    .environment(\.logOut, logOut)
                    .environment(\.locale, Locale(identifier: appLanguage))
                    .id(appLanguage)
                    .onAppear {
                        MenuLocalizer.startObserving()
                        DispatchQueue.main.async {
                            MenuLocalizer.updateMenu(to: appLanguage)
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            MenuLocalizer.updateMenu(to: appLanguage)
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                            MenuLocalizer.updateMenu(to: appLanguage)
                        }
                        reloadLibrary()
                        reloadLikes()
                        reloadPosts()
                        
                        commandSubjects.reload
                            .sink {
                                reloadLibrary()
                                reloadLikes()
                                reloadPosts()
                            }
                            .store(in: &subscriptions)
                        
                        player.$currentStream
                            .filter { $0 != nil}
                            .flatMap { SoundCloud.shared.perform(.addToHistory($0!)) }
                            .sink(receiveCompletion: { completion in
                                if case let .failure(error) = completion {
                                    print("Failed to add track to history: \(error)")
                                }
                            }, receiveValue: { _ in })
                            .store(in: &subscriptions)
                    }
            }
            else {
                LoginView { accessToken, expiryDate in
                    let defaults = UserDefaults.standard
                    defaults.set(accessToken, forKey: accessTokenKey)
                    defaults.set(expiryDate, forKey: accessTokenExpiryDateKey)
                    SoundCloud.shared.accessToken = accessToken
                    loggedIn = true
                }
                .environment(\.locale, Locale(identifier: appLanguage))
            }
        }
        .defaultSize(width: 1000, height: 650)
        .commands(content: commands)
    }
    
    @CommandsBuilder private func commands() -> some Commands {
        viewMenu()
        settingsMenu()
        
        CommandMenu(LocalizedStringKey("menu.language")) {
            Toggle("English", isOn: Binding(
                get: { appLanguage == "en" },
                set: { if $0 { changeLanguage(to: "en") } }
            ))
            Toggle("Русский", isOn: Binding(
                get: { appLanguage == "ru" },
                set: { if $0 { changeLanguage(to: "ru") } }
            ))
        }
        
        playbackMenu()
    }
    
    @CommandsBuilder private func viewMenu() -> some Commands {
        CommandMenu(LocalizedStringKey("menu.view")) {
            Toggle(LocalizedStringKey("menu.showComments"), isOn: $showTimedComments)
                .keyboardShortcut("c", modifiers: [.command, .shift])
        }
    }
    
    @CommandsBuilder private func settingsMenu() -> some Commands {
        CommandMenu(LocalizedStringKey("menu.settings")) {
            Toggle(LocalizedStringKey("menu.settings.discordRPC"), isOn: $enableDiscordPresence)
            Toggle(LocalizedStringKey("voice.title"), isOn: Binding(
                get: { VoiceControlService.shared.isEnabled },
                set: { VoiceControlService.shared.isEnabled = $0 }
            ))
            Divider()
            Button(LocalizedStringKey("voice.settings")) {
                NotificationCenter.default.post(name: .openVoiceControlSettings, object: nil)
            }
        }
    }
    
    private func changeLanguage(to language: String) {
        Bundle.setLanguage(language)
        UserDefaults.standard.set([language], forKey: "AppleLanguages")
        appLanguage = language
        MenuLocalizer.updateMenu(to: language)
        DispatchQueue.main.async {
            MenuLocalizer.updateMenu(to: language)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            MenuLocalizer.updateMenu(to: language)
        }
    }
    
    @CommandsBuilder private func playbackMenu() -> some Commands {
        CommandMenu(LocalizedStringKey("menu.playback")) {
            let playbackToggleTitle = player.isPlaying ? "menu.pause" : "menu.play"
            Button(LocalizedStringKey(playbackToggleTitle), action: player.togglePlayback)
            
            Divider()
            
            playbackControls()
            
            Divider()
            
            Toggle(LocalizedStringKey("menu.shuffle"), isOn: $player.shuffleQueue)
                .keyboardShortcut("s", modifiers: [.command])

            Toggle(LocalizedStringKey("menu.repeat"), isOn: $player.repeatQueue)
                .keyboardShortcut("r", modifiers: [.command])
            
            Divider()
            
            Button(LocalizedStringKey("menu.volumeUp")) {
                player.volume += 0.05
            }
            .keyboardShortcut(.upArrow, modifiers: [.command])

            Button(LocalizedStringKey("menu.volumeDown")) {
                player.volume -= 0.05
            }
            .keyboardShortcut(.downArrow, modifiers: [.command])
        }
    }
    
    @ViewBuilder private func playbackControls() -> some View {
        Button(LocalizedStringKey("menu.next"), action: player.advanceForward)
            .keyboardShortcut(.rightArrow, modifiers: .command)
        
        Button(LocalizedStringKey("menu.previous"), action: player.advanceBackward)
            .keyboardShortcut(.leftArrow, modifiers: .command)
        
        Button(LocalizedStringKey("menu.seekForward"), action: player.seekForward)
            .keyboardShortcut(.rightArrow, modifiers: [.command, .shift])
        
        Button(LocalizedStringKey("menu.seekBackward"), action: player.seekBackward)
            .keyboardShortcut(.leftArrow, modifiers: [.command, .shift])
    }
    
    init() {
        // Migrate preferences from sandboxed container if needed
        let containerPlistPath = ("~/Library/Containers/ch.laurinbrandner.nuage/Data/Library/Preferences/ch.laurinbrandner.nuage.plist" as NSString).expandingTildeInPath
        if FileManager.default.fileExists(atPath: containerPlistPath),
           let containerDict = NSDictionary(contentsOfFile: containerPlistPath) as? [String: Any] {
            let defaults = UserDefaults.standard
            for (key, value) in containerDict {
                if defaults.object(forKey: key) == nil {
                    defaults.set(value, forKey: key)
                }
            }
        }
        _ = DiscordRPCService.shared
        
        let MB = 1024*1024
        URLCache.shared = URLCache(memoryCapacity: 10*MB, diskCapacity: 20*MB)
        URLSession.shared.configuration.requestCachePolicy = .returnCacheDataElseLoad
        
        let defaults = UserDefaults.standard
        defaults.register(defaults: [
            "AppleShowScrollBars": "WhenScrolling"
        ])
        ToolbarMenuDisabler.disable()
        let savedLanguage = defaults.string(forKey: "appLanguage") ?? (Locale.current.languageCode ?? "en")
        Bundle.setLanguage(savedLanguage)
        MenuLocalizer.startObserving()
        DispatchQueue.main.async {
            MenuLocalizer.updateMenu(to: savedLanguage)
        }
        
        if let data = defaults.data(forKey: userKey) {
            do {
                SoundCloud.shared.user = try JSONDecoder().decode(User.self, from: data)
            }
            catch {
                defaults.removeObject(forKey: userKey)
                print("Failed to load user from UserDefaults: \(error)")
            }
        }
        let token = defaults.object(forKey: accessTokenKey)
        let expiryDate = defaults.object(forKey: accessTokenExpiryDateKey)
        
        _loggedIn = State(initialValue: false)
        if let token = token as? String {
            if let exipryDate = expiryDate as? Date, exipryDate < Date() {
                defaults.set(nil, forKey: accessTokenKey)
                defaults.set(nil, forKey: accessTokenExpiryDateKey)
            }
            else {
                SoundCloud.shared.accessToken = token
                _loggedIn = State(initialValue: true)
            }
        }
        
        if let data = defaults.data(forKey: playlistsKey) {
            do {
                playlists = try JSONDecoder().decode([AnyPlaylist].self, from: data)
            } catch {
                print("Failed to decode playlists from UserDefaults: \(error)")
                defaults.removeObject(forKey: playlistsKey)
                playlists = []
            }
        }
        else {
            playlists = []
        }
        
        if let data = defaults.data(forKey: likesKey) {
            do {
                likes = try JSONDecoder().decode([Track].self, from: data)
            } catch {
                print("Failed to decode likes from UserDefaults: \(error)")
                defaults.removeObject(forKey: likesKey)
                likes = []
            }
        }
        else {
            likes = []
        }
        
        if let data = defaults.data(forKey: postsKey) {
            do {
                posts = try JSONDecoder().decode([Post].self, from: data)
            } catch {
                print("Failed to decode posts from UserDefaults: \(error)")
                defaults.removeObject(forKey: postsKey)
                posts = []
            }
        }
        else {
            posts = []
        }
        
        WaveService.shared.cachedLikes = likes
        
        SoundCloud.shared.$user.sink { user in
            if let user = user {
                let data = try! JSONEncoder().encode(user)
                defaults.set(data, forKey: userKey)
            }
            else {
                defaults.set(nil, forKey: userKey)
            }
        }
        .store(in: &subscriptions)
    }
    
    private func logOut() {
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: accessTokenKey)
        defaults.removeObject(forKey: accessTokenExpiryDateKey)
        defaults.removeObject(forKey: userKey)
        defaults.removeObject(forKey: likesKey)
        defaults.removeObject(forKey: postsKey)
        defaults.removeObject(forKey: playlistsKey)
        defaults.removeObject(forKey: "datadome_cookie")
        defaults.synchronize()
        
        // Remove cookies from WKWebsiteDataStore so it doesn't auto-login immediately
        let cookieStore = WKWebsiteDataStore.default().httpCookieStore
        cookieStore.getAllCookies { cookies in
            for cookie in cookies {
                if cookie.name == "oauth_token" || cookie.domain.contains("soundcloud") {
                    cookieStore.delete(cookie)
                }
            }
        }
        if let sharedCookies = HTTPCookieStorage.shared.cookies {
            for cookie in sharedCookies {
                if cookie.name == "oauth_token" || cookie.domain.contains("soundcloud") {
                    HTTPCookieStorage.shared.deleteCookie(cookie)
                }
            }
        }
        
        player.reset()
        
        SoundCloud.shared.accessToken = nil
        SoundCloud.shared.user = nil
        likes = []
        posts = []
        playlists = []
        loggedIn = false
    }
    
    private func saveLikes() {
        if let data = try? JSONEncoder().encode(likes) {
            UserDefaults.standard.set(data, forKey: likesKey)
        }
    }
    
    private func savePosts() {
        if let data = try? JSONEncoder().encode(posts) {
            UserDefaults.standard.set(data, forKey: postsKey)
        }
    }
    
    private func savePlaylists() {
        if let data = try? JSONEncoder().encode(playlists) {
            UserDefaults.standard.set(data, forKey: playlistsKey)
        }
    }
    
    private func reloadLibrary() {
        SoundCloud.shared.get(all: .library())
            .map { $0.map { $0.item } }
            .replaceError(with: playlists)
            .receive(on: RunLoop.main)
            .sink { newPlaylists in
                self.playlists = newPlaylists
                self.savePlaylists()
            }
            .store(in: &subscriptions)
    }
    
    private func reloadLikes() {
        SoundCloud.shared.$user
            .filter { $0 != nil}
            .flatMap { SoundCloud.shared.get(all: .trackLikes(of: $0!)) }
            .map { $0.map { $0.item } }
            .replaceError(with: likes)
            .receive(on: RunLoop.main)
            .sink { newLikes in
                self.likes = newLikes
                self.saveLikes()
                WaveService.shared.cachedLikes = newLikes
            }
            .store(in: &subscriptions)
    }
    
    private func reloadPosts() {
        SoundCloud.shared.$user
            .filter { $0 != nil}
            .flatMap { SoundCloud.shared.get(all: .userReposts(of: $0!)) }
            .replaceError(with: posts)
            .receive(on: RunLoop.main)
            .sink { newPosts in
                self.posts = newPosts
                self.savePosts()
            }
            .store(in: &subscriptions)
    }
    
    private func toggleLike(_ track: Track) -> () -> () {
        return {
            let shouldUnlike = likes.contains { $0.id == track.id }
            let request: APIRequest = shouldUnlike ? .unlike(track) : .like(track)
            
            // Optimistic update
            if shouldUnlike {
                likes.removeAll { $0.id == track.id }
            } else {
                likes.insert(track, at: 0)
            }
            saveLikes()
            
            SoundCloud.shared.perform(request)
                .receive(on: RunLoop.main)
                .sink(receiveCompletion: { completion in
                    if case let .failure(error) = completion {
                        print("Failed to like track: \(error)")
                        // Roll back on failure
                        if shouldUnlike {
                            if !likes.contains(where: { $0.id == track.id }) {
                                likes.insert(track, at: 0)
                                saveLikes()
                            }
                        } else {
                            likes.removeAll { $0.id == track.id }
                            saveLikes()
                        }
                    }
                }, receiveValue: {
                    reloadLikes()
                })
                .store(in: &subscriptions)
        }
    }
    
    private func toggleLike(_ playlist: AnyPlaylist) -> () -> () {
        return {
            let shouldUnlike = playlists.contains { $0.id == playlist.id }
            let request: APIRequest = shouldUnlike ? .unlike(playlist) : .like(playlist)
            
            if shouldUnlike {
                playlists.removeAll { $0.id == playlist.id }
            } else {
                playlists.insert(playlist, at: 0)
            }
            savePlaylists()
            
            SoundCloud.shared.perform(request)
                .receive(on: RunLoop.main)
                .sink(receiveCompletion: { completion in
                    if case let .failure(error) = completion {
                        print("Failed to like playlist: \(error)")
                        if shouldUnlike {
                            if !playlists.contains(where: { $0.id == playlist.id }) {
                                playlists.insert(playlist, at: 0)
                                savePlaylists()
                            }
                        } else {
                            playlists.removeAll { $0.id == playlist.id }
                            savePlaylists()
                        }
                    }
                }, receiveValue: {
                    reloadLibrary()
                })
                .store(in: &subscriptions)
        }
    }
    
    private func toggleRepost(_ track: Track) -> () -> () {
        return {
            let shouldDeleteRepost = posts.contains { $0.isRepost && $0.isTrack && $0.tracks.first?.id == track.id }
            let request: APIRequest = shouldDeleteRepost ? .unrepost(track) : .repost(track)
            
            // Optimistic update
            if shouldDeleteRepost {
                posts.removeAll { $0.isRepost && $0.isTrack && $0.tracks.first?.id == track.id }
            } else if let user = SoundCloud.shared.user {
                let newPost = Post(id: UUID().uuidString, date: Date(), caption: nil, kind: .trackRepost(track), user: user)
                posts.insert(newPost, at: 0)
            }
            savePosts()
            
            SoundCloud.shared.perform(request)
                .receive(on: RunLoop.main)
                .sink(receiveCompletion: { completion in
                    if case let .failure(error) = completion {
                        print("Failed to repost track: \(error)")
                        // Rollback on failure
                        if shouldDeleteRepost {
                            if let user = SoundCloud.shared.user, !posts.contains(where: { $0.tracks.first?.id == track.id }) {
                                let restored = Post(id: UUID().uuidString, date: Date(), caption: nil, kind: .trackRepost(track), user: user)
                                posts.insert(restored, at: 0)
                                savePosts()
                            }
                        } else {
                            posts.removeAll { $0.tracks.first?.id == track.id }
                            savePosts()
                        }
                    }
                }, receiveValue: {
                    reloadPosts()
                })
                .store(in: &subscriptions)
        }
    }
    
    private func toggleRepost(_ playlist: UserPlaylist) -> () -> () {
        return {
            let shouldDeleteRepost = posts.contains { $0.isRepost && !$0.isTrack && $0.playlist?.id == playlist.id }
            let request: APIRequest = shouldDeleteRepost ? .unrepost(playlist) : .repost(playlist)
            
            if shouldDeleteRepost {
                posts.removeAll { $0.isRepost && !$0.isTrack && $0.playlist?.id == playlist.id }
            } else if let user = SoundCloud.shared.user {
                let newPost = Post(id: UUID().uuidString, date: Date(), caption: nil, kind: .playlistRepost(playlist), user: user)
                posts.insert(newPost, at: 0)
            }
            savePosts()
            
            SoundCloud.shared.perform(request)
                .receive(on: RunLoop.main)
                .sink(receiveCompletion: { completion in
                    if case let .failure(error) = completion {
                        print("Failed to repost playlist: \(error)")
                        reloadPosts()
                    }
                }, receiveValue: {
                    reloadPosts()
                })
                .store(in: &subscriptions)
        }
    }
    
    private func deletePlaylistAction(_ playlist: UserPlaylist) {
        playlists.removeAll { $0.id == playlist.id }
        savePlaylists()
        SoundCloud.shared.perform(.deletePlaylist(id: playlist.id))
            .receive(on: RunLoop.main)
            .sink(receiveCompletion: { completion in
                if case let .failure(error) = completion {
                    print("Failed to delete playlist: \(error)")
                    self.reloadLibrary()
                }
            }, receiveValue: {
                self.reloadLibrary()
            })
            .store(in: &subscriptions)
    }
    
    private func saveCreatedPlaylistAction(_ playlist: UserPlaylist) {
        if !playlists.contains(where: { $0.id == playlist.id }) {
            playlists.insert(.user(playlist), at: 0)
            savePlaylists()
        }
    }
    
    private func updateUserPlaylistAction(_ playlist: UserPlaylist) {
        if let index = playlists.firstIndex(where: { $0.id == playlist.id }) {
            playlists[index] = .user(playlist)
            savePlaylists()
        }
    }
}
