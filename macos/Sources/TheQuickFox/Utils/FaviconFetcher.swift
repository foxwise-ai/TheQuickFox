//
//  FaviconFetcher.swift
//  TheQuickFox
//
//  Fetches favicons for URLs using multiple services for best quality
//

import AppKit
import CommonCrypto
import Foundation

/// Fetches favicons for websites with LRU cache
class FaviconFetcher {
    static let shared = FaviconFetcher()

    // LRU cache - keeps most recent 10 favicons
    private var cache: [String: NSImage] = [:]
    private var cacheOrder: [String] = []  // Most recent at end
    private let maxCacheSize = 10
    private let cacheQueue = DispatchQueue(label: "com.thequickfox.favicon-cache")

    private init() {}

    /// Fetches favicon for a URL, returns cached version if available
    /// - Parameters:
    ///   - url: The webpage URL
    ///   - size: Desired icon size (default 128 for high quality)
    ///   - completion: Called with the favicon image, or nil if fetch failed
    func fetchFavicon(for url: URL, size: Int = 128, completion: @escaping (NSImage?) -> Void) {
        guard let host = url.host else {
            completion(nil)
            return
        }

        // Check cache first
        var cachedImage: NSImage?
        cacheQueue.sync {
            if let image = cache[host] {
                cachedImage = image
                // Move to end (most recently used)
                if let index = cacheOrder.firstIndex(of: host) {
                    cacheOrder.remove(at: index)
                    cacheOrder.append(host)
                }
            }
        }
        if let cached = cachedImage {
            DispatchQueue.main.async {
                completion(cached)
            }
            return
        }

        // Try Google first (usually higher quality), fallback to DuckDuckGo
        fetchFromGoogle(host: host, size: size) { [weak self] image in
            if let image = image, image.size.width >= 32 {
                self?.cacheAndReturn(image: image, host: host, completion: completion)
            } else {
                // Fallback to DuckDuckGo
                self?.fetchFromDuckDuckGo(host: host) { ddgImage in
                    if let ddgImage = ddgImage {
                        self?.cacheAndReturn(image: ddgImage, host: host, completion: completion)
                    } else {
                        // Both services returned default icons or failed - no favicon
                        DispatchQueue.main.async {
                            completion(nil)
                        }
                    }
                }
            }
        }
    }

    private func fetchFromGoogle(host: String, size: Int, completion: @escaping (NSImage?) -> Void) {
        // Request larger size for better quality
        let faviconURLString = "https://www.google.com/s2/favicons?domain=\(host)&sz=\(size)"
        guard let faviconURL = URL(string: faviconURLString) else {
            print("🖼️ [Favicon] Google: Invalid URL for \(host)")
            completion(nil)
            return
        }

        print("🖼️ [Favicon] Google: Fetching \(faviconURLString)")
        URLSession.shared.dataTask(with: faviconURL) { [weak self] data, response, error in
            if let error = error {
                print("🖼️ [Favicon] Google: Error for \(host): \(error.localizedDescription)")
                completion(nil)
                return
            }

            guard let data = data else {
                print("🖼️ [Favicon] Google: No data for \(host)")
                completion(nil)
                return
            }

            // Reject Google's default globe icon by checking hash
            let hash = self?.sha256(data: data) ?? ""
            if hash == self?.googleDefaultIconHash {
                print("🖼️ [Favicon] Google: Rejecting default icon for \(host)")
                completion(nil)
                return
            }

            guard let image = NSImage(data: data),
                  image.size.width > 0 else {
                print("🖼️ [Favicon] Google: No valid image for \(host)")
                completion(nil)
                return
            }
            print("🖼️ [Favicon] Google: Got \(Int(image.size.width))x\(Int(image.size.height)) for \(host)")
            completion(image)
        }.resume()
    }

    // SHA256 hashes of default/fallback icons to reject
    private let ddgDefaultIconHash = "e5db88ea2322863ca17817b99d60006c625a31cff0dad49cf05d3c6d16a75c17"
    private let googleDefaultIconHash = "d0a9917592d2492e6bc8a7ce987af5608d9a26e3c302fc6858e564f79d08a4d4"

    private func fetchFromDuckDuckGo(host: String, completion: @escaping (NSImage?) -> Void) {
        // DuckDuckGo often has better quality icons
        let faviconURLString = "https://icons.duckduckgo.com/ip3/\(host).ico"
        guard let faviconURL = URL(string: faviconURLString) else {
            print("🖼️ [Favicon] DDG: Invalid URL for \(host)")
            completion(nil)
            return
        }

        print("🖼️ [Favicon] DDG: Fetching \(faviconURLString)")
        URLSession.shared.dataTask(with: faviconURL) { [weak self] data, response, error in
            if let error = error {
                print("🖼️ [Favicon] DDG: Error for \(host): \(error.localizedDescription)")
                completion(nil)
                return
            }

            guard let data = data else {
                print("🖼️ [Favicon] DDG: No data for \(host)")
                completion(nil)
                return
            }

            // Reject DDG's default globe icon by checking hash
            let hash = self?.sha256(data: data) ?? ""
            if hash == self?.ddgDefaultIconHash {
                print("🖼️ [Favicon] DDG: Rejecting default icon for \(host)")
                completion(nil)
                return
            }

            guard let image = NSImage(data: data),
                  image.size.width > 0 else {
                print("🖼️ [Favicon] DDG: No valid image for \(host)")
                completion(nil)
                return
            }
            print("🖼️ [Favicon] DDG: Got \(Int(image.size.width))x\(Int(image.size.height)) for \(host)")
            completion(image)
        }.resume()
    }

    private func sha256(data: Data) -> String {
        var hash = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        data.withUnsafeBytes {
            _ = CC_SHA256($0.baseAddress, CC_LONG(data.count), &hash)
        }
        return hash.map { String(format: "%02x", $0) }.joined()
    }

    private func cacheAndReturn(image: NSImage, host: String, completion: @escaping (NSImage?) -> Void) {
        cacheQueue.async {
            // Remove if already exists (will re-add at end)
            if let index = self.cacheOrder.firstIndex(of: host) {
                self.cacheOrder.remove(at: index)
            }

            // Evict oldest if at capacity
            while self.cacheOrder.count >= self.maxCacheSize {
                let oldest = self.cacheOrder.removeFirst()
                self.cache.removeValue(forKey: oldest)
            }

            // Add new entry
            self.cache[host] = image
            self.cacheOrder.append(host)
        }
        DispatchQueue.main.async {
            completion(image)
        }
    }

    /// Clears the favicon cache
    func clearCache() {
        cacheQueue.async {
            self.cache.removeAll()
            self.cacheOrder.removeAll()
        }
    }
}
