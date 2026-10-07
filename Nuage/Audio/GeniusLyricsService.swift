//
//  GeniusLyricsService.swift
//  Nuage
//
//  Created on 03.10.2026.
//

import Foundation
import Combine
import SoundCloud

public struct GeniusSongInfo {
    public let title: String
    public let artist: String
    public let lyrics: String
    public let geniusURL: URL?
    public let thumbnailURL: URL?
}

@MainActor
public class GeniusLyricsService: ObservableObject {
    
    public static let shared = GeniusLyricsService()
    
    public struct TranslationResult {
        public let translation: GeniusSongInfo
        public let translationLang: String
        public let originalLang: String
    }
    
    @Published public private(set) var currentTrackID: String?
    @Published public private(set) var lyrics: String?
    @Published public private(set) var songInfo: GeniusSongInfo?
    @Published public private(set) var translatedLyrics: String?
    @Published public private(set) var translatedSongInfo: GeniusSongInfo?
    @Published public private(set) var originalLanguageCode: String = "EN"
    @Published public private(set) var translationLanguageCode: String = "RU"
    @Published public private(set) var isLoading: Bool = false
    @Published public private(set) var isLoadingTranslation: Bool = false
    @Published public private(set) var errorMessage: String?
    
    // Backwards-compatible aliases
    public var russianLyrics: String? { translatedLyrics }
    public var russianSongInfo: GeniusSongInfo? { translatedSongInfo }
    
    private var cache = [String: GeniusSongInfo]()
    private var translationCache = [String: TranslationResult]()
    private var activeTask: Task<Void, Never>?
    private var activeTranslationTask: Task<Void, Never>?
    
    private init() {}
    
    public static func isPredominantlyCyrillic(_ text: String) -> Bool {
        var cyrillicCount = 0
        var latinCount = 0
        for scalar in text.unicodeScalars {
            if (0x0400...0x04FF).contains(scalar.value) {
                cyrillicCount += 1
            } else if (0x0041...0x005A).contains(scalar.value) || (0x0061...0x007A).contains(scalar.value) {
                latinCount += 1
            }
        }
        return cyrillicCount > latinCount && cyrillicCount > 15
    }
    
    public func fetchLyrics(for track: Track) {
        if currentTrackID == track.id && (lyrics != nil || isLoading) {
            return
        }
        
        currentTrackID = track.id
        errorMessage = nil
        
        let (parsedTitle, parsedArtists) = parseTrack(title: track.title, username: track.user.username)
        let primaryArtist = parsedArtists.first ?? track.user.username
        let cacheKey = "\(parsedArtists.joined(separator: "_").lowercased())--\(parsedTitle.lowercased())"
        
        activeTranslationTask?.cancel()
        translatedLyrics = nil
        translatedSongInfo = nil
        isLoadingTranslation = false
        
        if let cached = cache[cacheKey] {
            self.songInfo = cached
            self.lyrics = cached.lyrics
            self.isLoading = false
            
            if let cachedTrans = translationCache[cacheKey] {
                self.translatedSongInfo = cachedTrans.translation
                self.translatedLyrics = cachedTrans.translation.lyrics
                self.translationLanguageCode = cachedTrans.translationLang
                self.originalLanguageCode = cachedTrans.originalLang
            } else {
                fetchTranslation(artists: parsedArtists, title: parsedTitle, originalLyrics: cached.lyrics, cacheKey: cacheKey)
            }
            return
        }
        
        activeTask?.cancel()
        isLoading = true
        lyrics = nil
        songInfo = nil
        
        activeTask = Task {
            let info = await searchGenius(artists: parsedArtists, title: parsedTitle)
            guard !Task.isCancelled else { return }
            
            if let info = info {
                self.cache[cacheKey] = info
                self.songInfo = info
                self.lyrics = info.lyrics
                self.isLoading = false
                
                self.fetchTranslation(artists: parsedArtists, title: parsedTitle, originalLyrics: info.lyrics, cacheKey: cacheKey)
            } else {
                // Try fallback to lyrics.ovh
                let fallback = await searchLyricsOvh(artist: primaryArtist, title: parsedTitle)
                guard !Task.isCancelled else { return }
                
                if let fallbackText = fallback {
                    let fallbackInfo = GeniusSongInfo(
                        title: parsedTitle,
                        artist: primaryArtist,
                        lyrics: fallbackText,
                        geniusURL: URL(string: "https://genius.com/search?q=\(primaryArtist)+\(parsedTitle)".addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""),
                        thumbnailURL: nil
                    )
                    self.cache[cacheKey] = fallbackInfo
                    self.songInfo = fallbackInfo
                    self.lyrics = fallbackText
                    self.originalLanguageCode = Self.isPredominantlyCyrillic(fallbackText) ? "RU" : "EN"
                    self.translationLanguageCode = self.originalLanguageCode == "RU" ? "EN" : "RU"
                } else {
                    self.errorMessage = "Текст не найден"
                }
                self.isLoading = false
            }
        }
    }
    
