import Foundation

/// Release packs: large or environment-only parts of the runtime, downloaded on
/// first setup of the environment that needs them.
public enum Packs {
    static let release = "https://github.com/tarikbc/macgames/releases/download/packs-1/"

    /// Pinned archives: name -> SHA-256. Filled in when the packs are published.
    public static let pinned: [String: String] = [:]

    public static func download(_ name: String) -> Download {
        Download(url: URL(string: release + "macgames-pack-\(name).tar.xz")!, sha256: pinned[name],
                 fileName: "macgames-pack-\(name).tar.xz")
    }

    /// Downloads, checks and unpacks `name` into `<root>/packs/<name>` unless it is already there.
    public static func install(_ name: String, paths: GamePaths, downloader: Downloader, runner: ProcessRunner) throws {
        let fm = FileManager.default
        let target = paths.pack(name)
        let marker = target.appendingPathComponent(".macgames-pack")
        let wanted = pinned[name] ?? name
        if (try? String(contentsOf: marker, encoding: .utf8)) == wanted { return }
        let archive = try downloader.fetch(download(name))
        let stage = paths.packs.appendingPathComponent("staging-\(name)-\(UUID().uuidString)")
        try fm.createDirectory(at: stage, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: stage) }
        try runner.run(URL(fileURLWithPath: "/usr/bin/tar"), ["-xJf", archive.path, "-C", stage.path], timeout: 900)
        let unpacked = stage.appendingPathComponent(name)
        guard fm.fileExists(atPath: unpacked.path) else { throw SetupError("The \(name) pack has an unexpected layout.") }
        try wanted.write(to: unpacked.appendingPathComponent(".macgames-pack"), atomically: true, encoding: .utf8)
        if fm.fileExists(atPath: target.path) { try fm.removeItem(at: target) }
        try fm.moveItem(at: unpacked, to: target)
    }
}
