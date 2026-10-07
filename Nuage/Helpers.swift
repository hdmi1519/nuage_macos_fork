//
//  Helpers.swift
//  Nuage
//
//  Created by Laurin Brandner on 22.12.19.
//  Copyright © 2019 Laurin Brandner. All rights reserved.
//

import Foundation
import SwiftUI
import Combine
import URLImage
import SoundCloud
import ObjectiveC

private var durationFormatter: DateComponentsFormatter = {
    let formatter = DateComponentsFormatter()
    formatter.unitsStyle = .positional
    formatter.allowedUnits = [.hour, .minute, .second]
    formatter.zeroFormattingBehavior = .pad
    
    return formatter
}()

func format<Time: BinaryFloatingPoint>(time: Time) -> String {
    let totalSeconds = max(0, Int(time.rounded()))
    let hours = totalSeconds / 3600
    let minutes = (totalSeconds % 3600) / 60
    let seconds = totalSeconds % 60
    if hours > 0 {
        return String(format: "%d:%02d:%02d", hours, minutes, seconds)
    } else {
        return String(format: "%d:%02d", minutes, seconds)
    }
}

private var countFormatter: NumberFormatter = {
    let formatter = NumberFormatter()
    formatter.numberStyle = .decimal
    formatter.maximumFractionDigits = 1
    formatter.usesGroupingSeparator = false

    return formatter
}()

func format(count: Int) -> String {
    if count < 1_000 { return String(count) }

    let value = Double(count)
    let (scaled, suffix): (Double, String)
    switch value {
    case 1_000_000_000...: (scaled, suffix) = (value / 1_000_000_000, "B")
    case 1_000_000...:     (scaled, suffix) = (value / 1_000_000, "M")
    default:               (scaled, suffix) = (value / 1_000, "K")
    }

    return (countFormatter.string(from: NSNumber(value: scaled)) ?? String(count)) + suffix
}

extension AnyCancellable {
    
    func store<T: Hashable>(in dictionary: inout Dictionary<T, AnyCancellable>, key: T) {
        dictionary[key] = self
    }
    
}

protocol Filterable {
    
    func contains(_ text: String) -> Bool
    
}

extension User: Filterable {
    
    func contains(_ text: String) -> Bool {
        return username.containsCaseInsensitive(text) || name.containsCaseInsensitive(text)
    }
    
}

extension Track: Filterable {
    
    func contains(_ text: String) -> Bool {
        return title.containsCaseInsensitive(text) || (description?.containsCaseInsensitive(text) ?? false)
    }
    
}

extension Post: Filterable {
    
    func contains(_ text: String) -> Bool {
        return user.contains(text) || tracks.contains { $0.contains(text) }
    }
    
}

extension UserPlaylist: Filterable {
    
    func contains(_ text: String) -> Bool {
        let contained = title.containsCaseInsensitive(text) || (description?.containsCaseInsensitive(text) ?? false)
        if let tracks = tracks {
            return contained || tracks.contains { $0.contains(text) }
        }
        return contained
        
    }
}

extension SystemPlaylist: Filterable {
    
    func contains(_ text: String) -> Bool {
        let contained = title.containsCaseInsensitive(text) || (description?.containsCaseInsensitive(text) ?? false)
        if let tracks = tracks {
            return contained || tracks.contains { $0.contains(text) }
        }
        return contained
        
    }
}

extension Like: Filterable where T: Filterable {
    
    func contains(_ text: String) -> Bool {
        return item.contains(text)
    }
    
}

extension Some: Filterable {
    
    func contains(_ text: String) -> Bool {
        switch self {
        case .track(let track): return track.contains(text)
        case .userPlaylist(let playlist): return playlist.contains(text)
        case .systemPlaylist(let playlist): return playlist.contains(text)
        case .user(let user): return user.contains(text)
        }
    }
    
}

extension Comment: Filterable {
    
    func contains(_ text: String) -> Bool {
        return body.contains(text) || user.contains(text)
    }
    
}

extension HistoryItem: Filterable {
    
    func contains(_ text: String) -> Bool {
        return track.contains(text)
    }
    
}

extension Recommendation: Filterable {
    
    func contains(_ text: String) -> Bool {
        return user.contains(text)
    }
    
}

extension String {
    