    private func fetchTranslation(artists: [String], title: String, originalLyrics: String, cacheKey: String) {
        activeTranslationTask?.cancel()
        activeTranslationTask = Task {
            isLoadingTranslation = true
            let isCyrillic = Self.isPredominantlyCyrillic(originalLyrics)
            let result = await searchGeniusTranslation(artists: artists, title: title, isOriginalCyrillic: isCyrillic)
            guard !Task.isCancelled else { return }
            
            if let (transInfo, transLang, origLang) = result {
                let cacheEntry = TranslationResult(translation: transInfo, translationLang: transLang, originalLang: origLang)
                self.translationCache[cacheKey] = cacheEntry
                self.translatedSongInfo = transInfo
                self.translatedLyrics = transInfo.lyrics
                self.translationLanguageCode = transLang
                self.originalLanguageCode = origLang
            }
            self.isLoadingTranslation = false
        }
    }
    
    // MARK: - Genius Search & Scrape
    
    private struct GeniusHitCandidate {
        let title: String
        let artist: String
        let path: String
        let thumbnailURL: URL?
        let artistMatches: Bool
    }
    
    private func searchGenius(artists: [String], title: String) async -> GeniusSongInfo? {
        var queries = [String]()
        
        // Multi-artist queries: e.g. "Kai Angel 9mice SPIT", "Kai Angel & 9mice SPIT"
        let artistPairs = artists.filter { !$0.contains(" ") || $0.components(separatedBy: " ").count <= 3 }
        if artistPairs.count >= 2 {
            queries.append("\(artistPairs[0]) \(artistPairs[1]) \(title)")
        }
        for artist in artists {
            let q = "\(artist) \(title)".trimmingCharacters(in: .whitespaces)
            if !queries.contains(q) {
                queries.append(q)
            }
        }
        if !queries.contains(title) {
            queries.append(title)
        }
        
        for q in queries {
            guard let encodedQuery = q.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
                continue
            }
            
            let endpoints = [
                "https://genius.com/api/search/multi?q=\(encodedQuery)",
                "https://genius.com/api/search/song?q=\(encodedQuery)"
            ]
            
            for endpoint in endpoints {
                guard let searchURL = URL(string: endpoint) else { continue }
                
                var request = URLRequest(url: searchURL)
                request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36", forHTTPHeaderField: "User-Agent")
                request.setValue("application/json", forHTTPHeaderField: "Accept")
                
                do {
                    let (data, response) = try await URLSession.shared.data(for: request)
                    guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { continue }
                    
                    guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                          let responseDict = json["response"] as? [String: Any],
                          let sections = responseDict["sections"] as? [[String: Any]] else {
                        continue
                    }
                    
                    var candidates = [GeniusHitCandidate]()
                    
                    for section in sections {
                        guard let hits = section["hits"] as? [[String: Any]] else { continue }
                        for hit in hits {
                            guard let result = hit["result"] as? [String: Any],
                                  let songPath = result["path"] as? String else { continue }
                            
                            let songTitle = result["title"] as? String ?? ""
                            let primaryArtist = (result["primary_artist"] as? [String: Any])?["name"] as? String ?? ""
                            let artistNames = result["artist_names"] as? String ?? ""
                            
                            // STRICT TITLE VALIDATION: Prevents returning unrelated tracks / interludes
                            guard isTitleMatch(searched: title, candidate: songTitle) else {
                                continue
                            }
                            
                            // Check if this is a translation or meta page
                            let isTranslationPage = songTitle.localizedCaseInsensitiveContains("translation") ||
                                                   songTitle.localizedCaseInsensitiveContains("перевод") ||
                                                   artistNames.localizedCaseInsensitiveContains("Translations")
                            if isTranslationPage {
                                continue
                            }
                            
                            let thumbStr = result["song_art_image_thumbnail_url"] as? String
                            let thumbURL = thumbStr != nil ? URL(string: thumbStr!) : nil
                            
                            let artistMatches = isArtistMatch(searchedArtists: artists, candidateArtist: primaryArtist) ||
                                                isArtistMatch(searchedArtists: artists, candidateArtist: artistNames)
                            
                            candidates.append(GeniusHitCandidate(
                                title: songTitle,
                                artist: primaryArtist.isEmpty ? (artists.first ?? "") : primaryArtist,
                                path: songPath,
                                thumbnailURL: thumbURL,
                                artistMatches: artistMatches
                            ))
                        }
                    }
                    
                    // Sort candidate hits: hits with matching artist come first
                    candidates.sort { ($0.artistMatches ? 0 : 1) < ($1.artistMatches ? 0 : 1) }
                    
                    for candidate in candidates {
                        if let extracted = await scrapeLyrics(from: "https://genius.com\(candidate.path)", title: candidate.title, artist: candidate.artist) {
                            return GeniusSongInfo(
                                title: candidate.title,
                                artist: candidate.artist,
                                lyrics: extracted,
                                geniusURL: URL(string: "https://genius.com\(candidate.path)"),
                                thumbnailURL: candidate.thumbnailURL
                            )
                        }
                    }
                } catch {
                    continue
                }
            }
        }
        
