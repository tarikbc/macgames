import Foundation

/// Release packs: large or environment-only parts of the runtime, downloaded on
/// first setup of the environment that needs them.
public enum Packs {
    static let release = "https://github.com/tarikbc/macgames/releases/download/packs-1/"

    /// Pinned archives: name -> SHA-256.
    public static let pinned: [String: String] = [
        "apple-d3dmetal-4.0b2": "209a9203864a0618d686096162f75ce506838fcfe3a715b997f87759dbbee02e",
        "battlenet": "a9e262f72a1fe7ff0b133a9c531b8661170efae5aebcebf4347ba9d6c06a6d15",
        "gta5": "bc8d15d5ad6713e6a192de6d78e0534a2925db886d7a9225efdf52c25fcc7499",
        "overwatch": "b987bf1540b66b09369ec95124a09df066050db21f5a7a6f0376978241e91c37",
        "rockstar": "6757715792fe378758ef880ee9a433882ab6083044928ba1befbdda6f8598639",
        "skyrim": "0ebee3d52cef5d4055e7f4139b3064092907c4abcf6fdf1523a38b7b1e2a1205",
    ]

    public static func download(_ name: String, pins: [String: String] = pinned) -> Download {
        Download(url: URL(string: release + "macgames-pack-\(name).tar.xz")!, sha256: pins[name],
                 fileName: "macgames-pack-\(name).tar.xz")
    }

    /// Downloads, checks and unpacks `name` into `<root>/packs/<name>` unless it is already there.
    public static func install(_ name: String, paths: GamePaths, downloader: Downloader, runner: ProcessRunner,
                               pins: [String: String] = pinned) throws {
        let fm = FileManager.default
        let target = paths.pack(name)
        let marker = target.appendingPathComponent(".macgames-pack")
        let wanted = pins[name] ?? name
        if (try? String(contentsOf: marker, encoding: .utf8)) == wanted { return }
        let archive = try downloader.fetch(download(name, pins: pins))
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
