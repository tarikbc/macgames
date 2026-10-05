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

    /// The graphics libraries an environment's prefix needs, in the order they are copied.
    public static func graphicsCopies(for paths: GamePaths) -> [Copy] {
        let windows = paths.prefix.appendingPathComponent("drive_c/windows")
        let lib = paths.engine.appendingPathComponent("lib/wine")
        func to(_ folder: String, _ name: String) -> URL { windows.appendingPathComponent("\(folder)/\(name).dll") }
        var copies: [Copy] = []
        for step in paths.environment.prefixDLLs {
            switch step {
            case .d3dmetalSystem32:
                // An environment that pins its own D3DMetal still takes atidxx64 from the template.
                let own = paths.d3dmetal.appendingPathComponent("wine/x86_64-windows")
                let template = paths.frameworks.appendingPathComponent("renderer/d3dmetal/wine/x86_64-windows")
                for name in ["dxgi", "d3d11", "d3d12"] { copies.append(Copy(from: own.appendingPathComponent("\(name).dll"), to: to("system32", name))) }
                copies.append(Copy(from: template.appendingPathComponent("atidxx64.dll"), to: to("system32", "atidxx64")))
            case .winemetal:
                copies.append(Copy(from: lib.appendingPathComponent("x86_64-windows/winemetal.dll"), to: to("system32", "winemetal")))
                copies.append(Copy(from: lib.appendingPathComponent("i386-windows/winemetal.dll"), to: to("syswow64", "winemetal")))
            case .engineDXMT:
                for name in ["dxgi", "d3d11", "d3d10core", "winemetal"] {
                    copies.append(Copy(from: lib.appendingPathComponent("x86_64-windows/\(name).dll"), to: to("system32", name)))
                    copies.append(Copy(from: lib.appendingPathComponent("i386-windows/\(name).dll"), to: to("syswow64", name)))
                }
            case .engineDXMT32:
                for name in ["dxgi", "d3d11", "d3d10core", "winemetal"] {
                    copies.append(Copy(from: lib.appendingPathComponent("i386-windows/\(name).dll"), to: to("syswow64", name)))
                }
            case .rockstarWineD3D:
                let renderer = paths.pack("rockstar").appendingPathComponent("RockstarRenderer")
                for name in ["d3d11", "dxgi", "d3d10core"] {
                    copies.append(Copy(from: renderer.appendingPathComponent("\(name).dll"), to: to("system32", name)))
                }
            }
        }
        // A later step replaces an earlier one's file; keep the last copy per target.
        var seen = Set<URL>()
        return Array(copies.reversed().filter { seen.insert($0.to).inserted }.reversed())
    }

    /// Points the environment's root drives at its own root, so a game sees no Mac files.
    public static func mapRootDrives(paths: GamePaths) throws {
        let fm = FileManager.default
        let devices = paths.prefix.appendingPathComponent("dosdevices")
        for letter in paths.environment.rootDrives {
            let link = devices.appendingPathComponent("\(letter):")
            if (try? fm.destinationOfSymbolicLink(atPath: link.path)) != nil || fm.fileExists(atPath: link.path) {
                try fm.removeItem(at: link)
            }
            try fm.createSymbolicLink(atPath: link.path, withDestinationPath: paths.root.path)
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
