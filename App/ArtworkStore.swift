import AppKit
import Observation

/// Loads Steam artwork once and keeps it in memory and in a disk cache.
@MainActor @Observable
final class ArtworkStore {
    static let shared = ArtworkStore()

    private(set) var images: [URL: NSImage] = [:]
    @ObservationIgnored private var loading: Set<URL> = []
    @ObservationIgnored private let session: URLSession

    private init() {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let config = URLSessionConfiguration.default
        config.urlCache = URLCache(memoryCapacity: 32 << 20, diskCapacity: 256 << 20,
                                   directory: caches.appendingPathComponent("com.tarikbc.macgames/artwork"))
        config.requestCachePolicy = .returnCacheDataElseLoad
        session = URLSession(configuration: config)
    }

    /// The image if it is loaded; otherwise starts loading it and returns `nil`.
    func image(_ url: URL) -> NSImage? {
        if let image = images[url] { return image }
        guard !loading.contains(url) else { return nil }
        loading.insert(url)
        Task {
            defer { loading.remove(url) }
            guard let (data, _) = try? await session.data(from: url), let image = NSImage(data: data) else { return }
            images[url] = image
        }
        return nil
    }
}
