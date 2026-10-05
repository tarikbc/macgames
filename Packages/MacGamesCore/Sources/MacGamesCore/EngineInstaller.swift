import Foundation

/// Builds `<root>/engine` from the vendored engine, the profile's overlays and
/// absolute links into `<root>/deps/Frameworks`.
///
/// Files are copied byte for byte. Changing a signed Mach-O would invalidate
/// its signature, and macOS would then ignore `DYLD_FALLBACK_LIBRARY_PATH`.
public struct EngineInstaller: Sendable {
    public let runtime: RuntimeLayout
    static let markerName = ".macgames-engine"

    public init(runtime: RuntimeLayout) { self.runtime = runtime }

    func wantedMarker(for profile: GameProfile) throws -> String {
        "\(try runtime.version())+\(profile.engineOverlays.joined(separator: "+"))"
    }

    public func isCurrent(for paths: GamePaths) -> Bool {
        let marker = paths.engine.appendingPathComponent(Self.markerName)
        guard let wanted = try? wantedMarker(for: paths.profile),
              let found = try? String(contentsOf: marker, encoding: .utf8) else { return false }
        return found == wanted
    }

    /// Returns `true` when it installed a new engine, `false` when the current one was kept.
    @discardableResult
    public func install(for paths: GamePaths) throws -> Bool {
        if isCurrent(for: paths) { return false }
        let fm = FileManager.default
        let marker = try wantedMarker(for: paths.profile)
        try fm.createDirectory(at: paths.root, withIntermediateDirectories: true)
        let stage = paths.root.appendingPathComponent("engine-staging-\(UUID().uuidString)")
        defer { try? fm.removeItem(at: stage) }

        try ditto(runtime.engine, stage)
        for name in paths.profile.engineOverlays {
            let overlay = runtime.overlay(name)
            guard fm.fileExists(atPath: overlay.path) else {
                throw SetupError("The runtime is missing the \(name) overlay at \(overlay.path).")
            }
            try ditto(overlay, stage)
        }
        let links = try JSONDecoder().decode([String: String].self, from: Data(contentsOf: runtime.dependencyLinks))
        for (relative, target) in links.sorted(by: { $0.key < $1.key }) {
            let link = stage.appendingPathComponent(relative)
            // An overlay that ships the file itself owns that path.
            if (try? link.checkResourceIsReachable()) == true || isSymlink(link) { continue }
            try fm.createDirectory(at: link.deletingLastPathComponent(), withIntermediateDirectories: true)
            try fm.createSymbolicLink(atPath: link.path, withDestinationPath: paths.frameworks.appendingPathComponent(target).path)
        }
        try marker.write(to: stage.appendingPathComponent(Self.markerName), atomically: true, encoding: .utf8)

        let old = paths.root.appendingPathComponent("engine-old-\(UUID().uuidString)")
        if fm.fileExists(atPath: paths.engine.path) { try fm.moveItem(at: paths.engine, to: old) }
        defer { try? fm.removeItem(at: old) }
        try fm.moveItem(at: stage, to: paths.engine)
        return true
    }

    func isSymlink(_ url: URL) -> Bool {
        (try? FileManager.default.destinationOfSymbolicLink(atPath: url.path)) != nil
    }

    func ditto(_ source: URL, _ destination: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = ["--noextattr", "--norsrc", source.path, destination.path]
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw SetupError("Could not copy \(source.lastPathComponent) (ditto exit \(process.terminationStatus)).")
        }
    }
}

public struct SetupError: Error, CustomStringConvertible, Equatable {
    public let description: String
    public init(_ description: String) { self.description = description }
}
