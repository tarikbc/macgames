import Foundation

/// Preferences shared by all games that use the same Wine prefix.
public struct EnvironmentSettings: Codable, Sendable, Equatable {
    public var hiDPI: Bool

    public init(hiDPI: Bool = false) { self.hiDPI = hiDPI }

    static func url(_ paths: GamePaths) -> URL { paths.root.appendingPathComponent("environment-settings.json") }

    public static func load(from paths: GamePaths) -> EnvironmentSettings {
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
        let fallback = paths.environment.games.contains {
            GameRecipes.registry(for: $0).contains(WineHiDPI.registryValue(true))
        }
        return Self(hiDPI: WineHiDPI.currentValue(in: paths.prefix) ?? fallback)
    }

    public func save(to paths: GamePaths) throws {
        try FileManager.default.createDirectory(at: paths.root, withIntermediateDirectories: true)
        try JSONEncoder().encode(self).write(to: Self.url(paths), options: .atomic)
    }
}