    fileprivate func containsCaseInsensitive(_ text: String) -> Bool {
        return range(of: text, options: .caseInsensitive) != nil
    }
    
}

protocol DateComparable: Comparable {
    
    var date: Date { get }
    
}

extension DateComparable {
    
    public static func < (lhs: Self, rhs: Self) -> Bool {
        return lhs.date < rhs.date
    }
    
}

extension HistoryItem: DateComparable {}
extension Post: DateComparable {}
extension Track: DateComparable {}
extension UserPlaylist: DateComparable {}

@ViewBuilder func RemoteImage(url: URL?, cornerRadius: CGFloat) -> some View {
    let placeholder = Rectangle()
        .foregroundColor(Color(NSColor.underPageBackgroundColor))
        .cornerRadius(cornerRadius)
    
    // Select appropriate resolution: 300x300 for list thumbnails (super crisp, ultra-fast decode), 500x500 for large detail/fullscreen
    let targetSize = cornerRadius <= 10 ? "-t300x300." : "-t500x500."
    let resolvedURL: URL? = {
        guard let url = url else { return nil }
        var s = url.absoluteString
        for small in ["-t120x120.", "-t200x200.", "-t300x300.", "-t500x500.", "-t67x67.", "-t50x50."] {
            if s.contains(small) {
                s = s.replacingOccurrences(of: small, with: targetSize)
                return URL(string: s)
            }
        }
        if s.contains("-large.") {
            s = s.replacingOccurrences(of: "-large.", with: targetSize)
            return URL(string: s) ?? url
        }
        return url
    }()
    
    if let url = resolvedURL {
        URLImage(url: url,
                 empty: { placeholder },
                 inProgress: { _ in placeholder },
                 failure: { _, _ in placeholder },
                 content: { image in
            image
                .resizable()
                .aspectRatio(contentMode: .fill)
                .cornerRadius(cornerRadius)
                .clipped()
        })
        .cornerRadius(cornerRadius)
        .clipped()
        .id(url)
    }
    else {
        placeholder
    }
}

extension Color {
    
    init(hex: UInt, alpha: Double = 1) {
        let red = Double((hex >> 16) & 0xff) / 255
        let green = Double((hex >> 08) & 0xff) / 255
        let blue = Double((hex >> 00) & 0xff) / 255
        self.init(.sRGB, red: red, green: green, blue: blue, opacity: alpha)
    }
    
    static let appBackground = Color(nsColor: NSColor(name: nil, dynamicProvider: { appearance in
        let match = appearance.bestMatch(from: [.aqua, .darkAqua])
        if match == .darkAqua {
            return NSColor(calibratedWhite: 0.12, alpha: 1.0)
        } else {
            return NSColor(calibratedWhite: 0.97, alpha: 1.0)
        }
    }))
    
    static let secondaryAppBackground = Color(nsColor: NSColor(name: nil, dynamicProvider: { appearance in
        let match = appearance.bestMatch(from: [.aqua, .darkAqua])
        if match == .darkAqua {
            return NSColor(calibratedWhite: 0.16, alpha: 1.0)
        } else {
            return NSColor(calibratedWhite: 1.0, alpha: 1.0)
        }
    }))
    
}

extension View {
    
    @ViewBuilder func `if`<Content: View>(_ condition: Bool, transform: (Self) -> Content) -> some View {
        if condition {
            transform(self)
        } else {
            self
        }
    }
    
}

extension String {
    
    func withAttributedLinks(useAppURLScheme: Bool = true) -> AttributedString {
        var linkRanges = [(NSRange, URL)]()
        var handleRanges = [(NSRange, URL)]()
        do {
            let detector = try NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
            detector.enumerateMatches(in: self, range: NSMakeRange(0, count)) { result, _, _ in
                if let match = result,
                    var url = match.url {
                    if url.absoluteString.contains("soundcloud") && useAppURLScheme {
                        var components = URLComponents(url: url, resolvingAgainstBaseURL: true)
                        components?.scheme = "nuage"
                        url = components?.url ?? url
                    }
                    linkRanges.append((match.range, url))
                }
            }
            
            let handle = /@([a-zA-Z0-9_-]{3,})/
            for match in self.matches(of: handle) {
                let range = NSRange(match.range, in: self)
                let username = match.output.1
                let scheme = useAppURLScheme ? "nuage" : "https"
                let url = URL(string: "\(scheme)://soundcloud.com/\(username)")!

                handleRanges.append((range, url))
            }
        }
        catch {
            print("Failed to parse text: \(error)")
        }
        
        let attributedText = NSMutableAttributedString(string: self)
        for (range, url) in (linkRanges + handleRanges)  {
            let attributes: [NSAttributedString.Key: Any] = [
                .link: url,
                .foregroundColor: NSColor.controlAccentColor,
            ]
            
            attributedText.addAttributes(attributes, range: range)
        }
        
        return AttributedString(attributedText)
    }

}

