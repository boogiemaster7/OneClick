/// Game profiles shipped with OneClick, one JSON document per game (schema: `GameProfile`). Keep values to
/// what is documented or measured; anything experimental belongs in the game's notes under
/// `docs/games/` until it has been A/B-tested on real hardware.
enum BundledProfiles {
    static let documents: [String] = [
        manorLords,
        anno1800,
    ]

    /// Manor Lords — UE5.4, DX12, no anti-cheat. See docs/games/manor-lords.md for the tuning plan.
    /// - D3DMetal (`gptk`): the DX12 path AppleGamingWiki rates "Perfect" with msync.
    /// - Raytracing Off: the game uses none, and D3DMetal enables DXR by default on M3+ (GPTK 4.0b2 Read Me).
    /// - 60 fps cap via `D3DM_MAX_FPS` (Read Me): steady pacing; the developer also recommends capping.
    static let manorLords = #"""
    {
      "id": "manor-lords",
      "title": "Manor Lords",
      "steam_appid": 1363080,
      "revision": 1,
      "renderer": "gptk",
      "env": {
        "syncMode": "msync",
        "advertiseAVX": true,
        "metalHUD": false,
        "metalFX": false,
        "raytracing": "off",
        "maxFPS": 60,
        "metalBackend": "auto",
        "extra": {}
      },
      "args": [],
      "executable": null,
      "fallback_executable": "ManorLords/Binaries/Win64/ManorLords-Win64-Shipping.exe",
      "anticheat": null,
      "conflicts": ["native-mac-steam"],
      "notes": "Launch from OneClick, not from the Play button inside Steam. In game: render at your display's non-Retina size (e.g. 1728x1117 on a 16-inch MacBook Pro), Shadows High (not \"sharp\"), Volumetric clouds Off, upscaler FSR or XeSS Quality. Raytracing is off and frames are capped at 60 for even pacing.",
      "lastVerified": null
    }
    """#

    /// Anno 1800 — Ubisoft Mainz in-house engine, DX11/DX12 (DX12 selected in engine.ini), Denuvo + Ubisoft
    /// Connect, no anti-cheat. See docs/games/anno-1800.md.
    /// - D3DMetal (`gptk`) with the game set to DX12: the combination CodeWeavers recommends and Mac users report.
    /// - `-uplay_steam_mode`: what Steam itself passes (Steam launch config) so Ubisoft Connect treats this as the
    ///   Steam edition; OneClick launches the exe directly, so the profile has to supply it.
    /// - Raytracing Off (the game has none) and a 60 fps cap (the game has no limiter of its own).
    static let anno1800 = #"""
    {
      "id": "anno-1800",
      "title": "Anno 1800",
      "steam_appid": 916440,
      "revision": 1,
      "renderer": "gptk",
      "env": {
        "syncMode": "msync",
        "advertiseAVX": true,
        "metalHUD": false,
        "metalFX": false,
        "raytracing": "off",
        "maxFPS": 60,
        "metalBackend": "auto",
        "extra": {}
      },
      "args": ["-uplay_steam_mode"],
      "executable": "Bin/Win64/Anno1800.exe",
      "fallback_executable": null,
      "anticheat": null,
      "conflicts": ["native-mac-steam"],
      "notes": "Needs Ubisoft Connect in the Steam bottle (turn its in-game overlay off). In game: DirectX 12, your display's non-Retina size (e.g. 1728x1117), High preset, then lower Shadows, Object, View distance and Crowd (Feedback) for big late-game cities. No in-game frame cap, so OneClick caps at 60. Denuvo: avoid switching Wine versions often, or it can lock activation for a day.",
      "lastVerified": null
    }
    """#
}
