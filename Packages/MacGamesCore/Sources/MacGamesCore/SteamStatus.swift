import Foundation

/// The account the shared Steam client signed in with last.
public struct SteamAccount: Sendable, Equatable {
    public let personaName: String
    public let steamID64: UInt64

    /// The short account ID Steam uses for `userdata/<id>` folders.
    public var accountID: UInt64 { steamID64 >= 76561197960265728 ? steamID64 - 76561197960265728 : steamID64 }

    /// Reads Steam's `config/loginusers.vdf`.
    public static func parse(_ text: String) -> SteamAccount? {
        var users: [[String: String]] = []
        var current: [String: String]?
        var depth = 0
        var lastKey = ""
        for raw in text.split(whereSeparator: \.isNewline) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line == "{" { depth += 1; if depth == 2 { current = ["__id": lastKey] }; continue }
            if depth == 1, line.hasPrefix("\"") { lastKey = line.trimmingCharacters(in: CharacterSet(charactersIn: "\"")) }
            if line == "}" { if depth == 2, let user = current { users.append(user); current = nil }; depth -= 1; continue }
            guard depth == 2 else { continue }
            let parts = line.split(separator: "\"", omittingEmptySubsequences: false)
            if parts.count >= 5 { current?[String(parts[1])] = String(parts[3]) }
        }
        guard let chosen = users.first(where: { $0["MostRecent"] == "1" }) ?? users.last,
              let name = chosen["PersonaName"] else { return nil }
        return SteamAccount(personaName: name, steamID64: chosen["__id"].flatMap { UInt64($0) } ?? 0)
    }

    public static func current(_ paths: GamePaths) -> SteamAccount? {
        let url = paths.steamDir.appendingPathComponent("config/loginusers.vdf")
        return (try? String(contentsOf: url, encoding: .utf8)).flatMap(parse)
    }
}

extension AppManifest {
    /// 0...1 while Steam installs or updates the game; `nil` when nothing is pending.
    public var downloadProgress: Double? { downloadProgress(stagedBytes: 0) }

    /// Steam rewrites the manifest's byte counters only now and then, but the
    /// staging folder grows as data arrives, so the larger of the two wins.
    public func downloadProgress(stagedBytes: UInt64) -> Double? {
        guard let flags = self["StateFlags"].flatMap({ Int($0) }) else { return nil }
        let installed = flags & 4 != 0, updating = flags & (2 | 1024) != 0
        if installed && !updating { return nil }
        let done = self["BytesDownloaded"].flatMap { Double($0) } ?? 0
        let total = self["BytesToDownload"].flatMap { Double($0) } ?? 0
        let toStage = self["BytesToStage"].flatMap { Double($0) } ?? 0
        let fromManifest = total > 0 ? done / total : 0
        let fromDisk = toStage > 0 ? Double(stagedBytes) / toStage : 0
        return min(1, max(fromManifest, fromDisk))
    }

    /// Space the files in `folder` take on disk. Steam reserves the full size
    /// of each file up front as a sparse file, so only written data counts.
    public static func stagedBytes(in folder: URL) -> UInt64 {
        guard let walker = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: [.totalFileAllocatedSizeKey]) else { return 0 }
        var total: UInt64 = 0
        for case let url as URL in walker {
            total += UInt64((try? url.resourceValues(forKeys: [.totalFileAllocatedSizeKey]).totalFileAllocatedSize) ?? 0)
        }
        return total
    }
}

/// What the library shows about the shared Steam client.
public struct SteamStatus: Sendable, Equatable {
    public struct Download: Sendable, Equatable {
        public let profile: GameProfile
        public let progress: Double
    }

    public let account: SteamAccount?
    public let downloads: [Download]

    public init(account: SteamAccount?, downloads: [Download]) {
        self.account = account
        self.downloads = downloads
    }

    /// Live install or update progress of one game; `nil` when nothing is pending.
    public static func downloadProgress(_ paths: GamePaths) -> Double? {
        let staging = paths.steamapps.appendingPathComponent("downloading/\(paths.profile.steamAppID)")
        return AppManifest(contentsOf: paths.appManifest)?.downloadProgress(stagedBytes: AppManifest.stagedBytes(in: staging))
    }

    public static func read(root: URL, environment: GameEnvironment = .steam) -> SteamStatus {
        guard let first = environment.games.first else { return SteamStatus(account: nil, downloads: []) }
        let any = GamePaths(profile: first, root: root)
        let downloads = environment.games.filter { $0.launch != .battleNet }.compactMap { profile -> Download? in
            let paths = GamePaths(profile: profile, root: root)
            guard let progress = downloadProgress(paths) else { return nil }
            return Download(profile: profile, progress: progress)
        }
        return SteamStatus(account: SteamAccount.current(any), downloads: downloads)
    }
}