private var bundleKey: UInt8 = 0

final class LocalizedBundle: Bundle, @unchecked Sendable {
    override func localizedString(forKey key: String, value: String?, table tableName: String?) -> String {
        if let bundle = objc_getAssociatedObject(self, &bundleKey) as? Bundle {
            let str = bundle.localizedString(forKey: key, value: value, table: tableName)
            if str != key {
                return str
            }
        }
        return super.localizedString(forKey: key, value: value, table: tableName)
    }
}

extension Bundle {
    private static let swizzleOnce: Void = {
        object_setClass(Bundle.main, LocalizedBundle.self)
    }()
    
    static func setLanguage(_ language: String) {
        _ = swizzleOnce
        let bundle: Bundle?
        if let path = Bundle.main.path(forResource: language, ofType: "lproj") {
            bundle = Bundle(path: path)
        } else {
            bundle = nil
        }
        objc_setAssociatedObject(Bundle.main, &bundleKey, bundle, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
    }
}

enum MenuLocalizer {
    
    private static var isObserving = false
    
    private static let enToRu: [String: String] = [
        "File": "Файл",
        "Edit": "Правка",
        "View": "Вид",
        "Language": "Язык",
        "Playback": "Воспроизведение",
        "Window": "Окно",
        "Help": "Справка",
        "Services": "Службы",
        "Preferences…": "Настройки…",
        "Preferences...": "Настройки…",
        "Settings…": "Настройки…",
        "Settings...": "Настройки…",
        "Close Window": "Закрыть окно",
        "Close": "Закрыть",
        "Minimize": "Свернуть",
        "Zoom": "Изменить масштаб",
        "Bring All to Front": "Все окна — на передний план",
        "Undo": "Отменить",
        "Redo": "Повторить",
        "Cut": "Вырезать",
        "Copy": "Скопировать",
        "Paste": "Вставить",
        "Paste and Match Style": "Вставить и согласовать стиль",
        "Delete": "Удалить",
        "Select All": "Выбрать все",
        "Filter": "Фильтр",
        "Search": "Поиск",
        "Find": "Поиск",
        "Find…": "Поиск…",
        "Find...": "Поиск…",
        "Find and Replace…": "Найти и заменить…",
        "Find and Replace...": "Найти и заменить…",
        "Find Next": "Найти следующее",
        "Find Previous": "Найти предыдущее",
        "Use Selection for Find": "Использовать выбранное для поиска",
        "Jump to Selection": "Перейти к выбранному",
        "Spelling and Grammar": "Правописание и грамматика",
        "Show Spelling and Grammar": "Показать правописание и грамматику",
        "Check Document Now": "Проверить документ сейчас",
        "Check Spelling While Typing": "Проверять правописание при вводе",
        "Check Grammar With Spelling": "Проверять грамматику вместе с правописанием",
        "Correct Spelling Automatically": "Автоматически исправлять ошибки",
        "Substitutions": "Автозамена",
        "Show Substitutions": "Показать автозамену",
        "Smart Copy/Paste": "Смарт-копирование/вставка",
        "Smart Quotes": "Смарт-кавычки",
        "Smart Dashes": "Смарт-тире",
        "Smart Links": "Смарт-ссылки",
        "Text Replacement": "Замена текста",
        "Transformations": "Преобразования",
        "Make Upper Case": "Все прописные",
        "Make Lower Case": "Все строчные",
        "Capitalize": "С прописной буквы",
        "Speech": "Проговаривание текста",
        "Start Speaking": "Начать проговаривание",
        "Stop Speaking": "Остановить проговаривание",
        "Playlists": "Плейлисты",
        "Show Created": "Показывать созданные",
        "Show Liked": "Показывать понравившиеся",
        "Show Created Playlists": "Показывать созданные",
        "Show Liked Playlists": "Показывать понравившиеся",
        "Play": "Играть",
        "Pause": "Пауза",
        "Shuffle": "Перемешать",
        "Repeat": "Повтор",
        "Volume Up": "Увеличить громкость",
        "Volume Down": "Уменьшить громкость",
        "Next": "Следующий трек",
        "Previous": "Предыдущий трек",
        "Next Track": "Следующий трек",
        "Previous Track": "Предыдущий трек",
        "Seek Forward": "Перемотка вперед",
        "Seek Backward": "Перемотка назад",
        "Show Tab Bar": "Показать панель вкладок",
        "Hide Tab Bar": "Скрыть панель вкладок",
        "Show All Tabs": "Показать все вкладки",
        "Enter Full Screen": "Перейти в полноэкранный режим",
        "Exit Full Screen": "Выйти из полноэкранного режима",
        "Toggle Full Screen": "Полноэкранный режим",
        "Hide Sidebar": "Скрыть боковое меню",
        "Show Sidebar": "Показать боковое меню",
        "Toggle Sidebar": "Боковое меню",
        "Show Comments": "Показывать комментарии",
        "Equalizer": "Эквалайзер",
        "Settings": "Настройки",
        "Discord Rich Presence": "Discord Rich Presence"
    ]
    
