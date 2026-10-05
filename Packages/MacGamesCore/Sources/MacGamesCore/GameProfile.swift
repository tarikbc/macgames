import Foundation

/// A game this launcher knows how to set up and run.
public struct GameProfile: Sendable, Hashable, Identifiable {
    public enum Graphics: Sendable, Hashable {
        /// Apple D3DMetal from the Sikarugir template (`renderer/d3dmetal`).
        case d3dmetal
        /// DXMT from the vendored engine overlay (`winemetal`).
        case dxmt
    }

    public let id: String
    public let title: String
    public let steamAppID: String
    public let installFolder: String
    public let executableRelativePath: String
    /// Vendored overlay folders copied over the base engine, in order.
    public let engineOverlays: [String]
    public let graphics: Graphics
    /// The executable build the fixed-address x87sidecar optimization targets.
    /// `nil` means the profile never uses the sidecar.
    public let optimizedExecutableSHA256: String?

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

    public var artwork: Artwork {
        let base = "https://shared.akamai.steamstatic.com/store_item_assets/steam/apps/\(steamAppID)/"
        return Artwork(hero: URL(string: base + "library_hero.jpg")!,
                       logo: URL(string: base + "logo.png")!,
                       portrait: URL(string: base + "library_600x900.jpg")!)
    }

    public static let aoe4 = GameProfile(
        id: "aoe4", title: "Age of Empires IV", steamAppID: "1466860",
        installFolder: "Age of Empires IV", executableRelativePath: "RelicCardinal.exe",
        engineOverlays: ["controllers"], graphics: .d3dmetal,
        optimizedExecutableSHA256: "5380c577805565817f528af6eac385263413fa6815553f9a31fa62561cb45e8c",
        presentation: Presentation(accentHex: "C8403B", heroFocus: .init(x: 0.32, y: 0.45)))

    public static let cs2 = GameProfile(
        id: "cs2", title: "Counter-Strike 2", steamAppID: "730",
        installFolder: "Counter-Strike Global Offensive", executableRelativePath: "game/bin/win64/cs2.exe",
        engineOverlays: ["cs2", "controllers"], graphics: .dxmt,
        optimizedExecutableSHA256: nil,
        presentation: Presentation(accentHex: "E9A23B", heroFocus: .init(x: 0.78, y: 0.4)))

    public static let all: [GameProfile] = [.aoe4, .cs2]

    /// Every game shares one engine, so it carries every profile's overlays,
    /// in first-seen order (game overlays before the shared controller one).
    public static var libraryOverlays: [String] {
        var seen: [String] = []
        for name in all.flatMap(\.engineOverlays) where !seen.contains(name) { seen.append(name) }
        return seen.sorted { a, b in (a == "controllers" ? 1 : 0) < (b == "controllers" ? 1 : 0) }
    }

    public static func named(_ id: String) -> GameProfile? { all.first { $0.id == id } }
}
