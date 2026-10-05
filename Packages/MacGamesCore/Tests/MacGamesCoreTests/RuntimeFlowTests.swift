import Foundation
import Testing
@testable import MacGamesCore

/// An environment whose `wine` and `wineserver` are shell scripts that log each call
/// to `<root>/calls.log` and fake the few side effects the flows look for.
struct FakeEnvironment {
    let dir: URL
    let runtime: GameRuntime
    var calls: [String] { (read(dir.appendingPathComponent("root/calls.log")) ?? "").split(separator: "\n").map(String.init) }
    let events = EventLog()

    final class EventLog: @unchecked Sendable {
        private let lock = NSLock()
        private var lines: [String] = []
        func add(_ line: String) { lock.lock(); lines.append(line); lock.unlock() }
        var all: [String] { lock.lock(); defer { lock.unlock() }; return lines }
    }

    static let wine = #"""
    #!/bin/sh
    root="$(cd "$(dirname "$0")/../.." && pwd)"
    printf 'wine %s\n' "$*" >> "$root/calls.log"
    steam="$WINEPREFIX/drive_c/Program Files (x86)/Steam"
    # A flag file makes one helper exit at once with an error.
    for helper in dismiss-dialog gpu-sync fit-window; do
      case "$1" in *"$helper.exe") [ -e "$root/fail-$helper" ] && exit 10 ;; esac
    done
    case "$*" in
      *"/S"*) mkdir -p "$steam" && : > "$steam/steam.exe" ;;
      *steam.exe*)
        # Steam appends to its log; flag files make it start a fresh log, or never finish starting.
        mkdir -p "$steam/logs"
        [ -e "$root/steam-truncates" ] && : > "$steam/logs/console_log.txt"
        [ -e "$root/steam-never-starts" ] || printf 'System startup time: 1\n' >> "$steam/logs/console_log.txt" ;;
      "reg import "*) cp "$WINEPREFIX/drive_c/$(basename "$(printf '%s' "$3" | tr '\\' '/')")" "$root/imported.reg" ;;
    esac
    exit 0
    """#

    static let wineserver = #"""
    #!/bin/sh
    root="$(cd "$(dirname "$0")/../.." && pwd)"
    printf 'wineserver %s\n' "$*" >> "$root/calls.log"
    exit 0
    """#

    /// Recall's graphics tool: logs its call, and fails when a flag file asks it to.
    static let pipelineTool = #"""
    #!/bin/sh
    root="$(cd "$(dirname "$0")/../../.." && pwd)"
    printf 'ow2-pipeline %s\n' "$*" >> "$root/calls.log"
    [ -e "$root/fail-ow2-pipeline" ] && exit 1
    exit 0
    """#

    init(_ profile: GameProfile) throws {
        dir = try makeTempDir("flow")
        let res = dir.appendingPathComponent("Runtime")
        try write(Self.wine, to: res.appendingPathComponent("Engine/bin/wine"))
        try write(Self.wineserver, to: res.appendingPathComponent("Engine/bin/wineserver"))
        for script in ["wine", "wineserver"] {
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: res.appendingPathComponent("Engine/bin/\(script)").path)
        }
        for overlay in profile.gameEnvironment.engineOverlays {
            try write(overlay, to: res.appendingPathComponent("Overlays/\(overlay)/marker"))
        }
        try write("{}", to: res.appendingPathComponent("dependency-links.json"))
        try write("test", to: res.appendingPathComponent("VERSION"))
        let log = events
        runtime = GameRuntime(profile: profile, root: dir.appendingPathComponent("root"),
                              runtime: RuntimeLayout(resources: res, helpers: dir.appendingPathComponent("Helpers")),
                              downloadCache: dir.appendingPathComponent("downloads"),
                              events: { if case .progress(let line) = $0 { log.add(line) } })
        // Packs count as installed, so no test downloads one.
        for pack in profile.gameEnvironment.packs {
            try write(Packs.pinned[pack] ?? pack, to: runtime.paths.pack(pack).appendingPathComponent(".macgames-pack"))
        }
        // An engine pack brings the same stand-in engine, a DXMT profile and Recall's graphics tool.
        if let pack = profile.gameEnvironment.enginePack {
            let folder = runtime.paths.pack(pack)
            for script in ["wine", "wineserver"] {
                let target = folder.appendingPathComponent("Engine/bin/\(script)")
                try write(script == "wine" ? Self.wine : Self.wineserver, to: target)
                try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: target.path)
            }
            try write("[Overwatch.exe]\ndxgi.fullscreenCanvasWidth = 1920\ndxgi.fullscreenCanvasHeight = 1200\n",
                      to: folder.appendingPathComponent("Engine/config/dxmt.conf"))
            try write("<plist/>", to: folder.appendingPathComponent("Engine/lib/wine/game-mode/Overwatch.app/Contents/Info.plist"))
            let tool = folder.appendingPathComponent("Helpers/ow2-pipeline")
            try write(Self.pipelineTool, to: tool)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: tool.path)
        }
        try EngineInstaller(runtime: runtime.runtime).install(for: runtime.paths)
        runtime.startupGrace = 0.2
        runtime.processes = { _ in ProcessSnapshot(entries: []) }
        try FileManager.default.createDirectory(at: runtime.paths.prefix.appendingPathComponent("drive_c"), withIntermediateDirectories: true)
        try write("runtime-v1", to: runtime.paths.runtimeReady)
        try write(profile.environment, to: runtime.paths.root.appendingPathComponent("macgames-environment"))
    }

    func installSteam() throws { try write("", to: runtime.paths.steamExe) }

    /// Makes the session look alive, with these Windows programs running in it.
    func live(_ programs: [String] = []) {
        let engine = runtime.paths.engine.resolvingSymlinksInPath().path
        let server = runtime.paths.wineserver.resolvingSymlinksInPath().path
        let entries = [ProcessSnapshot.Entry(pid: 1, path: server, argv0: server)]
            + programs.enumerated().map { .init(pid: Int32($0.offset + 2), path: engine + "/bin/wine-preloader", argv0: #"C:\Games\"# + $0.element) }
        runtime.processes = { _ in ProcessSnapshot(entries: entries) }
    }

    func cleanUp() { try? FileManager.default.removeItem(at: dir) }
}

@Suite(.serialized) struct RuntimeFlowTests {
    @Test func steamDoesNotRestartWhileAnotherGameOfItsEnvironmentRuns() throws {
        let env = try FakeEnvironment(.cs2); defer { env.cleanUp() }
        try env.installSteam()
        try SteamSession.begin(fingerprint: "old settings", paths: env.runtime.paths, environment: [:])
        env.live(["RelicCardinal.exe"])
        #expect(throws: SetupError.self) { try env.runtime.startSteam(.play([])) }
        #expect(!env.calls.contains("wineserver -k"), "the running game must survive")
        #expect(!env.calls.contains { $0.contains("-applaunch") })
    }

    @Test func steamWithOtherSettingsStopsThenLaunchesTheGame() throws {
        let env = try FakeEnvironment(.cs2); defer { env.cleanUp() }
        try env.installSteam()
        try SteamSession.begin(fingerprint: "old settings", paths: env.runtime.paths, environment: [:])
        env.live()
        try env.runtime.startSteam(.play([]))
        let calls = env.calls
        let kill = try #require(calls.firstIndex(of: "wineserver -k"))
        let launch = try #require(calls.firstIndex { $0.contains("-applaunch 730") })
        #expect(kill < launch)
        #expect(SteamSession.load(env.runtime.paths)?.fingerprint == SteamLaunch.fingerprint(try env.runtime.launchEnvironment()))
    }

    @Test func steamWithTheSameSettingsKeepsRunning() throws {
        let env = try FakeEnvironment(.cs2); defer { env.cleanUp() }
        try env.installSteam()
        let launchEnv = try env.runtime.launchEnvironment()
        try SteamSession.begin(fingerprint: SteamLaunch.fingerprint(launchEnv), paths: env.runtime.paths, environment: launchEnv)
        env.live(["RelicCardinal.exe"])
        try env.runtime.startSteam(.play([]))
        #expect(!env.calls.contains("wineserver -k"))
        #expect(env.calls.contains { $0.contains("-applaunch 730") })
    }

    @Test func steamReadyFindsTheStartLineInALogThatStartedOver() throws {
        let env = try FakeEnvironment(.heroes3); defer { env.cleanUp() }
        try env.installSteam()
        // An older, longer log: the fresh one is shorter than the old offset.
        try write(String(repeating: "old line\n", count: 2000), to: env.runtime.paths.steamDir.appendingPathComponent("logs/console_log.txt"))
        try write("", to: env.dir.appendingPathComponent("root/steam-truncates"))
        let start = Date()
        try env.runtime.ensureSteamReady()
        #expect(Date().timeIntervalSince(start) < 20)
        #expect(!env.events.all.contains { $0.contains("taking long") })
    }

    @Test func theSteamInstallerRunsFromDriveC() throws {
        let env = try FakeEnvironment(.cs2); defer { env.cleanUp() }
        try write("installer", to: env.dir.appendingPathComponent("downloads/SteamSetup.exe"))
        try env.runtime.installSteam()
        #expect(env.calls.contains(#"wine C:\macgames\SteamSetup.exe /S"#))
        #expect(FileManager.default.fileExists(atPath: env.runtime.paths.steamExe.path))
    }

    @Test func aRunningBattleNetInstallerIsNotStartedTwice() throws {
        let env = try FakeEnvironment(.diablo4BattleNet); defer { env.cleanUp() }
        env.live(["Battle.net-Setup.exe"])
        try env.runtime.installBattleNet()
        #expect(!env.calls.contains { $0.hasPrefix("wine ") })
        #expect(env.events.all.contains { $0.contains("still running") })
    }

    @Test func recipesReachAnExistingEnvironmentOnce() throws {
        let env = try FakeEnvironment(.witcher3); defer { env.cleanUp() }
        let plain = env.runtime.environment(optimized: false, hud: false)
        try env.runtime.ensureRecipes(environment: plain)
        #expect(env.calls.filter { $0.hasPrefix("wine reg import") }.count == 1)
        let imported = try #require(try? Data(contentsOf: env.dir.appendingPathComponent("root/imported.reg")))
        #expect(Array(imported.prefix(2)) == [0xFF, 0xFE])
        try env.runtime.ensureRecipes(environment: plain)
        #expect(env.calls.filter { $0.hasPrefix("wine reg import") }.count == 1, "the marker stops a second import")
    }

    @Test func aDirectGameStartsAfterSteamIsReady() throws {
        let env = try FakeEnvironment(.heroes3); defer { env.cleanUp() }
        try env.installSteam()
        try env.runtime.ensureSteamReady()
        try env.runtime.launchDirect()
        let calls = env.calls
        let steam = try #require(calls.firstIndex { $0.contains("steam.exe") })
        let game = try #require(calls.firstIndex { $0.hasPrefix("wine cmd /c") })
        #expect(steam < game)
    }
}
