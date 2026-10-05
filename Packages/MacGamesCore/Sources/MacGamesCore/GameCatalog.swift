import Foundation

/// Every game MacGames knows. Each entry records how the game installs and starts;
/// game-specific steps live in `GameRecipes`.
extension GameProfile {
    static func p(_ x: Double, _ y: Double) -> Presentation.Point { .init(x: x, y: y) }

    public static let aoe4 = GameProfile(
        id: "aoe4", title: "Age of Empires IV", steamAppID: "1466860",
        installFolder: "Age of Empires IV", executableRelativePath: "RelicCardinal.exe",
        optimizedExecutableSHA256: "5380c577805565817f528af6eac385263413fa6815553f9a31fa62561cb45e8c",
        presentation: Presentation(accentHex: "C8403B", heroFocus: p(0.32, 0.45)))

    public static let cs2 = GameProfile(
        id: "cs2", title: "Counter-Strike 2", steamAppID: "730",
        installFolder: "Counter-Strike Global Offensive", executableRelativePath: "game/bin/win64/cs2.exe",
        graphics: .dxmt, presentation: Presentation(accentHex: "E9A23B", heroFocus: p(0.78, 0.4)))

    public static let aoe3 = GameProfile(
        id: "aoe3", title: "Age of Empires III: Definitive Edition", steamAppID: "933110",
        installFolder: "AoE3DE", executableRelativePath: "AoE3DE_s.exe", windowsSteamPath: true,
        presentation: Presentation(accentHex: "2F6DB5", heroFocus: p(0.6, 0.4)))

    public static let aomRetold = GameProfile(
        id: "aom-retold", title: "Age of Mythology: Retold", steamAppID: "1934680",
        installFolder: "Age of Mythology Retold", executableRelativePath: "AoMRT_s.exe", windowsSteamPath: true,
        presentation: Presentation(accentHex: "C9A227", heroFocus: p(0.6, 0.4)))

    public static let coh3 = GameProfile(
        id: "coh3", title: "Company of Heroes 3", steamAppID: "1677280",
        installFolder: "Company of Heroes 3", executableRelativePath: "RelicCoH3.exe",
        presentation: Presentation(accentHex: "8A9A5B", heroFocus: p(0.6, 0.4)))

    public static let hogwarts = GameProfile(
        id: "hogwarts-legacy", title: "Hogwarts Legacy", steamAppID: "990080",
        installFolder: "Hogwarts Legacy", executableRelativePath: "Phoenix/Binaries/Win64/HogwartsLegacy.exe",
        steamArgs: ["-no-cef-sandbox"], minimumMacOS: [26, 5],
        presentation: Presentation(accentHex: "B08D57", heroFocus: p(0.6, 0.4)))

    public static let poe2 = GameProfile(
        id: "poe2", title: "Path of Exile 2", steamAppID: "2694490",
        installFolder: "Path of Exile 2", executableRelativePath: "PathOfExileSteam.exe", minimumMacOS: [26, 5],
        presentation: Presentation(accentHex: "A8342A", heroFocus: p(0.6, 0.4)))

    public static let diablo4 = GameProfile(
        id: "diablo4", title: "Diablo IV", steamAppID: "2344520",
        installFolder: "Diablo IV", executableRelativePath: "Diablo IV.exe", minimumMacOS: [26, 5],
        presentation: Presentation(accentHex: "B3261E", heroFocus: p(0.6, 0.4)))

    public static let witcher3 = GameProfile(
        id: "witcher3", title: "The Witcher 3: Wild Hunt", steamAppID: "292030",
        installFolder: "The Witcher 3", executableRelativePath: "bin/x64_dx12/witcher3.exe",
        windowsSteamPath: true, gameArgs: ["--launcher-skip"],
        presentation: Presentation(accentHex: "B8322A", heroFocus: p(0.6, 0.4)))

    public static let heroes3 = GameProfile(
        id: "heroes3", title: "Heroes of Might and Magic III", steamAppID: "4921760",
        installFolder: "Heroes Of Might And Magic III", executableRelativePath: "Heroes3.exe",
        graphics: .builtin, launch: .direct, windowsSteamPath: true,
        presentation: Presentation(accentHex: "C2A049", heroFocus: p(0.5, 0.4)))

