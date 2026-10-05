import Darwin
import Foundation

/// Top-level keys of a Steam `appmanifest_<id>.acf` (Valve KeyValues text).
public struct AppManifest: Sendable {
    public let values: [String: String]

    public init(text: String) {
        var values: [String: String] = [:]
        var depth = 0
        for raw in text.split(whereSeparator: \.isNewline) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line == "{" { depth += 1; continue }
            if line == "}" { depth -= 1; continue }
            guard depth == 1 else { continue }
            let parts = line.split(separator: "\"", omittingEmptySubsequences: false)
            // "key"<ws>"value" splits into ["", key, ws, value, ""]
            if parts.count >= 5 { values[String(parts[1])] = String(parts[3]) }
        }
        self.values = values
    }

    public init?(contentsOf url: URL) {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        self.init(text: text)
    }

    public subscript(key: String) -> String? { values[key] }

    /// StateFlags is a bit field; bit 4 ("fully installed") stays set while an update waits.
    public func isFullyInstalled(_ profile: GameProfile) -> Bool {
        guard let flags = self["StateFlags"].flatMap({ Int($0) }) else { return false }
        return self["appid"] == profile.steamAppID && self["installdir"] == profile.installFolder && flags & 4 != 0
    }
}

/// Reads Steam's `logs/gameprocess_log.txt` to tell whether the game process is alive.
public enum GameProcessLog {
    public static func isRunning(_ profile: GameProfile, log: String) -> Bool {
        var tracked: String?
        let id = profile.steamAppID
        for line in log.split(whereSeparator: \.isNewline) {
            if line.contains("AppID \(id) adding PID "), line.contains(profile.executableName) {
                let tail = line.components(separatedBy: "adding PID ").last ?? ""
                tracked = tail.components(separatedBy: " ").first
            }
            if line.contains("Remove \(id) from running list") { tracked = nil }
            if let pid = tracked, line.contains("AppID \(id) no longer tracking PID \(pid),") { tracked = nil }
        }
        return tracked != nil
    }

    public static func url(_ paths: GamePaths) -> URL { paths.steamDir.appendingPathComponent("logs/gameprocess_log.txt") }

    /// Reads at most the last 128 KiB, and nothing from before the current Steam
    /// session: a session ended with `wineserver -k` never logs the game's exit.
    public static func isRunning(_ profile: GameProfile, paths: GamePaths) -> Bool {
        guard let handle = try? FileHandle(forReadingFrom: url(paths)) else { return false }
        defer { try? handle.close() }
        guard let size = try? handle.seekToEnd() else { return false }
        let sessionStart = SteamSession.load(paths)?.gameLogOffset ?? 0
        try? handle.seek(toOffset: max(sessionStart <= size ? sessionStart : 0, size > 131_072 ? size - 131_072 : 0))
        let data = (try? handle.readToEnd()) ?? Data()
        return isRunning(profile, log: String(decoding: data, as: UTF8.self))
    }
}

@_silgen_name("proc_listallpids") private func proc_listallpids(_ buffer: UnsafeMutableRawPointer?, _ size: Int32) -> Int32
@_silgen_name("proc_pidpath") private func proc_pidpath(_ pid: Int32, _ buffer: UnsafeMutableRawPointer?, _ size: UInt32) -> Int32

public enum LiveProcesses {
    /// Executable paths of live processes whose binary is inside `folder`.
    public static func paths(under folder: URL) -> [URL] {
        var pids = [Int32](repeating: 0, count: 8192)
        let count = pids.withUnsafeMutableBytes { proc_listallpids($0.baseAddress, Int32($0.count)) }
        guard count > 0 else { return [] }
        let prefix = folder.resolvingSymlinksInPath().path + "/"
        var found: [URL] = []
        for pid in pids.prefix(Int(min(count, Int32(pids.count)))) where pid > 0 {
            var buffer = [CChar](repeating: 0, count: 4096)
            let length = buffer.withUnsafeMutableBytes { proc_pidpath(pid, $0.baseAddress, 4096) }
            guard length > 0 else { continue }
            let path = URL(fileURLWithPath: String(decoding: buffer.prefix(Int(length)).map { UInt8(bitPattern: $0) }, as: UTF8.self))
                .resolvingSymlinksInPath()
            if path.path.hasPrefix(prefix) { found.append(path) }
        }
        return found
    }
}
