import CryptoKit
import Foundation

func sha256Hex(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }

func sha256Hex(ofFileAt url: URL) throws -> String {
    let handle = try FileHandle(forReadingFrom: url)
    defer { try? handle.close() }
    var hasher = SHA256()
    while let chunk = try handle.read(upToCount: 1 << 20), !chunk.isEmpty { hasher.update(data: chunk) }
    return hasher.finalize().map { String(format: "%02x", $0) }.joined()
}

public struct Download: Sendable {
    public let url: URL
    /// `nil` accepts whatever the source serves (Valve updates SteamSetup.exe in place).
    public let sha256: String?
    public let fileName: String

    public static let template = Download(
        url: URL(string: "https://github.com/Sikarugir-App/Wrapper/releases/download/v1.0/Template-1.0.15.tar.xz")!,
        sha256: "34273bcce885ce5a7fd6937af9ea344bb9961de7d55d6193f7413142e835c8c3",
        fileName: "Template-1.0.15.tar.xz")

    public static let steamSetup = Download(
        url: URL(string: "https://cdn.akamai.steamstatic.com/client/installer/SteamSetup.exe")!,
        sha256: nil, fileName: "SteamSetup.exe")
}

/// Fetches into a shared cache and verifies pinned hashes before a file is used.
public struct Downloader: Sendable {
    public let cache: URL

    public init(cache: URL) { self.cache = cache }

    public func fetch(_ item: Download) throws -> URL {
        let fm = FileManager.default
        let target = cache.appendingPathComponent(item.fileName)
        if fm.fileExists(atPath: target.path) {
            if item.sha256 == nil || (try? sha256Hex(ofFileAt: target)) == item.sha256 { return target }
            try fm.removeItem(at: target)
        }
        try fm.createDirectory(at: cache, withIntermediateDirectories: true)
        let partial = cache.appendingPathComponent(".\(item.fileName).\(UUID().uuidString).partial")
        defer { try? fm.removeItem(at: partial) }
        try transfer(item.url, to: partial)
        return try commit(partial, to: target, pin: item.sha256)
    }

    /// Verifies `partial` and puts it at `target`. Another setup may have
    /// placed the same file meanwhile; a verified one is kept.
    func commit(_ partial: URL, to target: URL, pin: String?) throws -> URL {
        let fm = FileManager.default
        if let pin {
            let actual = try sha256Hex(ofFileAt: partial)
            guard actual == pin else {
                throw SetupError("\(target.lastPathComponent) failed verification (SHA-256 \(actual), expected \(pin)).")
            }
        }
        if fm.fileExists(atPath: target.path) {
            if pin == nil || (try? sha256Hex(ofFileAt: target)) == pin { return target }
            try fm.removeItem(at: target)
        }
        try fm.moveItem(at: partial, to: target)
        return target
    }

    func transfer(_ source: URL, to destination: URL) throws {
        if source.isFileURL {
            try FileManager.default.copyItem(at: source, to: destination)
            return
        }
        final class Box: @unchecked Sendable { var result: Result<URL, any Error>? }
        let box = Box()
        let done = DispatchSemaphore(value: 0)
        let task = URLSession.shared.downloadTask(with: source) { file, response, error in
            defer { done.signal() }
            if let error { box.result = .failure(error); return }
            guard let file, let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                box.result = .failure(SetupError("Download of \(source.lastPathComponent) failed (\((response as? HTTPURLResponse)?.statusCode ?? 0)).")); return
            }
            // The temporary file is deleted when this handler returns.
            do { try FileManager.default.moveItem(at: file, to: destination); box.result = .success(destination) }
            catch { box.result = .failure(error) }
        }
        task.resume()
        done.wait()
        _ = try box.result!.get()
    }
}
