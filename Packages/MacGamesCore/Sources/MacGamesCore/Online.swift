import Foundation

/// Community online clients: GeneralsOnline for Zero Hour, CnCNet for Red Alert 2.
public enum Online {
    /// The online clients are .NET programs and need their own environment.
    public static func environment(for profile: GameProfile, base: [String: String], paths: GamePaths) -> [String: String] {
        var env = base
        switch profile.online {
        case .generalsOnline:
            env["WINEDLLOVERRIDES"] = env["WINEDLLOVERRIDES"]?.replacingOccurrences(of: "mscoree,mshtml=;", with: "mscoree=b;mshtml=;")
            env["DOTNET_PELoader_DisableMapping"] = "1"
        case .cncnet:
            for key in env.keys where ["DOTNET_", "DXMT_", "CS2_", "X87_", "AOE2_"].contains(where: key.hasPrefix) { env[key] = nil }
            env["WINEDLLPATH"] = paths.engine.appendingPathComponent("lib/wine").path
            env["WINEDLLOVERRIDES"] = "winemenubuilder.exe=;mshtml=;gameoverlayrenderer,gameoverlayrenderer64="
            env["DOTNET_MULTILEVEL_LOOKUP"] = "0"
        case nil:
            break
        }
        return env
    }
}

public enum CRC32 {
    static let table: [UInt32] = (0..<256).map { n in
        (0..<8).reduce(UInt32(n)) { c, _ in c & 1 == 1 ? 0xEDB88320 ^ (c >> 1) : c >> 1 }
    }

    public static func checksum(_ data: Data) -> UInt32 {
        ~data.reduce(~UInt32(0)) { table[Int(($0 ^ UInt32($1)) & 0xFF)] ^ ($0 >> 8) }
    }
}

public enum GeneralsOnline {
    public struct Update: Equatable, Sendable {
        public let url: URL
        public let size: Int
    }

    public static let setup = Download(
        url: URL(string: "https://cdn.playgenerals.online/GeneralsOnline_setup_092226_QFE2.exe")!,
        sha256: "307d27ac21cd398259dec4e95f4eb85f90d571bdc0efe063a65734386896317b",
        fileName: "GeneralsOnline_setup_092226_QFE2.exe")
    static let versionCheck = URL(string: "https://api.playgenerals.online/env/prod/contract/1/VersionCheck")!

