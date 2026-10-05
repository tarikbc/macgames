import Foundation

/// Game-specific environment values. Each entry restates what that game's
/// working setup needs on top of its renderer's defaults.
public struct EnvironmentEdits: Sendable {
    public enum Sandbox: Sendable { case none, xdg, full }

    /// Replaces the renderer's default `WINEDLLOVERRIDES`.
    var overrides: String?
    var appendOverrides: String?
    var set: [String: String] = [:]
    var unset: [String] = []
    /// Moves `HOME` (`.full`), the XDG folders and `TMPDIR` into the game's own folder.
    var sandbox: Sandbox = .none
    /// Points D3DMetal at its shared library (`CX_APPLEGPTK_LIBD3DSHARED_PATH`).
    var libd3dshared = false
}

public enum GameRecipes {
    static let baseOverrides = "winemenubuilder.exe=;mscoree,mshtml=;gameoverlayrenderer,gameoverlayrenderer64=;"
    static let rockstarOverrides = baseOverrides + "nvapi64,nvngx="
    static let battleNetEdits = EnvironmentEdits(
        set: ["WINEMSYNC": "0", "WINE_SIMULATE_WRITECOPY": "1", "WINE_LARGE_ADDRESS_AWARE": "1", "WINE_HEAP_ZERO_MEMORY": "1",
              "DOTNET_EnableWriteXorExecute": "0", "QT_QUICK_BACKEND": "software", "QT_OPENGL": "software"],
        unset: ["AOELAB_STEAM_SINGLEPROCESS"], sandbox: .full, libd3dshared: true)

    public static func environmentEdits(for profile: GameProfile, paths: GamePaths) -> EnvironmentEdits {
        let graphics = paths.graphics.path, logs = paths.logs.path
        switch profile.id {
        case "cs2":
            return EnvironmentEdits(set: [
                "DXMT_CS2_EARLY_COMPILE": "1",
                "DXMT_SHADER_CACHE_PATH": graphics + "/shader-cache",
                "DXMT_CS2_PIPELINE_CACHE": graphics + "/game-archives",
                "DXMT_CS2_RECIPE_DIR": graphics + "/recipes",
                "DXMT_LOG_PATH": logs,
            ])
        case "aoe3":
            return EnvironmentEdits(sandbox: .full, libd3dshared: true)
        case "aom-retold":
            return EnvironmentEdits(unset: ["SteamAppId", "SteamGameId", "SteamOverlayGameId"], sandbox: .full, libd3dshared: true)
        case "hogwarts-legacy":
            return EnvironmentEdits(set: ["MTL_SHADER_CACHE_PATH": paths.gameData.path + "/shader-cache"],
                                    sandbox: .full, libd3dshared: true)
        case "poe2":
            return EnvironmentEdits(set: ["WINEMSYNC": "0"], sandbox: .xdg, libd3dshared: true)
        case "diablo4":
            return EnvironmentEdits(libd3dshared: true)
        case "witcher3":
            return EnvironmentEdits(appendOverrides: ";amd_fidelityfx_loader_dx12=n",
                                    set: ["FFXPROXY_NO_DPI": "1", "CFFIXED_USER_HOME": paths.gameData.path + "/home"],
                                    sandbox: .full, libd3dshared: true)
        case "heroes3":
            return EnvironmentEdits(overrides: baseOverrides + "dxgi,d3d10,d3d10_1,d3d10core,d3d11,d3d9,ddraw=b;xdd=n",
                                    set: ["SteamAppId": "4921760"], sandbox: .full)
        case "elden-ring":
            // Started directly, so it reads its app ID from the environment, not from Steam.
            return EnvironmentEdits(set: ["SteamAppId": "1245620"], unset: ["SteamGameId"], sandbox: .full, libd3dshared: true)
        case "skyrim-se":
            return EnvironmentEdits(
                overrides: baseOverrides + "dxgi,d3d11,d3d10core,winemetal=b;xaudio2_6,xaudio2_7,x3daudio1_6,x3daudio1_7=n,b;nvapi64,nvngx=",
                set: ["DXMT_SHADER_CACHE_PATH": paths.gameData.path + "/shader-cache", "DXMT_LOG_PATH": logs], sandbox: .xdg)
        case "overwatch":
            return EnvironmentEdits(
                overrides: baseOverrides + "dxgi,d3d11,d3d10core,winemetal=b;d3d12,d3d12core=;nvapi64,nvngx=",
                set: ["DXMT_OWT_EARLY_COMPILE": "0", "DXMT_LOG_PATH": logs, "DXMT_LOG_LEVEL": "warn",
                      "DXMT_SHADER_CACHE_PATH": graphics + "/shader-cache",
                      "DXMT_OWT_PIPELINE_CACHE": graphics + "/game-archives", "DXMT_OWT_RECIPE_DIR": graphics + "/recipes"],
                libd3dshared: true)
        case "diablo4-battlenet", "diablo2-resurrected":
            return battleNetEdits
        case "rdr2":
            return EnvironmentEdits(overrides: rockstarOverrides,
                                    set: ["GTM_ROCKSTAR_SWIFTSHADER": "1", "D3DM_VENDOR_ID": "0x106b",
                                          "D3DM_DEVICE_DESCRIPTION": "Apple Silicon (D3DMetal)"],
                                    sandbox: .full, libd3dshared: true)
        case "san-andreas-de":
            return EnvironmentEdits(overrides: rockstarOverrides, set: ["GTM_ROCKSTAR_SWIFTSHADER": "1"],
                                    sandbox: .full, libd3dshared: true)
        case "gta5-enhanced":
            return EnvironmentEdits(overrides: rockstarOverrides,
                                    set: ["GTM_ROCKSTAR_SWIFTSHADER": "1", "WINEMSYNC": "0", "USER": "crossover", "LOGNAME": "crossover"],
                                    sandbox: .full, libd3dshared: true)
        default:
            return EnvironmentEdits()
        }
    }

