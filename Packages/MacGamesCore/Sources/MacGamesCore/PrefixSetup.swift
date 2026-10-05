import Foundation

public enum PrefixSetup {
    public struct Copy: Sendable, Equatable {
        public let from: URL
        public let to: URL
        public init(from: URL, to: URL) { self.from = from; self.to = to }
    }

    /// Wine links Documents, Desktop and similar folders to the Mac home.
    /// Real empty folders keep the game away from the user's own files.
    public static func replaceUserLinks(prefix: URL) throws {
        let fm = FileManager.default
        let users = prefix.appendingPathComponent("drive_c/users")
        for user in (try? fm.contentsOfDirectory(at: users, includingPropertiesForKeys: nil)) ?? [] {
            for item in (try? fm.contentsOfDirectory(at: user, includingPropertiesForKeys: [.isSymbolicLinkKey])) ?? [] {
                guard (try? item.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true else { continue }
                try fm.removeItem(at: item)
                try fm.createDirectory(at: item, withIntermediateDirectories: false)
            }
        }
    }

    public static func graphicsCopies(for paths: GamePaths) -> [Copy] {
        let windows = paths.prefix.appendingPathComponent("drive_c/windows")
        switch paths.profile.graphics {
        case .d3dmetal:
            let source = paths.frameworks.appendingPathComponent("renderer/d3dmetal/wine/x86_64-windows")
            return ["dxgi", "d3d11", "d3d12", "atidxx64"].map {
                Copy(from: source.appendingPathComponent("\($0).dll"), to: windows.appendingPathComponent("system32/\($0).dll"))
            }
        case .dxmt:
            let lib = paths.engine.appendingPathComponent("lib/wine")
            return [Copy(from: lib.appendingPathComponent("x86_64-windows/winemetal.dll"), to: windows.appendingPathComponent("system32/winemetal.dll")),
                    Copy(from: lib.appendingPathComponent("i386-windows/winemetal.dll"), to: windows.appendingPathComponent("syswow64/winemetal.dll"))]
        }
    }

    public static func apply(_ copies: [Copy]) throws {
        let fm = FileManager.default
        for copy in copies {
            if fm.fileExists(atPath: copy.to.path) { try fm.removeItem(at: copy.to) }
            try fm.createDirectory(at: copy.to.deletingLastPathComponent(), withIntermediateDirectories: true)
            try fm.copyItem(at: copy.from, to: copy.to)
        }
    }

    /// Arguments for `wine` that route controllers through the SDL backend of winebus.
    public static let wineBusCommands: [[String]] = ["Enable SDL", "DisableHidraw", "Map Controllers"].map {
        ["reg", "add", "HKLM\\System\\CurrentControlSet\\Services\\WineBus", "/v", $0, "/t", "REG_DWORD", "/d", "1", "/f"]
    }
}
