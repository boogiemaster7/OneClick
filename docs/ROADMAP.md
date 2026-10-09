# OneClick roadmap

Goal: double-click `Manor Lords.app` on an Apple-silicon Mac and play the Windows Steam version at a
steady 60 fps, then add more games as data files instead of code. The design is in
[ARCHITECTURE.md](ARCHITECTURE.md).

Status key: ✅ done · 🔨 in progress · ⬜ not started. "Verified" means run on real hardware, not only
unit-tested.

## Inherited from Silo 0.5.0 (unit-tested; on-device verification is part of M0)
- ✅ Shared Windows Steam bottle; sign in once, and Steam caches the login.
- ✅ GPTK `.dmg` import; automatic GPTK → DXMT → DXVK backend choice and fallback; wined3d-fallback
  detection.
- ✅ Wine/DXMT/DXVK runtime download, SHA-256 verified and fail-closed.
- ✅ msync for games in the shared bottle; per-game env flags (Metal HUD, MetalFX, DXR, Metal 3/4).
- ✅ Per-game logs; bottle relocation to an external APFS drive; in-app self-update.
- ✅ Desktop shortcuts: a small `.app` that opens `oneclick://play/steam/<appid>`.

## M0: Manor Lords spike 🔨
- ✅ Fork, rename to OneClick, build and test on this Mac (539 tests green).
- ✅ Set up on device: GPTK 4.0 beta 2 imported, runtimes downloaded, bottle created, Steam signed in.
- ✅ Install Manor Lords (build 24905706, 14 GB).
- ⬜ Launch it on D3DMetal with msync, and confirm the log
  shows D3DMetal (not wined3d).
- ⬜ Measure fps with the Metal HUD at the display's resolution; tune for a steady 60 fps.
- ⬜ Write down every step in `docs/manual-path.md`.

## M1: Game profiles and preflight ⬜
- ⬜ Per-game JSON profiles (field names follow highball-db): exe, launch mode, backend and fallback,
  sync, env, args, conflicts, anti-cheat, notes, `lastVerified`. Manor Lords first: launch the Shipping
  exe directly, alongside Steam.
- ⬜ Preflight before every launch: Apple Silicon, macOS version, Rosetta, runtimes, GPTK, disk space.
- ⬜ Detect native Mac Steam and ask to quit it before launching.
- ⬜ Steam's own Play button must not start games on wined3d ("A D3D11-compatible GPU … is required").

## M2: App UI ⬜
- ⬜ Show profile status and notes in the library and game detail.
- ⬜ "Copy report" diagnostics export.
- ⬜ OneClick app icon.

## M3: Desktop apps ⬜
- ⬜ "Create Desktop App" writes `~/Applications/<Game>.app` (`com.oneclick.game.<id>`) with the game's
  icon; ad-hoc signed.
- ⬜ CLI: `oneclick make-app manor-lords`.

## M4: More games ⬜
- ⬜ Three more profiles: a DX11 game on DXMT, a DX12 game, and a 32-bit game.
- ⬜ Import highball-db (CC0) game entries.
- ⬜ Profile editor and "report result" export.

## M5: Hardening ⬜
- ⬜ This repository's own CI builds of Wine, DXMT and DXVK; move `RUNTIME_GITHUB_REPO` to them.
- ⬜ Runtime auto-update with checksums; no orphaned wineserver after a session.
- ⬜ Remember a crash-to-DXMT fallback per game.
- ⬜ Signed and notarized releases (needs an Apple Developer ID).

## M6: After Rosetta ⬜
- ⬜ Keep the engine swappable so an ARM64 Wine (CrossOver ARM64 / upstream) can replace the x86-64
  runtime. macOS 27 is the last full-Rosetta release.

## Resolved
- Manor Lords is Unreal Engine 5.4 (UE5 since 0.8.004); highball-db's "UE4" is stale.
- Tuning plan: [games/manor-lords.md](games/manor-lords.md).
