import CoreGraphics
import Foundation

/// Overwatch's display setup on Recall's engine: the game's resolution, its settings file and
/// DXMT's fullscreen canvas, which must all agree.
public enum OverwatchDisplay {
    /// DXMT's settings for this launch: the engine's profile with the canvas set to the game's size.
    static func config(_ paths: GamePaths) -> URL { paths.gameData.appendingPathComponent("dxmt.conf") }

    /// The main display, where the game opens, in points; `nil` without a display.
    static func mainDisplay() -> Size? {
        guard let mode = CGDisplayCopyDisplayMode(CGMainDisplayID()) else { return nil }
        return Size(width: mode.width, height: mode.height)
    }

    /// The game's settings file in the prefix's one Windows user folder: the file that exists, or
    /// where the game will make it. `nil` when there is more than one user folder to choose from.
    static func settingsFile(_ paths: GamePaths) -> URL? {
        let shared = ["public", "default", "default user", "all users"]
        let users = GameFiles.userFolders(paths).filter { !shared.contains($0.lastPathComponent.lowercased()) }
        let files = users.map { $0.appendingPathComponent("Documents/Overwatch/Settings/Settings_v0.ini") }
        let existing = files.filter { FileManager.default.fileExists(atPath: $0.path) }
        if existing.count == 1 { return existing[0] }
        return existing.isEmpty && files.count == 1 ? files[0] : nil
    }

    static func record(_ paths: GamePaths) -> URL { paths.gameData.appendingPathComponent("display.json") }
}

extension OverwatchDisplay {
    public struct Size: Sendable, Equatable, Codable {
        public let width: Int, height: Int
        public init(width: Int, height: Int) { self.width = width; self.height = height }
    }

    /// What MacGames chose and wrote into the game's settings at the last launch, and the
    /// graphics card the game had recorded then.
    public struct Record: Sendable, Equatable, Codable {
        public var chosen: Size, wrote: Size, gpu: String
    }

    /// The six resolutions Recall offers, in 16:9 and 16:10.
    static let resolutions = [Size(width: 1920, height: 1080), Size(width: 1920, height: 1200), Size(width: 2560, height: 1440),
                              Size(width: 2560, height: 1600), Size(width: 3840, height: 2160), Size(width: 3840, height: 2400)]

    /// Recall's launch values for `[Render.13]`; the size keys take the launch's resolution.
    static let launchPreferences = [
        "UseCustomWorldScale": "1", "DynamicRenderScale": "0", "FullscreenWindow": "0", "FullscreenWindowEnabled": "0",
        "WindowedFullscreen": "0", "WindowMode": "0", "FullScreenRefresh": "120", "WindowedPosX": "100", "WindowedPosY": "100",
    ]

    /// Recall's starting graphics, written once and only where the file has no value of its own.
    static let baselinePreferences = [
        "FrameRateCap": "600", "UseCustomFrameRates": "1", "GFXPresetLevel": "1", "PhysicsQuality": "3",
        "VerticalSyncEnabled": "0", "ShowFPSCounter": "1", "ShowRTT": "1", "WindowedRefresh": "120",
    ]

    static let section = "[Render.13]"

