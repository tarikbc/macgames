import Foundation

/// CS2 keeps its display mode in `cs2_video.txt` per Steam account. Borderless
/// fullscreen-windowed at the display size avoids exclusive fullscreen, which
/// Wine's Mac driver shows with a title bar.
public enum CS2VideoConfig {
    static func values(width: Int, height: Int) -> [(String, String)] {
        [("setting.fullscreen", "0"), ("setting.coop_fullscreen", "1"), ("setting.nowindowborder", "1"),
         ("setting.fullscreen_min_on_focus_loss", "0"), ("setting.defaultres", String(width)),
         ("setting.defaultresheight", String(height))]
    }

    /// Returns `text` with the display keys set, adding the ones it lacks.
    public static func apply(to text: String?, width: Int, height: Int) -> String {
        var lines = (text ?? "\"video.cfg\"\n{\n\t\"Version\"\t\t\"16\"\n}\n").components(separatedBy: "\n")
        for (key, value) in values(width: width, height: height) {
            let entry = "\t\"\(key)\"\t\t\"\(value)\""
            if let i = lines.firstIndex(where: { $0.trimmingCharacters(in: .whitespaces).hasPrefix("\"\(key)\"") }) {
                lines[i] = entry
            } else if let close = lines.lastIndex(where: { $0.trimmingCharacters(in: .whitespaces) == "}" }) {
                lines.insert(entry, at: close)
            }
        }
        return lines.joined(separator: "\n")
    }

    public static func url(paths: GamePaths, account: SteamAccount) -> URL {
        paths.steamDir.appendingPathComponent("userdata/\(account.accountID)/730/local/cfg/cs2_video.txt")
    }
}
