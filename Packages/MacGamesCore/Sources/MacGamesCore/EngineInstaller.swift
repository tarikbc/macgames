import Foundation

/// Builds `<root>/engine` from the vendored engine, the profile's overlays and
/// absolute links into `<root>/deps/Frameworks`.
///
/// Files are copied byte for byte. Changing a signed Mach-O would invalidate
/// its signature, and macOS would then ignore `DYLD_FALLBACK_LIBRARY_PATH`.
public struct EngineInstaller: Sendable {
    public let runtime: RuntimeLayout
    static let markerName = ".macgames-engine"
    /// In the marker of an engine built for `GameEnvironment.mixesRenderers`, so engines built
    /// before that layout existed are replaced.
    static let separateRenderersMarker = "separate-renderers"
    /// In the marker of an engine whose D3DMetal links point into the environment's D3DMetal
    /// pack, so engines that linked the template's D3DMetal are replaced.
    static let ownD3DMetalMarker = "own-d3dmetal"

    public init(runtime: RuntimeLayout) { self.runtime = runtime }

    func wantedMarker(for paths: GamePaths) throws -> String {
        let packs = paths.environment.packs.map { name in
            (try? String(contentsOf: paths.pack(name).appendingPathComponent(".macgames-pack"), encoding: .utf8)) ?? name
        }
        // An engine pack brings the whole engine, so the app's runtime version does not matter.
        let base = paths.environment.enginePack == nil ? try runtime.version() : "pack"
        let layout = (paths.environment.mixesRenderers ? [Self.separateRenderersMarker] : [])
            + (paths.environment.d3dmetalPack != nil ? [Self.ownD3DMetalMarker] : [])
        return ([base] + paths.environment.engineOverlays + layout + packs).joined(separator: "+")
    }

    public func isCurrent(for paths: GamePaths) -> Bool {
        let marker = paths.engine.appendingPathComponent(Self.markerName)
        guard let wanted = try? wantedMarker(for: paths),
              let found = try? String(contentsOf: marker, encoding: .utf8) else { return false }
        return found == wanted
    }

    /// Returns `true` when it installed a new engine, `false` when the current one was kept.
    @discardableResult
    public func install(for paths: GamePaths) throws -> Bool {
        if isCurrent(for: paths) { return false }
        let fm = FileManager.default
        let marker = try wantedMarker(for: paths)
        try fm.createDirectory(at: paths.root, withIntermediateDirectories: true)
        let stage = paths.root.appendingPathComponent("engine-staging-\(UUID().uuidString)")
        defer { try? fm.removeItem(at: stage) }

        if let pack = paths.environment.enginePack {
            let engine = paths.pack(pack).appendingPathComponent("Engine")
            guard fm.fileExists(atPath: engine.path) else { throw SetupError("The \(pack) pack has no engine.") }
            try clone(engine, stage)
        } else {
            try ditto(runtime.engine, stage)
        }
        for name in paths.environment.engineOverlays {
            guard let overlay = overlay(name, for: paths) else {
                throw SetupError("The runtime is missing the \(name) overlay.")
            }
            try ditto(overlay, stage)
        }
        let links = paths.environment.enginePack == nil
            ? try JSONDecoder().decode([String: String].self, from: Data(contentsOf: runtime.dependencyLinks)) : [:]
        let separate = paths.environment.mixesRenderers
        let dxmtDLLs = stage.appendingPathComponent("lib/dxmt")
        for (relative, target) in links.sorted(by: { $0.key < $1.key }) {
            let link = stage.appendingPathComponent(relative)
            let overlayOwnsIt = (try? link.checkResourceIsReachable()) == true || isSymlink(link)
            if separate, Self.isD3DMetalDLL(target) {
                // Neither renderer's copy may stay in lib/wine: D3DMetal games load the template's
                // through WINEDLLPATH, and an overlay's DXMT copy moves to lib/dxmt for DXMT games.
                if overlayOwnsIt, relative.hasPrefix("lib/wine/") {
                    let moved = dxmtDLLs.appendingPathComponent(String(relative.dropFirst("lib/wine/".count)))
                    try fm.createDirectory(at: moved.deletingLastPathComponent(), withIntermediateDirectories: true)
                    try fm.moveItem(at: link, to: moved)
                }
                continue
            }
            // An overlay that ships the file itself owns that path.
            if overlayOwnsIt { continue }
            try fm.createDirectory(at: link.deletingLastPathComponent(), withIntermediateDirectories: true)
            let destination = Self.ownD3DMetal(target, for: paths) ?? paths.frameworks.appendingPathComponent(target)
            try fm.createSymbolicLink(atPath: link.path, withDestinationPath: destination.path)
        }
        try marker.write(to: stage.appendingPathComponent(Self.markerName), atomically: true, encoding: .utf8)
        try Self.swap(stage: stage, into: paths.engine)
        return true
    }

