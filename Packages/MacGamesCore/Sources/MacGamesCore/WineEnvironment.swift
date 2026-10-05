import Foundation

public enum WineEnvironment {
    /// Inherited keys that would change how Wine, Rosetta or the renderers behave.
    static let strippedPrefixes = ["CX_", "WINE", "DYLD_", "ROSETTA_", "MTL_", "D3DM_", "DXMT_", "GST_",
                                   "AOELAB_", "AOE2_", "AOE_SOFTFAULT_", "X87_", "SDL_", "MACGAMES_"]

    static let baseOverrides = "winemenubuilder.exe=;mscoree,mshtml=;gameoverlayrenderer,gameoverlayrenderer64=;"

    /// Builds the full environment for any Wine process of `profile`.
    ///
    /// Steam passes its own environment on to the game, so Steam itself must be
    /// started with the same environment the game should get.
    public static func make(profile: GameProfile, paths: GamePaths, inherited: [String: String],
                            optimized: Bool, hud: Bool, bridge: URL) -> [String: String] {
        var env = inherited.filter { key, _ in !strippedPrefixes.contains(where: key.hasPrefix) }
        let fw = paths.frameworks.path
        let gst = "\(fw)/GStreamer.framework/Versions/1.0/lib"
        env.merge([
            "WINEPREFIX": paths.prefix.path,
            "WINESERVER": paths.wineserver.path,
            "WINELOADER": paths.wine.path,
            "WINEDEBUG": "-all",
            "ROSETTA_ADVERTISE_AVX": "1",
            "WINEMSYNC": "1",
            "WINEESYNC": "0",
            "MTL_HUD_ENABLED": hud ? "1" : "0",
            "D3DM_ENABLE_METALFX": "0",
            "MVK_CONFIG_LOG_LEVEL": "1",
            "AOELAB_STEAM_SINGLEPROCESS": "1",
            "SDL_JOYSTICK_ALLOW_BACKGROUND_EVENTS": "1",
        ]) { $1 }
        // A self-contained engine finds its own libraries; the template's are not there.
        if paths.environment.usesTemplate {
            env["DYLD_FALLBACK_LIBRARY_PATH"] = "\(fw):\(gst):/usr/lib"
            env["GST_PLUGIN_PATH"] = "\(gst)/gstreamer-1.0"
            env["GST_REGISTRY"] = paths.root.appendingPathComponent("gstreamer-registry.bin").path
        }

        let engineDLLs = paths.engine.appendingPathComponent("lib/wine").path
        switch profile.graphics {
        case .d3dmetal:
            env["WINEDLLPATH"] = "\(paths.d3dmetal.path)/wine:\(engineDLLs)"
            env["WINEDLLOVERRIDES"] = baseOverrides + "dxgi,d3d11,d3d12,atidxx64=n,b;nvapi64,nvngx="
        case .dxmt:
            env["WINEDLLPATH"] = engineDLLs
            // The shared prefix's system32 holds D3DMetal for other games, so
            // every D3D name is forced to the engine's builtins.
            env["WINEDLLOVERRIDES"] = baseOverrides + "dxgi,d3d11,d3d10core,d3d12,atidxx64,winemetal=b;nvapi64,nvngx="
        case .builtin:
            env["WINEDLLPATH"] = engineDLLs
            env["WINEDLLOVERRIDES"] = baseOverrides + "nvapi64,nvngx="
        }

        let edits = GameRecipes.environmentEdits(for: profile, paths: paths)
        if let overrides = edits.overrides { env["WINEDLLOVERRIDES"] = overrides }
        if let extra = edits.appendOverrides { env["WINEDLLOVERRIDES"]! += extra }
        for key in edits.unset { env[key] = nil }
        env.merge(edits.set) { $1 }
        if edits.libd3dshared {
            env["CX_APPLEGPTK_LIBD3DSHARED_PATH"] = paths.d3dmetal.appendingPathComponent("external/libd3dshared.dylib").path
        }
        let data = paths.gameData.path
        if edits.sandbox == .full { env["HOME"] = data + "/home" }
        if edits.sandbox != .none {
            env["XDG_CACHE_HOME"] = data + "/cache"
            env["XDG_CONFIG_HOME"] = data + "/config"
            env["XDG_DATA_HOME"] = data + "/share"
            env["TMPDIR"] = data + "/tmp/"
        }

        // The patched ntdll re-execs RelicCardinal.exe through the bridge only
        // when all of these are present; set all of them or none.
        if optimized, let sha = profile.optimizedExecutableSHA256 {
            env["AOELAB_SOFTFAULT_GAME"] = "1"
            env["AOELAB_CODE_CACHE_GAME"] = "1"
            env["AOELAB_SIDECAR_PATH"] = bridge.path
            env["MACGAMES_OPTIMIZED_SHA256"] = sha
        }
        return env
    }
}