        return nil
    }
    
    private func searchGeniusTranslation(artists: [String], title: String, isOriginalCyrillic: Bool) async -> (GeniusSongInfo, String, String)? {
        let primaryArtist = artists.first ?? ""
        var queries: [(query: String, targetLang: String, originalLang: String)] = []
        
        if isOriginalCyrillic {
            queries.append(("\(primaryArtist) \(title) english translation", "EN", "RU"))
            queries.append(("\(title) english translation", "EN", "RU"))
            queries.append(("\(primaryArtist) \(title) russian translation", "RU", "EN"))
        } else {
            queries.append(("\(primaryArtist) \(title) russian translation", "RU", "EN"))
            queries.append(("\(primaryArtist) \(title) русский перевод", "RU", "EN"))
            queries.append(("\(title) русский перевод", "RU", "EN"))
            queries.append(("\(primaryArtist) \(title) english translation", "EN", "RU"))
        }
        
        for qEntry in queries {
            guard let encodedQuery = qEntry.query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
                continue
            }
            
            let endpoints = [
                "https://genius.com/api/search/multi?q=\(encodedQuery)",
                "https://genius.com/api/search/song?q=\(encodedQuery)"
            ]
            
            for endpoint in endpoints {
                guard let searchURL = URL(string: endpoint) else { continue }
                
                var request = URLRequest(url: searchURL)
                request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36", forHTTPHeaderField: "User-Agent")
                request.setValue("application/json", forHTTPHeaderField: "Accept")
                
                do {
                    let (data, response) = try await URLSession.shared.data(for: request)
                    guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { continue }
                    
                    guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                          let responseDict = json["response"] as? [String: Any],
                          let sections = responseDict["sections"] as? [[String: Any]] else {
                        continue
                    }
                    
                    for section in sections {
                        guard let hits = section["hits"] as? [[String: Any]] else { continue }
                        for hit in hits {
                            guard let result = hit["result"] as? [String: Any],
                                  let songPath = result["path"] as? String else { continue }
                            
                            let songTitle = result["title"] as? String ?? ""
                            let fullTitle = result["full_title"] as? String ?? ""
                            let primaryArtist = (result["primary_artist"] as? [String: Any])?["name"] as? String ?? ""
                            let artistNames = result["artist_names"] as? String ?? ""
                            
                            // STRICT TITLE VALIDATION for translations
                            guard isTitleMatch(searched: title, candidate: songTitle) ||
                                  isTitleMatch(searched: title, candidate: fullTitle) else {
                                continue
                            }
                            
                            let isRussianTrans = primaryArtist.localizedCaseInsensitiveContains("Russian Translations") ||
                                                artistNames.localizedCaseInsensitiveContains("Russian Translations") ||
                                                primaryArtist.localizedCaseInsensitiveContains("Русский перевод") ||
                                                artistNames.localizedCaseInsensitiveContains("Русский перевод") ||
                                                songTitle.localizedCaseInsensitiveContains("Русский перевод") ||
                                                songTitle.localizedCaseInsensitiveContains("Russian Translation") ||
                                                fullTitle.localizedCaseInsensitiveContains("Русский перевод") ||
                                                fullTitle.localizedCaseInsensitiveContains("Russian Translation")
                            
                            let isEnglishTrans = primaryArtist.localizedCaseInsensitiveContains("English Translations") ||
                                                artistNames.localizedCaseInsensitiveContains("English Translations") ||
                                                songTitle.localizedCaseInsensitiveContains("English Translation") ||
                                                fullTitle.localizedCaseInsensitiveContains("English Translation")
                            
                            if isRussianTrans || isEnglishTrans {
                                let transLang = isRussianTrans ? "RU" : "EN"
                                let origLang = isRussianTrans ? "EN" : "RU"
                                
                                let thumbStr = result["song_art_image_thumbnail_url"] as? String
                                let thumbURL = thumbStr != nil ? URL(string: thumbStr!) : nil
                                let pageURL = URL(string: "https://genius.com\(songPath)")
                                
                                if let extracted = await scrapeLyrics(from: "https://genius.com\(songPath)", title: songTitle, artist: primaryArtist) {
                                    let songInfo = GeniusSongInfo(
                                        title: songTitle,
                                        artist: primaryArtist,
                                        lyrics: extracted,
                                        geniusURL: pageURL,
                                        thumbnailURL: thumbURL
                                    )
                                    return (songInfo, transLang, origLang)
                                }
                            }
                        }
                    }
                } catch {
                    continue
                }
            }
        }
        
        return nil
    }
    
    private func scrapeLyrics(from urlString: String, title: String = "", artist: String = "") async -> String? {
        guard let url = URL(string: urlString) else { return nil }
        
        var request = URLRequest(url: url)
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36", forHTTPHeaderField: "User-Agent")
        request.setValue("text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8", forHTTPHeaderField: "Accept")
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return nil }
            guard let html = String(data: data, encoding: .utf8) else { return nil }
            
            // Extract all data-lyrics-container="true" blocks with balanced tag depth
            let containers = extractLyricsContainers(from: html)
            guard !containers.isEmpty else { return nil }
            
            var cleanedContainers = [String]()
            for rawBlock in containers {
                var block = rawBlock
                
                // Remove header containers (e.g. LyricsHeader, exclude-from-selection)
                block = block.replacingOccurrences(
                    of: #"(?s)<div[^>]*class="[^"]*LyricsHeader[^"]*"[^>]*>.*?</div>"#,
                    with: "\n",
                    options: .regularExpression
                )
                block = block.replacingOccurrences(
                    of: #"(?s)<div[^>]*data-exclude-from-selection="true"[^>]*>.*?</div>"#,
                    with: "\n",
                    options: .regularExpression
                )
                
                // Convert line breaks and block tags to newlines
                block = block.replacingOccurrences(of: #"(?i)<br\s*/?>"#, with: "\n", options: .regularExpression)
                block = block.replacingOccurrences(of: #"(?i)</(div|p|h\d)>"#, with: "\n", options: .regularExpression)
                
                // Strip all remaining HTML tags
                block = block.replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression)
                
                // Decode HTML entities
                block = decodeHTMLEntities(block)
                
                cleanedContainers.append(block)
            }
            
            let combined = cleanedContainers.joined(separator: "\n\n")
            
            // Process lines to remove remaining metadata
            var finalLines = [String]()
            for rawLine in combined.components(separatedBy: "\n") {
                let trimmed = rawLine.trimmingCharacters(in: .whitespaces)
                
                // Drop Genius header lines (e.g. "19 Contributors", "Translations...")
                if trimmed.range(of: #"^\d+\s*Contributors?.*$"#, options: [.regularExpression, .caseInsensitive]) != nil {
                    continue
                }
                if trimmed.hasPrefix("Translations") {
                    continue
                }
                if trimmed.range(of: #"^\d*\s*Embed$"#, options: [.regularExpression, .caseInsensitive]) != nil {
                    continue
                }
                if trimmed.range(of: #"^You might also like"#, options: [.regularExpression, .caseInsensitive]) != nil {
                    continue
                }
                
                // Strip trailing Embed if attached to the end of a line (e.g. "Line text42Embed")
                let lineWithoutEmbed = trimmed.replacingOccurrences(of: #"\d*\s*Embed$"#, with: "", options: .regularExpression)
                finalLines.append(lineWithoutEmbed)
            }
            
            // Strip leading empty or song title header lines
            while !finalLines.isEmpty {
                let first = finalLines[0].trimmingCharacters(in: .whitespacesAndNewlines)
                if first.isEmpty {
                    finalLines.removeFirst()
                    continue
                }
                
                let lower = first.lowercased()
                let cleanTrackTitle = title.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
                let cleanArtist = artist.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
                
                // Matches translation headers like "Перевод песни Kai Angel...", "[Перевод песни «...»]", "English Translation", etc.
                let isTranslationHeader = lower.contains("перевод песни") ||
                                          lower.contains("перевод трека") ||
                                          lower.contains("текст и перевод") ||
                                          lower.contains("слова и перевод") ||
                                          lower.hasPrefix("перевод ") ||
                                          lower.hasPrefix("[перевод ") ||
                                          lower.hasPrefix("перевод:") ||
                                          lower.hasPrefix("перевод на ") ||
                                          lower.hasPrefix("[перевод на ") ||
                                          lower.contains("russian translation") ||
                                          lower.contains("english translation") ||
                                          lower.hasSuffix("перевод") ||
                                          lower.hasSuffix("перевод]") ||
                                          lower.hasSuffix("перевод)") ||
                                          lower.hasSuffix("translation") ||
                                          lower.hasSuffix("translation]") ||
                                          lower.hasSuffix("translation)")
                
                // Matches "[Текст песни «...»]", "Текст песни ...", "Lyrics", "... Lyrics", etc.
                let isTitleHeader = isTranslationHeader ||
                                    lower.contains("текст песни") ||
                                    lower.contains("текст трека") ||
                                    lower.contains("слова песни") ||
                                    lower.hasPrefix("текст ") ||
                                    lower.hasPrefix("[текст ") ||
                                    lower.hasSuffix("lyrics") ||
                                    lower.hasSuffix("lyrics]") ||
                                    lower.hasPrefix("lyrics") ||
                                    lower.hasPrefix("[lyrics") ||
                                    (!cleanTrackTitle.isEmpty && (lower == cleanTrackTitle || lower == "[\(cleanTrackTitle)]" || lower == "(\(cleanTrackTitle))" || lower.contains(cleanTrackTitle))) ||
                                    (!cleanArtist.isEmpty && lower.contains(cleanArtist) && (lower.contains(" - ") || lower.contains(" – ") || lower.contains(" — ")))
                
                if isTitleHeader {
                    finalLines.removeFirst()
                } else {
                    break
                }
            }
            
            var result = finalLines.joined(separator: "\n")
            // Collapse 3+ newlines into 2
            result = result.replacingOccurrences(of: #"\n{3,}"#, with: "\n\n", options: .regularExpression)
            result = result.trimmingCharacters(in: .whitespacesAndNewlines)
            
            return result.isEmpty ? nil : result
        } catch {
            return nil
        }
    }
    
    private func extractLyricsContainers(from html: String) -> [String] {
        var results = [String]()
        let searchTag = "data-lyrics-container=\"true\""
        var searchRange = html.startIndex..<html.endIndex
        
        while let range = html.range(of: searchTag, range: searchRange) {
            // Find '<div' before this tag
            guard let openBracket = html[searchRange.lowerBound..<range.lowerBound].range(of: "<div", options: .backwards) else {
                searchRange = range.upperBound..<html.endIndex
                continue
            }
            // Find end of this opening tag '>'
            guard let tagEnd = html.range(of: ">", range: range.upperBound..<html.endIndex) else {
                break
            }
            
            // Scan forward tracking nested <div> depth
            var depth = 1
            var cursor = tagEnd.upperBound
            let contentStart = cursor
            var contentEnd: String.Index?
            
            while cursor < html.endIndex && depth > 0 {
                guard let nextBracket = html.range(of: "<", range: cursor..<html.endIndex) else {
                    break
                }
                
                let remaining = html[nextBracket.lowerBound...]
                if remaining.hasPrefix("</div>") {
                    depth -= 1
                    let afterEnd = html.index(nextBracket.lowerBound, offsetBy: 6)
                    if depth == 0 {
                        contentEnd = nextBracket.lowerBound
                        cursor = afterEnd
                        break
                    } else {
                        cursor = afterEnd
                    }
                } else if remaining.hasPrefix("<div ") || remaining.hasPrefix("<div>") {
                    depth += 1
                    cursor = nextBracket.upperBound
                } else {
                    cursor = nextBracket.upperBound
                }
            }
            
            if let contentEnd = contentEnd {
                let block = String(html[contentStart..<contentEnd])
                results.append(block)
                searchRange = cursor..<html.endIndex
            } else {
                searchRange = tagEnd.upperBound..<html.endIndex
            }
        }
        
        return results
    }
    
    // MARK: - Fallback: lyrics.ovh
    
    private func searchLyricsOvh(artist: String, title: String) async -> String? {
        guard let encArtist = artist.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let encTitle = title.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let url = URL(string: "https://api.lyrics.ovh/v1/\(encArtist)/\(encTitle)") else {
            return nil
        }
        
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return nil }
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let lyrics = json["lyrics"] as? String else {
                return nil
            }
            let cleaned = lyrics.trimmingCharacters(in: .whitespacesAndNewlines)
            return cleaned.isEmpty ? nil : cleaned
        } catch {
            return nil
        }
    }
    
    // MARK: - Helpers
    
    private func parseTrack(title: String, username: String) -> (title: String, artists: [String]) {
        var rawTitle = title
        var parsedArtist: String? = nil
        
        // Check for dashes separating artist and title: " — ", " – ", " - ", " : "
        let dashSeparators = [" — ", " – ", " - ", " : "]
        for sep in dashSeparators {
            if let range = rawTitle.range(of: sep) {
                let left = String(rawTitle[..<range.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
                let right = String(rawTitle[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
                if !left.isEmpty && !right.isEmpty {
                    parsedArtist = left
                    rawTitle = right
                    break
                }
            }
        }
        
        let cleanedTitle = cleanTitle(rawTitle)
        
        var artistPool = [String]()
        if let parsedArtist = parsedArtist, !parsedArtist.isEmpty {
            artistPool.append(parsedArtist)
        }
        if !artistPool.contains(where: { $0.caseInsensitiveCompare(username) == .orderedSame }) {
            artistPool.append(username)
        }
        
        var individualArtists = [String]()
        let splitPatterns = [
            #"(?i)\s+feat\.?\s+"#,
            #"(?i)\s+ft\.?\s+"#,
            #"(?i)\s+featuring\s+"#,
            #"(?i)\s+with\s+"#,
            #"(?i)\s+x\s+"#,
            #"\s+&\s+"#,
            #"\s*,\s*"#,
            #"\s*\+\s*"#
        ]
        
        for art in artistPool {
            var parts = [art]
            for pat in splitPatterns {
                parts = parts.flatMap { segment -> [String] in
                    guard let regex = try? NSRegularExpression(pattern: pat) else { return [segment] }
                    let nsRange = NSRange(segment.startIndex..<segment.endIndex, in: segment)
                    let matches = regex.matches(in: segment, range: nsRange)
                    if matches.isEmpty { return [segment] }
                    
                    var pieces = [String]()
                    var curIdx = segment.startIndex
                    for m in matches {
                        if let r = Range(m.range, in: segment) {
                            let piece = String(segment[curIdx..<r.lowerBound])
                            if !piece.isEmpty { pieces.append(piece) }
                            curIdx = r.upperBound
                        }
                    }
                    let tail = String(segment[curIdx...])
                    if !tail.isEmpty { pieces.append(tail) }
                    return pieces
                }
            }
            for p in parts {
                let trimmed = p.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty && !individualArtists.contains(where: { $0.caseInsensitiveCompare(trimmed) == .orderedSame }) {
                    individualArtists.append(trimmed)
                }
            }
        }
        
        var finalArtists = [String]()
        if let parsedArtist = parsedArtist, !parsedArtist.isEmpty {
            finalArtists.append(parsedArtist)
        }
        if !finalArtists.contains(where: { $0.caseInsensitiveCompare(username) == .orderedSame }) {
            finalArtists.append(username)
        }
        
        // Joined version without punctuation: e.g. "Kai Angel 9mice"
        if individualArtists.count >= 2 {
            let combined = individualArtists.joined(separator: " ")
            if !finalArtists.contains(where: { $0.caseInsensitiveCompare(combined) == .orderedSame }) {
                finalArtists.append(combined)
            }
        }
        
        for ind in individualArtists {
            if !finalArtists.contains(where: { $0.caseInsensitiveCompare(ind) == .orderedSame }) {
                finalArtists.append(ind)
            }
        }
        
        return (title: cleanedTitle, artists: finalArtists)
    }
    
    private func normalizeForMatching(_ text: String) -> String {
        var s = text.lowercased()
        s = s.replacingOccurrences(of: #"\([^\)]*\)"#, with: "", options: .regularExpression)
        s = s.replacingOccurrences(of: #"\[[^\]]*\]"#, with: "", options: .regularExpression)
        let punctuation = CharacterSet.punctuationCharacters.union(.symbols)
        s = s.components(separatedBy: punctuation).joined(separator: " ")
        let tokens = s.split(separator: " ").map(String.init)
        return tokens.joined(separator: " ")
    }
    
    private func isTitleMatch(searched: String, candidate: String) -> Bool {
        let normSearched = normalizeForMatching(searched)
        let normCandidate = normalizeForMatching(candidate)
        
        guard !normSearched.isEmpty && !normCandidate.isEmpty else { return false }
        
        // Exact normalized match
        if normSearched == normCandidate { return true }
        
        // Rejection of special tracks if not requested
        let strictTags = ["interlude", "skit", "instrumental", "acapella", "snippet"]
        for tag in strictTags {
            if normCandidate.contains(tag) && !normSearched.contains(tag) {
                return false
            }
        }
        
        let searchedTokens = normSearched.split(separator: " ").map(String.init)
        let candidateTokens = normCandidate.split(separator: " ").map(String.init)
        
        let searchedSet = Set(searchedTokens)
        let candidateSet = Set(candidateTokens)
        
        if searchedSet == candidateSet { return true }
        
        // Multiple word searched title matches candidate
        if searchedTokens.count >= 2 && searchedSet.isSubset(of: candidateSet) {
            return true
        }
        if candidateSet.isSubset(of: searchedSet) && candidateTokens.count >= 1 {
            return true
        }
        
        // Substring check for titles with length >= 3
        if normSearched.count >= 3 && normCandidate.count >= 3 {
            if normCandidate.hasPrefix(normSearched + " ") || normCandidate.hasSuffix(" " + normSearched) {
                return true
            }
            if normSearched.hasPrefix(normCandidate + " ") || normSearched.hasSuffix(" " + normCandidate) {
                return true
            }
        }
        
        return false
    }
    
    private func isArtistMatch(searchedArtists: [String], candidateArtist: String) -> Bool {
        let normCandidate = normalizeForMatching(candidateArtist)
        for art in searchedArtists {
            let normArt = normalizeForMatching(art)
            if normArt.isEmpty { continue }
            if normCandidate == normArt ||
               normCandidate.contains(normArt) ||
               normArt.contains(normCandidate) {
                return true
            }
        }
        return false
    }
    
    private func cleanTitle(_ raw: String) -> String {
        var str = raw
        // If "Artist - Title", keep Title
        for dash in [" — ", " – ", " - ", " : "] {
            if let r = str.range(of: dash) {
                str = String(str[r.upperBound...])
            }
        }
        
        // Remove common junk in track titles
        let junkPatterns = [
            #"(?i)[\(\[](feat|ft|prod|official|video|audio|lyrics|remix|edit|hq|hd|visualizer|original mix|extended mix)[\.\s][^\)\]]*[\)\]]"#,
            #"(?i)[\(\[](out now|free download|premiere|stream|music video|lyric video|bonus|bonus track)[\)\]]"#,
            #"(?i)[\[\(].*?(clip|exclusive).*?[\]\)]"#
        ]
        
        for pat in junkPatterns {
            str = str.replacingOccurrences(of: pat, with: "", options: .regularExpression)
        }
        
        return str.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    private func decodeHTMLEntities(_ string: String) -> String {
        var str = string
        let entities = [
            ("&quot;", "\""),
            ("&apos;", "'"),
            ("&#x27;", "'"),
            ("&#39;", "'"),
            ("&amp;", "&"),
            ("&lt;", "<"),
            ("&gt;", ">"),
            ("&nbsp;", " "),
            ("&#8217;", "'"),
            ("&#8220;", "\""),
            ("&#8221;", "\""),
            ("&#8212;", "—"),
            ("&#8211;", "–")
        ]
        for (entity, replacement) in entities {
            str = str.replacingOccurrences(of: entity, with: replacement)
        }
        return str
    }
}
