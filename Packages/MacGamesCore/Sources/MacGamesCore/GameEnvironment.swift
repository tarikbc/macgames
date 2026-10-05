import Foundation

/// A Windows environment: one engine, one Wine prefix and one launcher client,
/// shared by the games that can live together in it.
///
/// Most games share the `steam` environment. A game gets its own when it needs a
/// different engine build or prefix-wide changes that would break the others.
public struct GameEnvironment: Sendable, Hashable, Identifiable {
    public enum Launcher: Sendable, Hashable {
        case steam
        case battleNet
    }

    /// Graphics libraries copied into the prefix during setup, in order.
    public enum PrefixDLLStep: Sendable, Hashable {
        /// D3DMetal `dxgi`, `d3d11`, `d3d12`, `atidxx64` into system32.
        case d3dmetalSystem32
        /// The engine's `winemetal.dll` (DXMT bridge) into system32 and syswow64.
        case winemetal
        /// The engine's DXMT `dxgi`, `d3d11`, `d3d10core`, `winemetal` into system32 and syswow64.
        case engineDXMT
        /// The engine's 32-bit DXMT DLLs into syswow64 only (the Battle.net client is 32-bit).
        case engineDXMT32
        /// WineD3D `d3d11`, `dxgi`, `d3d10core` from the rockstar pack into system32.
        case rockstarWineD3D
    }

    public let id: String
    public let title: String
    /// Sidebar group; environments of one publisher share it.
    public let group: String
    public let launcher: Launcher
    /// Folders copied over the base engine, from the app's runtime or this environment's packs.
    public let engineOverlays: [String]
    /// Release packs downloaded on first setup of this environment.
    public let packs: [String]
    public let prefixDLLs: [PrefixDLLStep]
    /// Drive letters pointed at this environment's root instead of the Mac's `/`.
    public let rootDrives: [String]
    /// Where D3DMetal comes from: `nil` for the Sikarugir template, or a pack folder.
    public let d3dmetalPack: String?
    /// Runs the WineBus registry step that routes controllers through SDL.
    public let sdlControllers: Bool

    public var games: [GameProfile] { GameProfile.all.filter { $0.environment == id } }

    public static let steam = GameEnvironment(
        id: "steam", title: "Steam", group: "Steam library", launcher: .steam,
        engineOverlays: ["ntdllfix", "cs2", "aomretold", "controllers"], packs: [],
        prefixDLLs: [.d3dmetalSystem32, .winemetal], rootDrives: [], d3dmetalPack: nil, sdlControllers: true)

    public static let skyrim = GameEnvironment(
        id: "skyrim", title: "Skyrim", group: "Skyrim", launcher: .steam,
        engineOverlays: ["skyrim", "controllers"], packs: ["skyrim"],
        prefixDLLs: [.engineDXMT], rootDrives: ["y", "z"], d3dmetalPack: nil, sdlControllers: true)

    public static let overwatch = GameEnvironment(
        id: "overwatch", title: "Overwatch", group: "Overwatch", launcher: .steam,
        engineOverlays: ["overwatch", "controllers"], packs: ["overwatch"],
        prefixDLLs: [.winemetal], rootDrives: [], d3dmetalPack: nil, sdlControllers: true)

    public static let battlenet = GameEnvironment(
        id: "battlenet", title: "Battle.net", group: "Battle.net", launcher: .battleNet,
        engineOverlays: ["battlenet", "controllers"], packs: ["battlenet"],
        prefixDLLs: [.d3dmetalSystem32, .engineDXMT32], rootDrives: ["z"], d3dmetalPack: nil, sdlControllers: true)

    public static let rockstar = GameEnvironment(
        id: "rockstar", title: "Rockstar", group: "Rockstar", launcher: .steam,
        engineOverlays: ["rockstar", "controllers"], packs: ["rockstar"],
        prefixDLLs: [.d3dmetalSystem32, .rockstarWineD3D], rootDrives: ["y", "z"], d3dmetalPack: nil, sdlControllers: true)

    public static let gta5 = GameEnvironment(
        id: "gta5", title: "GTA V", group: "Rockstar", launcher: .steam,
        engineOverlays: ["gta5"], packs: ["gta5", "rockstar", "apple-d3dmetal-4.0b2"],
        prefixDLLs: [.d3dmetalSystem32, .rockstarWineD3D], rootDrives: ["y", "z"],
        d3dmetalPack: "apple-d3dmetal-4.0b2", sdlControllers: false)

    public static let all: [GameEnvironment] = [.steam, .skyrim, .overwatch, .battlenet, .rockstar, .gta5]

    public static func named(_ id: String) -> GameEnvironment? { all.first { $0.id == id } }

    /// Sidebar groups in environment order, each with its games.
    public static var groups: [(title: String, games: [GameProfile])] {
        var result: [(title: String, games: [GameProfile])] = []
        for env in all {
            if let index = result.firstIndex(where: { $0.title == env.group }) {
                result[index].games += env.games
            } else {
                result.append((env.group, env.games))
            }
        }
        return result.filter { !$0.games.isEmpty }
    }
}
