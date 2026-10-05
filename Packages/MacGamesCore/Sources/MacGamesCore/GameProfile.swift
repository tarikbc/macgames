import Foundation

/// A game this launcher knows how to set up and run.
public struct GameProfile: Sendable, Hashable, Identifiable {
    public enum Graphics: Sendable, Hashable {
        /// Apple D3DMetal (`dxgi,d3d11,d3d12` native from system32, Unix side from the renderer folder).
        case d3dmetal
        /// DXMT builtins from the engine (`winemetal`).
        case dxmt
        /// Wine's own builtins only, for DirectDraw and Direct3D 8/9 games with a bundled wrapper.
        case builtin
    }

    /// How the game process starts.
    public enum Launch: Sendable, Hashable {
        /// `steam.exe -applaunch <id>`; Steam starts the game with its own environment.
        case steam
        /// Steam runs first, then MacGames starts the executable itself with the game's environment.
        case direct
        /// The Battle.net client starts the game when the user chooses Play there.
        case battleNet
    }

    /// Community online clients that MacGames can set up and start.
    public enum Online: Sendable, Hashable {
        case generalsOnline
        case cncnet
    }

    public let id: String
    public let title: String
    /// Steam app ID; also used for artwork. Empty for games Steam does not sell.
    public let steamAppID: String
    /// Folder under `steamapps/common`, or under `Program Files (x86)` for Battle.net games.
    public let installFolder: String
    public let executableRelativePath: String
    public let environment: String
    public let graphics: Graphics
    public let launch: Launch
    /// The Steam client path in the launch command: some games need the Windows form.
    public let windowsSteamPath: Bool
    /// Steam options placed before `-applaunch`.
    public let steamArgs: [String]
    /// Options passed to the game after its app ID.
    public let gameArgs: [String]
    /// Lowest macOS version, as (major, minor).
    public let minimumMacOS: [Int]
    public let online: Online?
    /// The executable build the fixed-address x87sidecar optimization targets.
    /// `nil` means the profile never uses the sidecar.
    public let optimizedExecutableSHA256: String?

    public init(id: String, title: String, steamAppID: String, installFolder: String, executableRelativePath: String,
                environment: String = "steam", graphics: Graphics = .d3dmetal, launch: Launch = .steam,
                windowsSteamPath: Bool = false, steamArgs: [String] = [], gameArgs: [String] = [],
                minimumMacOS: [Int] = [26, 0], online: Online? = nil, optimizedExecutableSHA256: String? = nil,
                presentation: Presentation = Presentation()) {
        self.id = id; self.title = title; self.steamAppID = steamAppID; self.installFolder = installFolder
        self.executableRelativePath = executableRelativePath; self.environment = environment; self.graphics = graphics
        self.launch = launch; self.windowsSteamPath = windowsSteamPath; self.steamArgs = steamArgs; self.gameArgs = gameArgs
        self.minimumMacOS = minimumMacOS; self.online = online; self.optimizedExecutableSHA256 = optimizedExecutableSHA256
        self.presentation = presentation
    }

    /// How the launcher shows the game. Art comes from Steam, so a new
    /// profile needs no bundled images.
    public struct Presentation: Sendable, Hashable {
        public struct Point: Sendable, Hashable {
            public let x: Double
            public let y: Double
            public init(x: Double, y: Double) { self.x = x; self.y = y }
        }
        /// sRGB hex such as "C8403B"; `nil` lets the UI pick a neutral tint.
        public let accentHex: String?
        /// The part of the hero art that must stay visible when it is cropped (0...1).
        public let heroFocus: Point

        public init(accentHex: String? = nil, heroFocus: Point = Point(x: 0.5, y: 0.5)) {
            self.accentHex = accentHex
            self.heroFocus = heroFocus
        }
    }

    public struct Artwork: Sendable, Hashable {
        public let hero: URL
        public let logo: URL
        public let portrait: URL
    }

    public let presentation: Presentation

    public var executableName: String { (executableRelativePath as NSString).lastPathComponent }

    /// Steam store art at the fixed paths of older apps; `nil` for games Steam does not sell.
    public var artwork: Artwork? {
        guard !steamAppID.isEmpty else { return nil }
        let base = SteamStoreArt.cdn + "steam/apps/\(steamAppID)/"
        return Artwork(hero: URL(string: base + "library_hero.jpg")!,
                       logo: URL(string: base + "logo.png")!,
                       portrait: URL(string: base + "library_600x900.jpg")!)
    }

    /// The art the store lists for this game, else the fixed paths.
    public func artwork(resolved: [String: Artwork]) -> Artwork? {
        guard !steamAppID.isEmpty else { return nil }
        return resolved[steamAppID] ?? artwork
    }

    public var gameEnvironment: GameEnvironment { GameEnvironment.named(environment) ?? .steam }

    public static func named(_ id: String) -> GameProfile? { all.first { $0.id == id } }
}
