//
//  Navigation.swift
//  Nuage
//
//  Created by Laurin Brandner on 28.07.23.
//

import Foundation
import SoundCloud

private let userPlaylistSeparator = "@@USERPLAYLIST@@"
private let systemPlaylistSeparator = "@@SYSTEMPLAYLIST@@"

enum SidebarItem: RawRepresentable {
    case discover
    case stream
    case wave
    case likes
    case reposts
    case history
    case following
    case playlists
    case userPlaylist(String, String)
    case systemPlaylist(String, String)

    init?(rawValue: String) {
        switch rawValue {
        case "discover": self = .discover
        case "stream": self = .stream
        case "wave": self = .wave
        case "likes": self = .likes
        case "reposts": self = .reposts
        case "history": self = .history
        case "following": self = .following
        case "playlists": self = .playlists
        default:
            if rawValue.contains(userPlaylistSeparator) {
                let components = rawValue.split(separator: userPlaylistSeparator)
                guard components.count == 2 else { return nil }
                
                self = .userPlaylist(String(components[0]), String(components[1]))
            }
            else {
                let components = rawValue.split(separator: systemPlaylistSeparator)
                guard components.count == 2 else { return nil }
                
                self = .systemPlaylist(String(components[0]), String(components[1]))
            }
        }
    }
    
    var rawValue: String {
        switch self {
        case .discover: return "discover"
        case .stream: return "stream"
        case .wave: return "wave"
        case .likes: return "likes"
        case .reposts: return "reposts"
        case .history: return "history"
        case .following: return "following"
        case .playlists: return "playlists"
        case .userPlaylist(let name, let id): return name+userPlaylistSeparator+id
        case .systemPlaylist(let name, let id): return name+systemPlaylistSeparator+id
        }
    }
    
    var title: String {
        switch self {
        case .discover: return NSLocalizedString("sidebar.discover", comment: "")
        case .stream: return NSLocalizedString("sidebar.stream", comment: "")
        case .wave: return NSLocalizedString("sidebar.wave", comment: "")
        case .likes: return NSLocalizedString("sidebar.likes", comment: "")
        case .reposts: return NSLocalizedString("sidebar.reposts", comment: "")
        case .history: return NSLocalizedString("sidebar.history", comment: "")
        case .following: return NSLocalizedString("sidebar.following", comment: "")
        case .playlists: return NSLocalizedString("sidebar.playlists", comment: "")
        case .userPlaylist(let name, _): return name
        case .systemPlaylist(let name, _): return name
        }
    }
    
    var imageName: String? {
        switch self {
        case .discover: return "sparkles"
        case .stream: return "bolt.horizontal.fill"
        case .wave: return "dot.radiowaves.left.and.right"
        case .likes: return "heart.fill"
        case .reposts: return "repeat"
        case .history: return "clock.fill"
        case .following: return "person.2.fill"
        case .playlists: return "music.note.list"
        default: return nil
        }
    }
    
}

extension SidebarItem: Hashable {
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(title.hashValue)
        if case .userPlaylist(_, let id) = self {
            hasher.combine(id.hashValue)
        }
        else if case .systemPlaylist(_, let urn) = self {
            hasher.combine(urn.hashValue)
        }
    }
    
}

extension SidebarItem: Identifiable {
    
    var id: String {
        if case .userPlaylist(_, let id) = self {
            return id
        }
        if case .systemPlaylist(_, let urn) = self {
            return urn
        }
        return title
    }
    
}

enum Station: Hashable {
    case track(Track)
    case artist(User)
}