    /// Replaces `engine` with `stage`. If the new engine cannot move into place,
    /// the old one goes back, so a failed update never leaves no engine at all.
    static func swap(stage: URL, into engine: URL) throws {
        let fm = FileManager.default
        let old = engine.deletingLastPathComponent().appendingPathComponent("engine-old-\(UUID().uuidString)")
        let hadEngine = fm.fileExists(atPath: engine.path)
        if hadEngine { try fm.moveItem(at: engine, to: old) }
        do {
            try fm.moveItem(at: stage, to: engine)
        } catch {
            if hadEngine { try? fm.moveItem(at: old, to: engine) }
            throw error
        }
        try? fm.removeItem(at: old)
    }

    /// Removes half-built folders that a crash or a forced quit left behind.
    public static func removeLeftovers(in root: URL) {
        let fm = FileManager.default
        func clean(_ folder: URL, _ prefixes: [String]) {
            for name in (try? fm.contentsOfDirectory(atPath: folder.path)) ?? [] where prefixes.contains(where: name.hasPrefix) {
                try? fm.removeItem(at: folder.appendingPathComponent(name))
            }
        }
        clean(root, ["engine-staging-", "engine-old-", "deps-staging-", "crt-staging-"])
        clean(root.appendingPathComponent("packs"), ["staging-"])
        for game in (try? fm.contentsOfDirectory(atPath: root.appendingPathComponent("games").path)) ?? [] {
            clean(root.appendingPathComponent("games/\(game)"), ["cncnet-staging-"])
        }
    }

    /// An overlay ships inside the app, or inside one of the environment's packs.
    func overlay(_ name: String, for paths: GamePaths) -> URL? {
        let candidates = [runtime.overlay(name)] + paths.environment.packs.map { paths.pack($0).appendingPathComponent("Overlays/\(name)") }
        return candidates.first { FileManager.default.fileExists(atPath: $0.path) }
    }

    /// Where an environment that pins its own D3DMetal finds a template D3DMetal file in its pack.
    /// The Windows DLLs and libd3dshared must come from one D3DMetal: an older libd3dshared
    /// writes into a newer dxgi.dll's code, which crashes any process that loads it.
    static func ownD3DMetal(_ target: String, for paths: GamePaths) -> URL? {
        let prefix = "renderer/d3dmetal/"
        guard paths.environment.d3dmetalPack != nil, target.hasPrefix(prefix) else { return nil }
        let own = paths.d3dmetal.appendingPathComponent(String(target.dropFirst(prefix.count)))
        return FileManager.default.fileExists(atPath: own.path) ? own : nil
    }

    /// A dependency link to one of D3DMetal's Windows DLLs, which share their names with DXMT's.
    static func isD3DMetalDLL(_ target: String) -> Bool {
        target.hasPrefix("renderer/d3dmetal/") && target.hasSuffix(".dll")
    }

    func isSymlink(_ url: URL) -> Bool {
        (try? FileManager.default.destinationOfSymbolicLink(atPath: url.path)) != nil
    }

    func ditto(_ source: URL, _ destination: URL) throws {
        try copy("/usr/bin/ditto", ["--noextattr", "--norsrc", source.path, destination.path], source)
    }

    /// Copies a folder as clones where the volume allows it, so a large engine takes no extra space.
    func clone(_ source: URL, _ destination: URL) throws {
        try copy("/bin/cp", ["-cR", source.path, destination.path], source)
    }

    func copy(_ tool: String, _ arguments: [String], _ source: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = arguments
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw SetupError("Could not copy \(source.lastPathComponent) (\(URL(fileURLWithPath: tool).lastPathComponent) exit \(process.terminationStatus)).")
        }
    }
}

public struct SetupError: Error, CustomStringConvertible, Equatable {
    public let description: String
    public init(_ description: String) { self.description = description }
}