    public static let eldenRing = GameProfile(
        id: "elden-ring", title: "Elden Ring", steamAppID: "1245620",
        installFolder: "ELDEN RING", executableRelativePath: "Game/eldenring.exe", launch: .direct, windowsSteamPath: true,
        presentation: Presentation(accentHex: "C8A951", heroFocus: p(0.6, 0.4)))

    public static let zeroHour = GameProfile(
        id: "zero-hour", title: "Command & Conquer: Generals Zero Hour", steamAppID: "2732960",
        installFolder: "Command & Conquer Generals - Zero Hour", executableRelativePath: "Generals.exe",
        online: .generalsOnline, presentation: Presentation(accentHex: "6B8E23", heroFocus: p(0.6, 0.4)))

    public static let redAlert2 = GameProfile(
        id: "red-alert2", title: "Command & Conquer: Red Alert 2", steamAppID: "2229850",
        installFolder: "Command & Conquer Red Alert II", executableRelativePath: "Ra2.exe",
        online: .cncnet, presentation: Presentation(accentHex: "C0392B", heroFocus: p(0.6, 0.4)))

    public static let skyrim = GameProfile(
        id: "skyrim-se", title: "The Elder Scrolls V: Skyrim Special Edition", steamAppID: "489830",
        installFolder: "Skyrim Special Edition", executableRelativePath: "SkyrimSE.exe",
        environment: "skyrim", graphics: .dxmt, steamArgs: ["-no-cef-sandbox"],
        presentation: Presentation(accentHex: "9AA5B1", heroFocus: p(0.6, 0.4)))

    public static let overwatch = GameProfile(
        id: "overwatch", title: "Overwatch", steamAppID: "2357570",
        installFolder: "Overwatch", executableRelativePath: "_retail_/Overwatch.exe", environment: "overwatch", graphics: .dxmt,
        launch: .battleNet, battleNetProduct: "Pro", presentation: Presentation(accentHex: "F99E1A", heroFocus: p(0.6, 0.4)))

    public static let diablo4BattleNet = GameProfile(
        id: "diablo4-battlenet", title: "Diablo IV (Battle.net)", steamAppID: "2344520",
        installFolder: "Diablo IV", executableRelativePath: "Diablo IV.exe", environment: "battlenet",
        launch: .battleNet, minimumMacOS: [26, 5],
        presentation: Presentation(accentHex: "B3261E", heroFocus: p(0.6, 0.4)))

    public static let diablo2Resurrected = GameProfile(
        id: "diablo2-resurrected", title: "Diablo II: Resurrected", steamAppID: "2536520",
        installFolder: "Diablo II Resurrected", executableRelativePath: "D2R.exe", environment: "battlenet",
        launch: .battleNet, minimumMacOS: [26, 5], presentation: Presentation(accentHex: "8E1B12"))

    public static let rdr2 = GameProfile(
        id: "rdr2", title: "Red Dead Redemption 2", steamAppID: "1174180",
        installFolder: "Red Dead Redemption 2", executableRelativePath: "RDR2.exe", environment: "rockstar",
        windowsSteamPath: true, presentation: Presentation(accentHex: "B22222", heroFocus: p(0.6, 0.4)))

    public static let sanAndreas = GameProfile(
        id: "san-andreas-de", title: "GTA San Andreas: The Definitive Edition", steamAppID: "1547000",
        installFolder: "GTA San Andreas - The Definitive Edition",
        executableRelativePath: "Gameface/Binaries/Win64/SanAndreas.exe", environment: "rockstar",
        steamArgs: ["-no-cef-sandbox"], presentation: Presentation(accentHex: "E67E22", heroFocus: p(0.6, 0.4)))

    public static let gta5 = GameProfile(
        id: "gta5-enhanced", title: "Grand Theft Auto V Enhanced", steamAppID: "3240220",
        installFolder: "Grand Theft Auto V Enhanced", executableRelativePath: "GTA5_Enhanced.exe", environment: "gta5",
        windowsSteamPath: true, gameArgs: ["-nobattleye", "-disableSpatialAudioClient"],
        presentation: Presentation(accentHex: "2E8B57", heroFocus: p(0.6, 0.4)))

    public static let all: [GameProfile] = [
        .aoe4, .cs2, .aoe3, .aomRetold, .coh3, .zeroHour, .redAlert2, .heroes3,
        .diablo4, .poe2, .hogwarts, .witcher3, .eldenRing,
        .skyrim, .overwatch, .diablo4BattleNet, .diablo2Resurrected, .rdr2, .sanAndreas, .gta5,
    ]
}
