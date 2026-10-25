import Foundation

/// Preferences shared by all games that use the same Wine prefix.
public struct EnvironmentSettings: Codable, Sendable, Equatable {
    public var hiDPI: Bool

    public init(hiDPI: Bool = false) { self.hiDPI = hiDPI }

    static func url(_ paths: GamePaths) -> URL { paths.root.appendingPathComponent("environment-settings.json") }

    /// `true` when a game in the environment needs Wine's Retina mode for the whole prefix, as
    /// Recall's fullscreen canvas does for Overwatch. HiDPI then stays on whatever was saved.
    public static func requiresHiDPI(_ environment: GameEnvironment) -> Bool {
        environment.games.contains { GameRecipes.registry(for: $0).contains(WineHiDPI.registryValue(true)) }
    }

    public static func load(from paths: GamePaths) -> EnvironmentSettings {
        if requiresHiDPI(paths.environment) { return Self(hiDPI: true) }
        if let data = try? Data(contentsOf: url(paths)),
           let saved = try? JSONDecoder().decode(Self.self, from: data) { return saved }

        // Preserve a pending choice from the original per-game preference. If
        // games disagree, keep the prefix's current mode instead of depending
        // on which game's card happens to open first.
        struct Legacy: Decodable { let hiDPI: Bool? }
        let choices = Set(paths.environment.games.compactMap { profile -> Bool? in
            let game = GamePaths(profile: profile, root: paths.root)
            guard let data = try? Data(contentsOf: LaunchSettings.url(game)) else { return nil }
            return (try? JSONDecoder().decode(Legacy.self, from: data))?.hiDPI
        })
        if choices.count == 1, let choice = choices.first { return Self(hiDPI: choice) }
        return Self(hiDPI: WineHiDPI.currentValue(in: paths.prefix) ?? false)
    }

    public func save(to paths: GamePaths) throws {
        try FileManager.default.createDirectory(at: paths.root, withIntermediateDirectories: true)
        try JSONEncoder().encode(self).write(to: Self.url(paths), options: .atomic)
    }
}