    /// Every Windows program that counts as this game running, including processes Steam
    /// does not track: online clients and the games they start.
    public static func processNames(for profile: GameProfile) -> [String] {
        switch profile.online {
        case .generalsOnline: [profile.executableName, "GeneralsOnlineZH.exe", "GeneralsOnlineZH_60.exe", "generals.exe", "game.dat"]
        case .cncnet: [profile.executableName, "gamemd.exe", "gamemd-spawn.exe", "game.exe", "dotnet.exe"]
        case nil: [profile.executableName]
        }
    }

    /// Identifies an environment's registry and sandbox recipes, so a change reaches existing installs.
    static func recipeHash(for environment: GameEnvironment, root: URL) -> String {
        let registry = environment.games.flatMap(registry(for:)).map { "\($0.key)|\($0.name)|\($0.value)" }
        return sha256Hex(Data(registry.joined(separator: "\n").utf8))
    }

    /// Registry values a game needs, scoped to its own executables where possible.
    public static func registry(for profile: GameProfile) -> [RegistryValue] {
        typealias R = RegistryValue
        func rockstar(_ game: String, extra: [RegistryValue] = []) -> [RegistryValue] {
            ["dxgi", "d3d11", "d3d10core", "d3d12", "atidxx64"].map { R.dll(game, $0, "builtin") }
                + ["Launcher.exe", "LauncherPatcher.exe", "SocialClubHelper.exe"].flatMap { exe in
                    ["dxgi", "d3d11", "d3d10core"].map { R.dll(exe, $0, "native,builtin") } + [R.dll(exe, "d3d12", "")]
                } + extra
        }
        switch profile.id {
        case "aoe3":
            let key = #"HKEY_CURRENT_USER\Software\Microsoft\Microsoft Games\Age of Empires III DE"#
            return [R(key: key, name: "IgnoreUnsupportedSystem", value: .string("1")),
                    R(key: key, name: "SystemInitialization", value: .string("1"))]
        case "witcher3": return [R.windowsVersion("witcher3.exe", "win11")]
        case "heroes3": return [R.windowsVersion("Heroes3.exe", "win11")]
        case "red-alert2":
            return ["Ra2.exe", "game.exe", "RA2MD.exe", "gamemd.exe", "gamemd-spawn.exe"].map { R.dll($0, "ddraw", "native,builtin") }
        case "rdr2": return rockstar("RDR2.exe")
        case "san-andreas-de": return rockstar("SanAndreas.exe")
        case "gta5-enhanced":
            return rockstar("GTA5_Enhanced.exe", extra: [R.dll("SocialClubHelper.exe", "vulkan-1", "native"),
                                                       R.dll("steamwebhelper.exe", "vulkan-1", "native")])
        default: return []
        }
    }

    /// Folders that a sandboxed environment points at; they must exist before Wine starts.
    public static func sandboxFolders(for profile: GameProfile, paths: GamePaths) -> [URL] {
        switch environmentEdits(for: profile, paths: paths).sandbox {
        case .none: []
        case .xdg: ["cache", "config", "share", "tmp"].map { paths.gameData.appendingPathComponent($0) }
        case .full: ["home", "cache", "config", "share", "tmp", "shader-cache"].map { paths.gameData.appendingPathComponent($0) }
        }
    }
}
