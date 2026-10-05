import Foundation

/// The small Windows programs in `WindowsHelpers/` and when a game needs them.
public enum WindowsHelper {
    public struct Launch: Sendable, Equatable {
        public let name: String
        public let arguments: [String]
    }

    static let gtaAdvisoryTitle = "Minimum Recommended Hardware Check Failure"
    /// GTA V's AMD driver check, which cannot pass under Apple's graphics layer.
    static let gtaAdvisoryText = "Please update your graphics driver. Game requires version 24.12.1 or newer. "
        + "Please visit AMD: https://www.amd.com/en/support/download/drivers.html for the latest graphics driver"

    /// Watchers that run next to the game in its Steam session. They start before the game and exit after it.
    public static func watchers(for profile: GameProfile, paths: GamePaths, context: LaunchContext) -> [Launch] {
        switch profile.id {
        case "aom-retold":
            // The game checks its GPU in registry keys that Wine fills with the Mac's GPU.
            var list = [Launch(name: "gpu-sync", arguments: ["--watch", profile.executableName, "--wait-seconds", "300"])]
            if context.hasNotch, context.topInset > 0 {
                list.append(Launch(name: "fit-window", arguments: [
                    "--program", profile.executableName, "--width", String(context.width), "--height", String(context.height),
                    "--inset", String(format: "%g", context.topInset), "--wait-seconds", "300",
                ]))
            }
            return list
        case "gta5-enhanced":
            return [Launch(name: "dismiss-dialog", arguments: [
                "--program", profile.executableName, "--title", gtaAdvisoryTitle, "--text", gtaAdvisoryText, "--wait-seconds", "600",
            ])]
        default:
            return []
        }
    }

    /// The "<width> <height>" line that display-mode prints, among Wine's own messages.
    public static func displaySize(_ output: String) -> LaunchContext.Size? {
        for line in output.split(whereSeparator: \.isNewline).reversed() {
            let parts = line.trimmingCharacters(in: .whitespaces).split(separator: " ")
            if parts.count == 2, let w = Int(parts[0]), let h = Int(parts[1]), w >= 640, h >= 480 {
                return LaunchContext.Size(width: w, height: h)
            }
        }
        return nil
    }
}

extension GameRuntime {
    func helper(_ name: String) -> URL { runtime.windowsHelpers.appendingPathComponent("\(name).exe") }

    /// Starts the game's watchers. Steam starts first, in the background and with this game's
    /// settings, so the game's launch does not restart Steam and end the watchers.
    func startWatchers(_ watchers: [WindowsHelper.Launch]) throws {
        let available = watchers.filter { fm.fileExists(atPath: helper($0.name).path) }
        guard !available.isEmpty else { return }
        try ensureSteamSession()
        let env = try launchEnvironment()
        // A watcher is a help, not a requirement: one that fails is reported and the game starts anyway.
        for watcher in available {
            do {
                try startDetached([try stage(helper(watcher.name))] + watcher.arguments, environment: env,
                                  workingDirectory: driveC, log: "helpers.log")
            } catch {
                progress("The \(watcher.name) helper did not start: \(error)")
            }
        }
    }

    /// Starts or restarts Steam without its window, with this game's settings, and waits until it is up.
    func ensureSteamSession() throws {
        let running = isSessionRunning()
        let matches = SteamSession.load(paths)?.fingerprint == SteamLaunch.fingerprint(try launchEnvironment())
        if running && matches { return }
        let since = steamConsoleSize()
        try startSteam(.background)
        // Steam appends to its log, so only lines past the old end tell about this start.
        waitForSteam(since: since)
    }

    /// Raises a running program's main window; `false` when it has none.
    func showWindow(of program: String) -> Bool {
        guard fm.fileExists(atPath: helper("show-window").path), let path = try? stage(helper("show-window")) else { return false }
        return (try? runner.run(paths.wine, [path, program], environment: joined(environment(optimized: false, hud: false)), timeout: 30)) != nil
    }

    /// The display size Windows programs see, while a session runs; the Mac's size otherwise.
    func windowsDisplay(_ context: LaunchContext) -> LaunchContext {
        guard isSessionRunning(), fm.fileExists(atPath: helper("display-mode").path), let path = try? stage(helper("display-mode")),
              let output = try? runner.run(paths.wine, [path], environment: joined(environment(optimized: false, hud: false)), timeout: 30),
              let size = WindowsHelper.displaySize(output) else { return context }
        var adjusted = context
        adjusted.width = size.width
        adjusted.height = size.height
        return adjusted
    }
}