    public static func versionCheckBody(crc: UInt32) -> Data {
        Data(#"{"execrc":\#(crc),"ver":1,"netver":1,"servicesver":1}"#.utf8)
    }

    /// Reads the server's answer. Only an official patcher name on the official CDN is accepted.
    public static func update(from response: Data) throws -> Update? {
        guard let json = try JSONSerialization.jsonObject(with: response) as? [String: Any],
              let result = json["result"] as? Int else { throw SetupError("GeneralsOnline sent an answer MacGames does not understand.") }
        if result == 0 { return nil }
        guard result == 2, let name = json["patcher_name"] as? String,
              name.range(of: #"^GeneralsOnline_update_[0-9]{6}(?:_QFE[0-9]{1,3})?\.exe$"#, options: .regularExpression) != nil,
              let size = json["patcher_size"] as? Int, (1024...(512 << 20)).contains(size) else {
            throw SetupError("GeneralsOnline offered an update MacGames will not run.")
        }
        return Update(url: URL(string: "https://cdn.playgenerals.online/" + name)!, size: size)
    }
}

public enum CnCNet {
    public static let package = Download(
        url: URL(string: "https://github.com/CnCNet/cncnet-yr-client-package/releases/download/yr-9.3.3/package_9.3.3.zip")!,
        sha256: "78889e7adb9b2961b3f81c388bce728bebbd91817e5d68d5a348bb67804d74e7", fileName: "cncnet-package_9.3.3.zip")
    public static let dotnet = [
        Download(url: URL(string: "https://builds.dotnet.microsoft.com/dotnet/Runtime/8.0.31/dotnet-runtime-8.0.31-win-x64.zip")!,
                 sha256: "7deabbefdc83e378b343c551fe447b86002680eea91355b1f6f81d0c9ab0dcaa", fileName: "dotnet-runtime-8.0.31-win-x64.zip"),
        Download(url: URL(string: "https://builds.dotnet.microsoft.com/dotnet/WindowsDesktop/8.0.31/windowsdesktop-runtime-8.0.31-win-x64.zip")!,
                 sha256: "9bb1d8957aab6ea0e1d5972e4673ad6ce2fbc0b15fe007879cd53fb477835a7a", fileName: "windowsdesktop-runtime-8.0.31-win-x64.zip"),
    ]
    /// The game's own programs, settings and renderer stay as they are.
    static let protected: Set<String> = ["ra2.exe", "game.exe", "ra2md.exe", "gamemd.exe", "ra2.ini", "ra2md.ini", "ddraw.dll", "ddraw.ini"]

    public static func isSafeEntry(_ path: String) -> Bool {
        !path.hasPrefix("/") && !path.split(separator: "/").contains("..")
    }

    /// Copies the client package into the game folder, backing up any file it changes.
    public static func merge(package: URL, into game: URL, backups: URL) throws {
        let fm = FileManager.default
        guard let walker = fm.enumerator(at: package, includingPropertiesForKeys: [.isRegularFileKey]) else { return }
        let base = package.standardizedFileURL.path + "/"
        for case let file as URL in walker where (try? file.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true {
            let relative = String(file.standardizedFileURL.path.dropFirst(base.count))
            guard isSafeEntry(relative), !protected.contains(relative.lowercased()) else { continue }
            let target = game.appendingPathComponent(relative)
            if fm.fileExists(atPath: target.path) {
                if (try? Data(contentsOf: target)) == (try? Data(contentsOf: file)) { continue }
                let backup = backups.appendingPathComponent(relative)
                if !fm.fileExists(atPath: backup.path) {
                    try fm.createDirectory(at: backup.deletingLastPathComponent(), withIntermediateDirectories: true)
                    try fm.copyItem(at: target, to: backup)
                }
                try fm.removeItem(at: target)
            }
            try fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            try fm.copyItem(at: file, to: target)
        }
    }

    /// Adds MacGames's DirectDraw renderer to the client's renderer list.
    public static func registerRenderer(in text: String) -> String {
        var t = INIFile.set(in: text, section: "Renderers", key: "MacGames", value: "MACGAMES_RA2")
        for (key, value) in [("UIName", "MacGames (OpenGL)"), ("DLLName", "macgames-ra2-ddraw.dll"), ("ConfigFileName", "ddraw.ini"),
                             ("ResConfigFileName", "macgames-ra2-ddraw.ini"), ("WindowedModeSection", "ddraw"),
                             ("WindowedModeKey", "windowed"), ("BorderlessWindowedModeKey", "border"),
                             ("IsBorderlessWindowedModeKeyReversed", "true"), ("UseQres", "false")] {
            t = INIFile.set(in: t, section: "MACGAMES_RA2", key: key, value: value)
        }
        return t
    }
}

// MARK: - Runtime

extension GameRuntime {
    var dotnet: URL { paths.gameData.appendingPathComponent("cncnet-dotnet8") }
    var cncnetReady: URL { paths.gameData.appendingPathComponent("cncnet-ready") }
    var generalsOnlineClient: URL { paths.installDir.appendingPathComponent("GeneralsOnlineZH.exe") }

    /// The online client is installed and can start.
    public var onlineReady: Bool {
        switch profile.online {
        case .generalsOnline: fm.fileExists(atPath: generalsOnlineClient.path)
        case .cncnet: fm.fileExists(atPath: cncnetReady.path) && fm.fileExists(atPath: dotnet.appendingPathComponent("dotnet.exe").path)
        case nil: false
        }
    }

    func onlineEnvironment() throws -> [String: String] {
        Online.environment(for: profile, base: try launchEnvironment(), paths: paths)
    }

    public func setupOnline() throws {
        guard state() == .ready || state() == .running else { throw SetupError("Install \(profile.title) in Steam first.") }
        switch profile.online {
        case .generalsOnline: try setupGeneralsOnline()
        case .cncnet: try setupCnCNet()
        case nil: throw SetupError("\(profile.title) has no online client in MacGames.")
        }
    }

    public func playOnline(_ context: LaunchContext) throws {
        if !onlineReady { try setupOnline() }
        try GameFiles.prepare(profile, paths: paths, runtime: runtime, context: context)
        try ensureSteamReady()
        let env = try onlineEnvironment()
        switch profile.online {
        case .generalsOnline:
            try importRegistry([Self.avalonSoftware], environment: env)
            do { try updateGeneralsOnline(environment: env) } catch { progress("GeneralsOnline update check skipped: \(error)") }
            try startDetached([paths.windowsPath(generalsOnlineClient)], environment: env, workingDirectory: paths.installDir,
                              log: "zero-hour-online.log")
        case .cncnet:
            let md = paths.installDir.appendingPathComponent("RA2MD.INI")
            if let text = try? String(contentsOf: md, encoding: .utf8), text.lowercased().contains("borderlesswindowedclient=true") {
                var t = INIFile.set(in: text, section: "Video", key: "ClientResolutionX", value: String(context.width))
                t = INIFile.set(in: t, section: "Video", key: "ClientResolutionY", value: String(context.height))
                try t.write(to: md, atomically: true, encoding: .utf8)
            }
            let client = paths.installDir.appendingPathComponent("Resources/BinariesNET8/OpenGL/clientogl.dll")
            try startDetached([dotnet.appendingPathComponent("dotnet.exe").path, paths.windowsPath(client)], environment: env,
                              workingDirectory: paths.installDir, log: "red-alert2-online.log")
        case nil:
            break
        }
        progress("The \(profile.title) online client is starting.")
    }

    /// The client's WPF windows draw blank with hardware rendering in Wine.
    static let avalonSoftware = RegistryValue(key: #"HKEY_CURRENT_USER\Software\Microsoft\Avalon.Graphics"#,
                                              name: "DisableHWAcceleration", value: .dword(1))

    func setupGeneralsOnline() throws {
        let env = try onlineEnvironment()
        progress("Getting GeneralsOnline…")
        let installer = try downloader.fetch(GeneralsOnline.setup)
        let dir = paths.windowsPath(paths.installDir)
        try importRegistry([RegistryValue(key: #"HKEY_CURRENT_USER\Software\GeneralsOnline"#, name: "InstallPath", value: .string(dir)),
                            Self.avalonSoftware], environment: env)
        progress("Finish the GeneralsOnline installer. Keep the folder it suggests.")
        try runWine([installer.path, "/DIR=\(dir)", "/NORESTART"], environment: env, timeout: 1800)
        guard fm.fileExists(atPath: generalsOnlineClient.path) else {
            throw SetupError("The GeneralsOnline installer finished, but its client is missing. Run the online setup again.")
        }
    }

    func updateGeneralsOnline(environment env: [String: String]) throws {
        let client = paths.installDir.appendingPathComponent("GeneralsOnlineZH_60.exe")
        guard let data = try? Data(contentsOf: client) else { return }
        var request = URLRequest(url: GeneralsOnline.versionCheck, timeoutInterval: 15)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = GeneralsOnline.versionCheckBody(crc: CRC32.checksum(data))
        guard let update = try GeneralsOnline.update(from: try Self.send(request)) else { return }
        progress("Updating GeneralsOnline…")
        let patcher = try downloader.fetch(Download(url: update.url, sha256: nil, fileName: update.url.lastPathComponent))
        let header = try FileHandle(forReadingFrom: patcher).read(upToCount: 2)
        guard header == Data("MZ".utf8), (try? fm.attributesOfItem(atPath: patcher.path)[.size] as? Int) == update.size else {
            throw SetupError("The GeneralsOnline update did not verify.")
        }
        try runWine([patcher.path, "/VERYSILENT", "/SUPPRESSMSGBOXES", "/NORESTART", "/DIR=\(paths.windowsPath(paths.installDir))"],
                    environment: env, timeout: 1800)
    }

    static func send(_ request: URLRequest) throws -> Data {
        final class Box: @unchecked Sendable { var result: Result<Data, any Error>? }
        let box = Box(), done = DispatchSemaphore(value: 0)
        URLSession.shared.dataTask(with: request) { data, response, error in
            defer { done.signal() }
            if let error { box.result = .failure(error); return }
            guard (response as? HTTPURLResponse)?.statusCode == 200, let data, data.count < 65536 else {
                box.result = .failure(SetupError("The server did not answer as expected.")); return
            }
            box.result = .success(data)
        }.resume()
        done.wait()
        return try box.result!.get()
    }

    func setupCnCNet() throws {
        let unzip = URL(fileURLWithPath: "/usr/bin/unzip"), ditto = URL(fileURLWithPath: "/usr/bin/ditto")
        func extract(_ zip: URL, to target: URL) throws {
            let entries = try runner.run(unzip, ["-Z1", zip.path], timeout: 60).split(whereSeparator: \.isNewline).map(String.init)
            guard entries.allSatisfy(CnCNet.isSafeEntry) else { throw SetupError("\(zip.lastPathComponent) holds unsafe paths.") }
            try runner.run(ditto, ["-x", "-k", zip.path, target.path], timeout: 300)
        }
        progress("Getting the CnCNet client…")
        let package = try downloader.fetch(CnCNet.package)
        let stage = paths.gameData.appendingPathComponent("cncnet-staging-\(UUID().uuidString)")
        try fm.createDirectory(at: stage, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: stage) }
        try extract(package, to: stage)
        let packageRoot = fm.fileExists(atPath: stage.appendingPathComponent("package").path) ? stage.appendingPathComponent("package") : stage
        try CnCNet.merge(package: packageRoot, into: paths.installDir, backups: paths.gameData.appendingPathComponent("backups"))

        progress("Getting .NET 8 for the CnCNet client…")
        try fm.createDirectory(at: dotnet, withIntermediateDirectories: true)
        for item in CnCNet.dotnet { try extract(try downloader.fetch(item), to: dotnet) }

        let files = runtime.gameFiles("red-alert2"), resources = paths.installDir.appendingPathComponent("Resources")
        for (from, to) in [("ddraw.dll", "macgames-ra2-ddraw.dll"), ("ddraw.ini", "macgames-ra2-ddraw.ini")] {
            let target = resources.appendingPathComponent(to)
            if fm.fileExists(atPath: target.path) { try fm.removeItem(at: target) }
            try fm.copyItem(at: files.appendingPathComponent(from), to: target)
        }
        try GameFiles.edit(resources.appendingPathComponent("Renderers.ini")) { CnCNet.registerRenderer(in: $0) }
        try GameFiles.edit(paths.installDir.appendingPathComponent("RA2MD.INI")) { text in
            let t = INIFile.set(in: text, section: "Compatibility", key: "Renderer", value: "MACGAMES_RA2")
            return INIFile.set(in: t, section: "Video", key: "BorderlessWindowedClient", value: "True", onlyIfMissing: true)
        }
        fm.createFile(atPath: cncnetReady.path, contents: nil)
    }
}