    private static let ruToEn: [String: String] = {
        var reversed: [String: String] = [:]
        for (k, v) in enToRu {
            if reversed[v] == nil {
                reversed[v] = k
            }
        }
        reversed["Вид"] = "View"
        reversed["Настройки"] = "Settings"
        reversed["Discord Rich Presence"] = "Discord Rich Presence"
        reversed["Показывать комментарии"] = "Show Comments"
        reversed["Эквалайзер"] = "Equalizer"
        reversed["Показывать созданные"] = "Show Created"
        reversed["Показывать понравившиеся"] = "Show Liked"
        reversed["Следующий трек"] = "Next"
        reversed["Предыдущий трек"] = "Previous"
        reversed["Настройки…"] = "Settings…"
        reversed["Поиск…"] = "Find…"
        reversed["Найти и заменить…"] = "Find and Replace…"
        return reversed
    }()
    
    static func startObserving() {
        guard !isObserving else { return }
        isObserving = true
        let updateHandler: (Notification) -> Void = { _ in
            let lang = UserDefaults.standard.string(forKey: "appLanguage") ?? "en"
            updateMenu(to: lang)
        }
        NotificationCenter.default.addObserver(forName: NSMenu.didBeginTrackingNotification, object: nil, queue: .main, using: updateHandler)
        NotificationCenter.default.addObserver(forName: NSMenu.didEndTrackingNotification, object: nil, queue: .main, using: updateHandler)
        NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main, using: updateHandler)
        NotificationCenter.default.addObserver(forName: NSWindow.didBecomeKeyNotification, object: nil, queue: .main, using: updateHandler)
    }
    
    static func updateMenu(to language: String) {
        guard let mainMenu = NSApp.mainMenu else { return }
        localize(menu: mainMenu, language: language)
        filterMenu(mainMenu)
        mainMenu.update()
    }
    
    private static func filterMenu(_ mainMenu: NSMenu) {
        // Keep the application menu (index 0).
        // Keep our custom "View" / "Вид" menu, "Language" / "Язык", and "Playback" / "Воспроизведение".
        // Hide all other top-level menus (File, Edit, native View, Window, Help, etc.).
        for (index, item) in mainMenu.items.enumerated() {
            if index == 0 {
                item.isHidden = false
                continue
            }
            
            let titles = [item.title, item.submenu?.title ?? ""].map {
                $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            }
            
            let isAllowed: Bool = {
                // Allow our custom View menu (only if it contains our comments toggle or equalizer, NOT native fullscreen/toolbar)
                if titles.contains(where: { $0 == "view" || $0 == "вид" }) {
                    if let submenu = item.submenu {
                        let subTitles = submenu.items.map { $0.title.lowercased() }
                        let isCustom = subTitles.contains { sub in
                            sub.contains("комментар") || sub.contains("comment") || sub.contains("эквалайзер") || sub.contains("equalizer")
                        }
                        return isCustom
                    }
                    return false
                }
                
                // Allow our custom Settings menu (only if it contains discord rpc toggle)
                if titles.contains(where: { $0 == "settings" || $0 == "настройки" }) {
                    if let submenu = item.submenu {
                        let subTitles = submenu.items.map { $0.title.lowercased() }
                        let isCustom = subTitles.contains { sub in
                            sub.contains("discord") || sub.contains("пресенс") || sub.contains("presence")
                        }
                        return isCustom
                    }
                    return false
                }
                
                return titles.contains { t in
                    t == "language" || t == "язык" || t == "playback" || t == "воспроизведение"
                }
            }()
            
            item.isHidden = !isAllowed
        }
    }
    
