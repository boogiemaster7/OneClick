# Manor Lords: tuning plan

Steam app 1363080 · build 24905706 (installed 2026-10-09) · Unreal Engine 5.4 · DirectX 12 default ·
no anti-cheat.

Goal: a **steady 60 fps** on an M5 Pro MacBook Pro 16" (3456×2234 Retina panel) through D3DMetal
(GPTK 4.0 beta 2). Every change below is A/B-tested against a baseline before it becomes a profile
default. Tags: **[Apple]** documented in the GPTK 4.0b2 Read Me · **[Dev]** Slavic Magic patch notes ·
**[Measured]** a user measured it · **[Claim]** community report · **[Ours]** to be measured here.

## Engine facts
- UE5 since 0.8.004 (Sep 2024); crash logs show `Release-5.4`. [Dev] (highball-db's "UE4" is stale.)
- Lumen is off; there is no ray tracing. "Sharp" shadows use Virtual Shadow Maps, which the developer
  says drop fps "massively" when the sun moves. [Dev]
- Anti-aliasing menu: FXAA, TAA, FSR (4.0.2 since Update #5), DLSS/DLAA, XeSS. **No frame-generation
  option**, even though `amd_fidelityfx_framegeneration_dx12.dll` ships in `Binaries/Win64`. [Dev]
- Config: `%LOCALAPPDATA%\ManorLords\Saved\Config\Windows\` (`Settings.ini`, `Engine.ini`). Saves:
  `%LOCALAPPDATA%\ManorLords\Saved\SaveGames\`. In the bottle: `drive_c/users/crossover/AppData/Local/ManorLords/`.

## How to launch it
- **Through OneClick's Play button**, not the Play button inside the Windows Steam window. A Steam-started
  game runs on the Steam client's runtime, gets wined3d and fails with "A D3D11-compatible GPU … is
  required" (seen 2026-10-09). Fixing that trap is a profile task.
- Launching `ManorLords-Win64-Shipping.exe` directly worked around a VC++ prompt in 2025 builds. CrossOver
  has since fixed that, so it is a **fallback only**. [Claim]

## The levers, in test order

| # | Lever | How | Source | Expected |
|---|---|---|---|---|
| 1 | Render resolution | 1728×1117 borderless (the panel's point size, ¼ of native pixels). Compare native + upscaler. | GameToMac's RDR2 preset uses exactly this | Largest single gain |
| 2 | Upscaler | FSR 4 Quality vs XeSS Quality vs DLSS Quality (DLSS → MetalFX needs `D3DM_ENABLE_METALFX=1`; the DLSS option may not appear on a non-NVIDIA device) | [Apple] env var · [Claim] menu | Large |
| 3 | Frame cap | `D3DM_MAX_FPS=60` vs in-game "Max framerate" 60 / 59.94 | [Apple] · [Dev] | Even frame pacing |
| 4 | Raytracing off | `D3DM_SUPPORT_DXR=0`; Apple enables it by default on M3+, and the game uses none | [Apple] | Small, free |
| 5 | Metal 4 vs Metal 3 | `D3DM_MTL4` default (4) vs `0` | [Apple]; Highball defaults to Metal 3 for stability | Unknown, measure |
| 6 | Shadows | High, never "sharp" (VSM) | [Dev] | Removes sunset drops |
| 7 | Heavy settings | Volumetric clouds Off; View/Grass distance Medium; Grass density Medium; Bounced light Medium | [Measured] PC/Steam Deck guides | Medium |
| 8 | Cheap quality | Terrain textures High, Shader High, Foliage High (unified memory makes textures nearly free) | GameToMac's RDR2 preset (Ultra textures) | Keeps it sharp |
| 9 | Sync | msync (OneClick default for the shared bottle) | [Claim] AppleGamingWiki "Perfect" with msync | Already on |
| 10 | AVX | `ROSETTA_ADVERTISE_AVX=1` (OneClick default) | [Apple] | Already on |
| 11 | Windows version | Windows 11 in the bottle; one report says it stopped a slide to 5 fps after minutes | [Claim] M2 | Check the bottle's setting |
| 12 | Motion blur | `Engine.ini [SystemSettings]` `r.MotionBlur.Max=0`, `r.DefaultFeature.MotionBlur=0` | [Claim] cosmetic | Clarity only |

Do **not** apply: `r.TemporalAA.HistoryScreenPercentage=200` / `r.TemporalAA.Algorithm=1` (cost about
10%), `-USEALLAVAILABLECORES` (no source), and the placebo variables listed in the trend research
(`D3DM_FEATURE_LEVEL_*`, `WINE_CPU_TOPOLOGY`, …).

## Experiments after a stable 60
- Frame generation: the game exposes none. DLSS frame generation → MetalFX frame interpolation exists in
  D3DMetal but has wedged WindowServer on another project's test Mac; only behind an explicit opt-in.
- Shader-cache warm-up: keep `$(getconf DARWIN_USER_CACHE_DIR)/d3dm/<game>/shaders.cache` between runs and
  measure first-run vs second-run stutter.
- macOS Game Mode for the Wine loader (no project has tried it yet).

## Benchmark protocol
Same save, same camera spot (village centre, mid-day, then sunset), 60 s after load, Metal HUD on
(`MTL_HUD_ENABLED=1`). Record average fps, 1% low and GPU time per change. Results go in the table
below with the date, GPTK and Wine versions.

| Date | Change | Resolution | Avg fps | 1% low | Notes |
|---|---|---|---|---|---|
| | Baseline (defaults) | | | | |
