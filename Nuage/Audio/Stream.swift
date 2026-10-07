//
//  Stream.swift
//  Nuage
//
//  Created by Laurin Brandner on 26.12.19.
//  Copyright © 2019 Laurin Brandner. All rights reserved.
//

import AVFoundation
import Combine
import SoundCloud

struct NoStreamError: Error {}

extension Track: Streamable {
    
    func prepare() -> AnyPublisher<AVURLAsset, Error> {
        var urls = streamURLs
        if urls.isEmpty, let url = streamURL {
            urls = [url]
        }
        guard !urls.isEmpty else { return Fail(error: NoStreamError()).eraseToAnyPublisher() }
        
        return prepareWithFallback(urls: urls, index: 0, trackAuth: trackAuthorization)
    }
    
    private func prepareWithFallback(urls: [URL], index: Int, trackAuth: String?) -> AnyPublisher<AVURLAsset, Error> {
        guard index < urls.count else {
            return Fail(error: NSError(domain: "SoundCloudAPI", code: 404, userInfo: [NSLocalizedDescriptionKey: "All stream formats failed"])).eraseToAnyPublisher()
        }
        
        let url = urls[index]
        var targetURL = url
        if let auth = trackAuth, !auth.isEmpty {
            if var components = URLComponents(url: url, resolvingAgainstBaseURL: false) {
                var queryItems = components.queryItems ?? []
                if !queryItems.contains(where: { $0.name == "track_authorization" }) {
                    queryItems.append(URLQueryItem(name: "track_authorization", value: auth))
                    components.queryItems = queryItems
                    if let newURL = components.url {
                        targetURL = newURL
                    }
                }
            }
        }
        
        return SoundCloud.shared.get(.audioFile(targetURL))
            .map { AVURLAsset(url: $0) }
            .catch { error -> AnyPublisher<AVURLAsset, Error> in
                print("Stream format \(index + 1)/\(urls.count) failed (\(error)). Trying next available format...")
                if index + 1 < urls.count {
                    return self.prepareWithFallback(urls: urls, index: index + 1, trackAuth: trackAuth)
                } else {
                    return Fail(error: error).eraseToAnyPublisher()
                }
            }
            .eraseToAnyPublisher()
    }
    
}