    private static func translateTitle(_ title: String, to language: String, appName: String) -> String? {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        
        if language == "ru" {
            if let direct = enToRu[trimmed] {
                return direct
            }
            if ruToEn[trimmed] != nil {
                return trimmed
            }
            if trimmed.hasPrefix("About ") {
                return "О программе \(appName)"
            } else if trimmed.hasPrefix("Hide ") && trimmed != "Hide Others" {
                return "Скрыть \(appName)"
            } else if trimmed == "Hide Others" {
                return "Скрыть остальные"
            } else if trimmed == "Show All" {
                return "Показать все"
            } else if trimmed.hasPrefix("Quit ") {
                return "Завершить \(appName)"
            } else if trimmed.hasSuffix(" Help") || trimmed.hasPrefix("Help ") {
                return "Справка \(appName)"
            }
        } else {
            if let direct = ruToEn[trimmed] {
                return direct
            }
            if enToRu[trimmed] != nil {
                return trimmed
            }
            if trimmed.hasPrefix("О программе ") {
                return "About \(appName)"
            } else if trimmed.hasPrefix("Скрыть ") && trimmed != "Скрыть остальные" {
                return "Hide \(appName)"
            } else if trimmed == "Скрыть остальные" {
                return "Hide Others"
            } else if trimmed == "Показать все" {
                return "Show All"
            } else if trimmed.hasPrefix("Завершить ") {
                return "Quit \(appName)"
            } else if trimmed.hasPrefix("Справка ") {
                return "\(appName) Help"
            }
        }
        return nil
    }
    
    private static func localize(menu: NSMenu, language: String) {
        let appName = Bundle.main.infoDictionary?["CFBundleName"] as? String ?? "Nuage"
        
        for item in menu.items {
            let candidate = !item.title.isEmpty ? item.title : (item.submenu?.title ?? "")
            if let translated = translateTitle(candidate, to: language, appName: appName) {
                item.title = translated
                item.submenu?.title = translated
            } else if let subTitle = item.submenu?.title, !subTitle.isEmpty,
                      let subTranslated = translateTitle(subTitle, to: language, appName: appName) {
                item.title = subTranslated
                item.submenu?.title = subTranslated
            }
            
            if let submenu = item.submenu {
                if let subTranslated = translateTitle(submenu.title, to: language, appName: appName) {
                    submenu.title = subTranslated
                    item.title = subTranslated
                }
                localize(menu: submenu, language: language)
                submenu.update()
            }
        }
        menu.update()
    }
}

extension Notification.Name {
    static let openTrackLyrics = Notification.Name("openTrackLyrics")
    static let openTrackPoster = Notification.Name("openTrackPoster")
    static let openFullscreenNowPlaying = Notification.Name("openFullscreenNowPlaying")
    static let shareTrackToFriend = Notification.Name("shareTrackToFriend")
    static let sharePlaylistToFriend = Notification.Name("sharePlaylistToFriend")
    static let voiceControlLikeTrack = Notification.Name("voiceControlLikeTrack")
    static let voiceControlUnlikeTrack = Notification.Name("voiceControlUnlikeTrack")
    static let voiceControlPlayWave = Notification.Name("voiceControlPlayWave")
    static let voiceControlRefreshWave = Notification.Name("voiceControlRefreshWave")
    static let voiceControlPlayLikes = Notification.Name("voiceControlPlayLikes")
    static let voiceControlRepostTrack = Notification.Name("voiceControlRepostTrack")
    static let voiceControlUnrepostTrack = Notification.Name("voiceControlUnrepostTrack")
    static let voiceControlPlayReposts = Notification.Name("voiceControlPlayReposts")
    static let voiceControlPlayStream = Notification.Name("voiceControlPlayStream")
    static let voiceControlShareTrack = Notification.Name("voiceControlShareTrack")
    static let voiceControlPostComment = Notification.Name("voiceControlPostComment")
    static let voiceControlSearchAndPlay = Notification.Name("voiceControlSearchAndPlay")
    static let openVoiceControlSettings = Notification.Name("openVoiceControlSettings")
}

