import AppKit
import MacGamesCore
import Observation

/// Loads Steam artwork once and keeps it in memory and in a disk cache.
@MainActor @Observable
final class ArtworkStore {
    static let shared = ArtworkStore()

    private(set) var images: [URL: NSImage] = [:]
    /// Images the CDN does not have, so views can show their fallback.
    private(set) var failed: Set<URL> = []
    /// Art paths the store lists, for apps that keep their art in hashed folders.
    private(set) var resolved: [String: GameProfile.Artwork] = [:]
    @ObservationIgnored private var loading: Set<URL> = []
    @ObservationIgnored private var resolving = false
    @ObservationIgnored private let session: URLSession

    private init() {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let config = URLSessionConfiguration.default
        config.urlCache = URLCache(memoryCapacity: 32 << 20, diskCapacity: 256 << 20,
                                   directory: caches.appendingPathComponent("com.tarikbc.macgames/artwork"))
        config.requestCachePolicy = .returnCacheDataElseLoad
        session = URLSession(configuration: config)
    }

    /// The game's art; the first call asks the store for the art paths of every game.
    func artwork(for profile: GameProfile) -> GameProfile.Artwork? {
        resolveOnce()
        return profile.artwork(resolved: resolved)
    }

    /// The image if it is loaded; otherwise starts loading it and returns `nil`.
    func image(_ url: URL) -> NSImage? {
        if let image = images[url] { return image }
        guard !loading.contains(url), !failed.contains(url) else { return nil }
        loading.insert(url)
        Task {
            defer { loading.remove(url) }
            guard let (data, response) = try? await session.data(from: url) else { return }
            if (response as? HTTPURLResponse)?.statusCode == 200, let image = NSImage(data: data) {
                images[url] = image
            } else {
                failed.insert(url)
            }
        }
        return nil
    }

    /// Asks the network first, so changed art shows up; offline, the last reply is used.
    private func resolveOnce() {
        guard !resolving else { return }
        resolving = true
        let url = SteamStoreArt.request(appIDs: Array(Set(GameProfile.all.map(\.steamAppID))).sorted())
        Task {
            var reply = try? await session.data(for: URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData))
            if (reply?.1 as? HTTPURLResponse)?.statusCode != 200 {
                reply = try? await session.data(for: URLRequest(url: url, cachePolicy: .returnCacheDataDontLoad))
            }
            if let data = reply?.0 { resolved = SteamStoreArt.parse(data) }
        }
    }
}

extension GameProfile {
    @MainActor var art: Artwork? { ArtworkStore.shared.artwork(for: self) }
}
