//
//  UserAliasService.swift
//  Nuage
//
//  Created on 04.10.2026.
//

import Foundation
import Combine
import AppKit
import SoundCloud

@MainActor
public final class UserAliasService: ObservableObject {
    
    public static let shared = UserAliasService()
    
    private let storageKey = "user_voice_aliases_map"
    
    @Published public private(set) var aliases: [String: String] = [:]
    
    private init() {
        if let saved = UserDefaults.standard.dictionary(forKey: storageKey) as? [String: String] {
            self.aliases = saved
        }
    }
    
    public func alias(for userId: String) -> String? {
        return aliases[userId]
    }
    
    public func setAlias(_ alias: String?, for userId: String) {
        let trimmed = alias?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let trimmed = trimmed, !trimmed.isEmpty {
            aliases[userId] = trimmed
        } else {
            aliases.removeValue(forKey: userId)
        }
        UserDefaults.standard.set(aliases, forKey: storageKey)
    }
    
    /// Normalizes a Russian or English word to its root stem to handle grammatical cases (e.g. "Саша", "Саше", "Сашей", "Сашу" -> "саш")
    public static func stem(_ word: String) -> String {
        let clean = word.lowercased().trimmingCharacters(in: .punctuationCharacters.union(.whitespacesAndNewlines))
        guard clean.count >= 3 else { return clean }
        
        let endings = ["ому", "ему", "ого", "его", "ыми", "ими", "оми", "еми", "ой", "ей", "ом", "ем", "ам", "ям", "ах", "ях", "ых", "их", "ую", "юю", "а", "я", "у", "ю", "е", "и", "ы", "о", "ь"]
        for ending in endings {
            if clean.hasSuffix(ending) && clean.count - ending.count >= 2 {
                return String(clean.dropLast(ending.count))
            }
        }
        return clean
    }
    
    /// Finds a conversation and matched display name from a spoken query phrase
    public func matchConversation(for query: String, in conversations: [Conversation]) -> (conversation: Conversation, user: User, matchedName: String)? {
        let rawQuery = query.lowercased().trimmingCharacters(in: .punctuationCharacters.union(.whitespacesAndNewlines))
        guard !rawQuery.isEmpty else { return nil }
        
        let queryStem = Self.stem(rawQuery)
        let currentUserId = SoundCloud.shared.user?.id
        
        // 1. First priority: match against user-defined aliases
        for conv in conversations {
            guard let partner = conv.otherUser(currentUserId: currentUserId) else { continue }
            if let customAlias = aliases[partner.id] {
                let aliasLower = customAlias.lowercased()
                let aliasStem = Self.stem(aliasLower)
                
                // Exact match, substring match, or stem match
                if rawQuery == aliasLower ||
                   rawQuery.contains(aliasLower) ||
                   aliasLower.contains(rawQuery) ||
                   queryStem == aliasStem ||
                   rawQuery.contains(aliasStem) {
                    return (conv, partner, customAlias)
                }
            }
        }
        
        // 2. Second priority: match against partner's username
        for conv in conversations {
            guard let partner = conv.otherUser(currentUserId: currentUserId) else { continue }
            let usernameLower = partner.username.lowercased()
            let usernameStem = Self.stem(usernameLower)
            
            if rawQuery == usernameLower ||
               usernameLower.contains(rawQuery) ||
               rawQuery.contains(usernameStem) ||
               queryStem == usernameStem {
                let displayName = aliases[partner.id] ?? partner.username
                return (conv, partner, displayName)
            }
        }
        
        return nil
    }
}