enum ToolbarMenuDisabler {
    private static var hasSwizzled = false
    private typealias PopUpContextMenuFunc = @convention(c) (AnyClass, Selector, NSMenu, NSEvent, NSView) -> Void
    private typealias PopUpInstFunc = @convention(c) (NSMenu, Selector, NSMenuItem?, NSPoint, NSView?) -> Bool
    
    private static var originalPopUpContextMenuIMP: IMP?
    private static var originalPopUpIMP: IMP?
    
    static func disable() {
        guard !hasSwizzled else { return }
        hasSwizzled = true
        
        // 1. Intercept NSMenu.popUpContextMenu(_:with:for:) to block ONLY toolbar customization menus
        if let classMethod = class_getClassMethod(NSMenu.self, #selector(NSMenu.popUpContextMenu(_:with:for:))) {
            let block: @convention(block) (AnyClass, NSMenu, NSEvent, NSView) -> Void = { cls, menu, event, view in
                if isToolbarContextMenu(menu) {
                    return
                }
                let orig = unsafeBitCast(originalPopUpContextMenuIMP, to: PopUpContextMenuFunc.self)
                orig(cls, #selector(NSMenu.popUpContextMenu(_:with:for:)), menu, event, view)
            }
            originalPopUpContextMenuIMP = method_setImplementation(classMethod, imp_implementationWithBlock(block))
        }
        
        // 2. Intercept NSMenu.popUp(positioning:at:in:) to block ONLY toolbar customization menus
        if let instMethod = class_getInstanceMethod(NSMenu.self, #selector(NSMenu.popUp(positioning:at:in:))) {
            let block: @convention(block) (NSMenu, NSMenuItem?, NSPoint, NSView?) -> Bool = { menu, item, point, view in
                if isToolbarContextMenu(menu) {
                    return false
                }
                let orig = unsafeBitCast(originalPopUpIMP, to: PopUpInstFunc.self)
                return orig(menu, #selector(NSMenu.popUp(positioning:at:in:)), item, point, view)
            }
            originalPopUpIMP = method_setImplementation(instMethod, imp_implementationWithBlock(block))
        }
    }
    
    private static func isToolbarContextMenu(_ menu: NSMenu) -> Bool {
        return menu.items.contains { item in
            guard let action = item.action else { return false }
            let name = NSStringFromSelector(action)
            return name.contains("Toolbar") || name.contains("changeToolbarDisplayMode") || name.contains("runToolbarCustomizationPalette")
        }
    }
}

func cleanSoundCloudURL(_ url: URL) -> URL {
    guard var components = URLComponents(url: url, resolvingAgainstBaseURL: true) else { return url }
    if components.scheme == nil || components.scheme?.isEmpty == true {
        components.scheme = "https"
    }
    // Remove analytics, tracking and share query parameters that interfere with resolution
    components.queryItems = nil
    components.fragment = nil
    return components.url ?? url
}

func detectSoundCloudURL(from text: String) -> URL? {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return nil }
    
    // Check if it already has scheme (http / https)
    if let url = URL(string: trimmed), let host = url.host?.lowercased() {
        if host.contains("soundcloud.com") {
            return cleanSoundCloudURL(url)
        }
    }
    
    // Check if user pasted without scheme: e.g. "soundcloud.com/...", "m.soundcloud.com/...", "on.soundcloud.com/..."
    let lower = trimmed.lowercased()
    if lower.hasPrefix("soundcloud.com/") || lower.hasPrefix("www.soundcloud.com/") || lower.hasPrefix("m.soundcloud.com/") || lower.hasPrefix("on.soundcloud.com/") {
        if let url = URL(string: "https://" + trimmed) {
            return cleanSoundCloudURL(url)
        }
    }
    
    // Check if text starts with soundcloud:// custom scheme
    if lower.hasPrefix("soundcloud://") {
        if let url = URL(string: trimmed) {
            return cleanSoundCloudURL(url)
        }
    }
    
    return nil
}



