import Foundation

/// Where the vendored runtime lives: inside MacGames.app, or any folder with the same shape.
public struct RuntimeLayout: Sendable {
    /// Holds `Engine/`, `Overlays/<name>/`, `dependency-links.json` and `VERSION`.
    public let resources: URL
    /// Holds `MacGamesBridge`, `x87sidecar` and `RosettaProbe`.
    public let helpers: URL

    public init(resources: URL, helpers: URL) {
        self.resources = resources
        self.helpers = helpers
    }

    public static func inBundle(_ bundle: Bundle = .main) -> RuntimeLayout {
        RuntimeLayout(resources: bundle.bundleURL.appendingPathComponent("Contents/Resources/Runtime"),
                      helpers: bundle.bundleURL.appendingPathComponent("Contents/Helpers"))
    }

    public var engine: URL { resources.appendingPathComponent("Engine") }
    public func overlay(_ name: String) -> URL { resources.appendingPathComponent("Overlays/\(name)") }
    public var dependencyLinks: URL { resources.appendingPathComponent("dependency-links.json") }
    public var bridge: URL { helpers.appendingPathComponent("MacGamesBridge") }
    public var sidecar: URL { helpers.appendingPathComponent("x87sidecar") }
    public var rosettaProbe: URL { helpers.appendingPathComponent("RosettaProbe") }

    public func version() throws -> String {
        try String(contentsOf: resources.appendingPathComponent("VERSION"), encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
