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

    public var executableName: String { (executableRelativePath as NSString).lastPathComponent }

    public static let aoe4 = GameProfile(
        id: "aoe4", title: "Age of Empires IV", steamAppID: "1466860",
        installFolder: "Age of Empires IV", executableRelativePath: "RelicCardinal.exe",
        engineOverlays: ["controllers"], graphics: .d3dmetal,
        optimizedExecutableSHA256: "5380c577805565817f528af6eac385263413fa6815553f9a31fa62561cb45e8c")

    public static let cs2 = GameProfile(
        id: "cs2", title: "Counter-Strike 2", steamAppID: "730",
        installFolder: "Counter-Strike Global Offensive", executableRelativePath: "game/bin/win64/cs2.exe",
        engineOverlays: ["cs2", "controllers"], graphics: .dxmt,
        optimizedExecutableSHA256: nil)

    public static let all: [GameProfile] = [.aoe4, .cs2]

    public static func named(_ id: String) -> GameProfile? { all.first { $0.id == id } }
}