    static func trimmed<S: StringProtocol>(_ line: S) -> String {
        line.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "\u{FEFF}")))
    }

    static func key(of line: String) -> String {
        trimmed(line.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)[0])
    }

    /// A key's value in the sections whose header starts with `section`; `nil` when it is
    /// missing or listed twice with different values.
    static func setting(_ text: String, section: String, key: String) -> String? {
        var value: String?, inside = false
        // Split on "\n" alone: Swift keeps "\r\n" as one character.
        for raw in text.components(separatedBy: "\n") {
            let line = trimmed(raw)
            if line.hasPrefix("[") { inside = line.hasPrefix(section); continue }
            guard inside, let equals = line.firstIndex(of: "=") else { continue }
            guard trimmed(line[..<equals]) == key else { continue }
            var right = trimmed(line[line.index(after: equals)...])
            if right.count >= 2, right.hasPrefix("\""), right.hasSuffix("\"") { right = String(right.dropFirst().dropLast()) }
            if let value, value != right { return nil }
            value = right
        }
        return value
    }

    /// The graphics card the game last recorded (`[GPU.*]`), or "" without one.
    static func gpu(_ text: String) -> String {
        let name = setting(text, section: "[GPU.", key: "GPUName"), vendor = setting(text, section: "[GPU.", key: "GPUVenderID")
        return name == nil && vendor == nil ? "" : "\(name ?? "")|\(vendor ?? "")"
    }

    static func isGameResolution(_ size: Size) -> Bool {
        (640...16384).contains(size.width) && (480...16384).contains(size.height)
    }

    /// The fullscreen resolution in the game's settings, when it is a usable one.
    static func gameResolution(_ text: String) -> Size? {
        func pixels(_ key: String) -> Int? {
            guard let value = setting(text, section: "[Render.", key: key), (3...5).contains(value.count),
                  value.allSatisfy(\.isASCII), value.allSatisfy(\.isNumber) else { return nil }
            return Int(value)
        }
        guard let width = pixels("FullScreenWidth"), let height = pixels("FullScreenHeight") else { return nil }
        let size = Size(width: width, height: height)
        return isGameResolution(size) ? size : nil
    }

    /// 1080p in the display's shape: 1920x1200 on a 16:10 screen such as a MacBook's, 1920x1080 on a wider one.
    static func screenDefault(display: Size) -> Size {
        Double(display.width) / Double(max(display.height, 1)) >= 1.69 ? Size(width: 1920, height: 1080) : Size(width: 1920, height: 1200)
    }

    /// The resolution for the next launch. A size in the game's settings other than the one MacGames
    /// wrote was chosen in the game, unless the game's record of the graphics card changed too: the
    /// game resets its display settings for a card it takes to be new, and that reset is set aside.
    static func next(settings: String?, record: Record?, display: Size) -> Size {
        let inGame = settings.flatMap(gameResolution)
        guard let record else { return inGame ?? screenDefault(display: display) }
        if let inGame, let settings, inGame != record.wrote {
            return gpu(settings) == record.gpu ? inGame : record.chosen
        }
        return record.chosen
    }

    /// The game's window must fit inside the display as Wine sees it (twice its size in points, in
    /// Retina mode). A larger choice is lowered for this launch to the largest of the six in the
    /// same shape that fits, or the largest that fits at all.
    static func fitted(_ size: Size, display: Size) -> Size {
        let maxWidth = display.width * 2, maxHeight = display.height * 2
        if size.width <= maxWidth && size.height <= maxHeight { return size }
        let fitting = resolutions.filter { $0.width <= maxWidth && $0.height <= maxHeight }
        let sameShape = fitting.filter { $0.width * size.height == $0.height * size.width }
        return (sameShape.isEmpty ? fitting : sameShape).max { $0.width * $0.height < $1.width * $1.height } ?? size
    }

    /// The game's settings with the launch values in `[Render.13]`, in the file's own line endings.
    /// With `seedBaseline`, Recall's starting graphics fill the keys the file does not have.
    static func apply(to text: String?, size: Size, seedBaseline: Bool) throws -> String {
        var original = text ?? section + "\n"
        let bom = original.hasPrefix("\u{FEFF}") ? "\u{FEFF}" : ""
        if !bom.isEmpty { original.removeFirst() }
        let newline = original.contains("\r\n") ? "\r\n" : "\n"
        var lines = original.components(separatedBy: newline)
        let headers = lines.indices.filter { trimmed(lines[$0]) == section }
        guard headers.count <= 1 else { throw SetupError("Overwatch's settings file has two \(section) sections, so it was left unchanged.") }
        if headers.isEmpty {
            let last = lines.last.map { trimmed($0).isEmpty } == true ? lines.count - 1 : lines.count
            lines.insert(section, at: last)
        }
        let start = (lines.firstIndex { trimmed($0) == section } ?? 0) + 1
        var end = lines[start...].firstIndex { trimmed($0).hasPrefix("[") } ?? lines.count
        while end > start, trimmed(lines[end - 1]).isEmpty { end -= 1 }

        func index(of name: String) throws -> Int? {
            let found = (start..<end).filter { key(of: lines[$0]) == name }
            guard found.count <= 1 else { throw SetupError("Overwatch's settings file lists \(name) twice, so it was left unchanged.") }
            return found.first
        }
        var values = launchPreferences
        values["FullScreenWidth"] = String(size.width); values["WindowedWidth"] = String(size.width)
        values["FullScreenHeight"] = String(size.height); values["WindowedHeight"] = String(size.height)
        if seedBaseline {
            for (name, value) in baselinePreferences where try index(of: name) == nil { values[name] = value }
        }
        for name in values.keys.sorted() {
            let line = "\(name) = \"\(values[name]!)\""
            if let i = try index(of: name) { lines[i] = line } else { lines.insert(line, at: end); end += 1 }
        }
        return bom + lines.joined(separator: newline)
    }

    /// DXMT's profile with its canvas set to the game's size. DXMT matches option names exactly,
    /// so only the profile's own spelling counts.
    static func canvas(_ profile: String, size: Size) throws -> String {
        var found = Set<String>()
        let lines = profile.components(separatedBy: "\n").map { line -> String in
            let name = key(of: line)
            switch name {
            case "dxgi.fullscreenCanvasWidth": found.insert(name); return "\(name) = \(size.width)"
            case "dxgi.fullscreenCanvasHeight": found.insert(name); return "\(name) = \(size.height)"
            default: return line
            }
        }
        guard found.count == 2 else { throw SetupError("The Overwatch engine's DXMT profile has no fullscreen canvas.") }
        return lines.joined(separator: "\n")
    }
}
