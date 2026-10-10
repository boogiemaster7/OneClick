<div align="center">

# OneClick

**Double-click a game icon on your Mac. Play the Windows Steam version.**

Apple Silicon · macOS 15+ · SwiftUI · Apple D3DMetal + DXMT + DXVK

[Architecture](docs/ARCHITECTURE.md) ·
[Roadmap](docs/ROADMAP.md) ·
[Wine build](docs/WINE-BUILD.md) ·
[License](LICENSE)

</div>

OneClick is a launcher for Windows Steam games on Apple-silicon Macs. It runs a real **Windows Steam
client inside one shared Wine bottle** and launches each game **next to it**, on the fastest Metal graphics
backend that works for that game. Steamworks and Steam DRM work normally, with no emulators and no
patched game files. You sign in to Steam once, and it stays signed in.

Each game can get its own **`<Game>.app` on your Desktop or in Launchpad**. Double-click it and OneClick
starts Steam if needed and launches the game in the right bottle with the right graphics backend.

**First target: Manor Lords** (Steam app 1363080, DirectX 12, no anti-cheat), tuned for a steady 60 fps.
OneClick is early: see the [Roadmap](docs/ROADMAP.md) for what is verified so far.

## How it works

```
Wine (x86-64, under Rosetta 2)
  └─ D3DMetal (Apple GPTK: DX11/12 → Metal)  ·  DXMT (DX10/11 → Metal)  ·  DXVK (DX9/10/11 → Vulkan → Metal)
       └─ Windows Steam client in a shared prefix
            └─ the game's .exe, launched alongside Steam
```

1. **Bottle.** One shared Wine prefix with Windows Steam, its fonts and the VC++ runtimes.
2. **Discovery.** Installed games are read from Steam's `appmanifest_*.acf` and `libraryfolders.vdf`.
3. **Backend choice.** OneClick picks GPTK, DXMT or DXVK per game from the DirectX imports of the game and
   its DLLs. If a backend silently falls back to Wine's slow wined3d renderer, OneClick notices and
   switches.
4. **Launch.** Each game runs in the same bottle as Steam, with its own environment and a per-game log.

Everything OneClick installs lives under `~/Library/Application Support/OneClick/`. Delete that folder
to uninstall.

## First-run setup

1. **Import GPTK.** Download Apple's Game Porting Toolkit `.dmg` from
   [developer.apple.com/games](https://developer.apple.com/games/game-porting-toolkit/) (free Apple ID)
   and pick it in OneClick. OneClick copies out the D3DMetal layer. Apple's license does not allow
   redistributing it, so OneClick never downloads it for you.
2. **Set up.** One click installs Rosetta 2 if needed, downloads the Wine runtime and graphics layers
   (SHA-256 verified), installs Windows Steam into the bottle, and opens it so you can sign in.

Then press **Play**, or create a desktop app for the game.

> **Mac Steam:** running the native macOS Steam client at the same time can crash games or show
> "NO CONNECTION". Quit it before playing (an automatic check is on the [Roadmap](docs/ROADMAP.md), M1).

> **Gatekeeper:** builds are ad-hoc signed. On first launch, right-click → **Open** (or run
> `xattr -dr com.apple.quarantine OneClick.app`).

## Build from source

A Swift 6 toolchain is enough. Command Line Tools work; full Xcode is not required.

```sh
./Scripts/test.sh        # test suite; passes with no Wine/GPTK/Steam installed
./Scripts/build-app.sh   # assemble + ad-hoc sign dist/OneClick.app
./Scripts/run.sh         # build the app and open it
./Scripts/dev.sh         # fast iteration: swift run oneclick
```

On a Mac with only the Command Line Tools, create `local.env` with `MACOS_SDK_VERSION=26.5` first. See
[Build environment](docs/ARCHITECTURE.md#build-environment) for why. Every version number lives in
`versions.env`.

### Wine sourcing

Wine is built **only from CrossOver's open-source (LGPL) code** (`Scripts/build-wine.sh`,
`.github/workflows/build-wine.yml`). DXMT and DXVK are built from their upstream sources against that Wine.
Until this repository's CI publishes its own runtimes, the app downloads the identical from-source builds
published by Silo (`RUNTIME_GITHUB_REPO` in `versions.env`). See [docs/WINE-BUILD.md](docs/WINE-BUILD.md).

## Ground rules

- **No game files, ever.** You install games from your own Steam account with the real Steam client.
  OneClick ships and downloads no game files, cracks, repacks or Steam emulators.
- **No D3DMetal redistribution.** GPTK is always imported from your own Apple download.
- **No kernel anti-cheat titles.** Games that need it are flagged as unsupported.

## Credits

- **[Silo](https://github.com/mikaelhug/Silo)** by Mikael Hug: OneClick is a fork of Silo, and its
  bottle, backend and launch engine are Silo's work.
- **[CodeWeavers](https://www.codeweavers.com/crossover/source)**, for publishing CrossOver's Wine source.
- **[DXMT](https://github.com/3Shain/dxmt)** by 3Shain, **[DXVK](https://github.com/doitsujin/dxvk)** and
  **[MoltenVK](https://github.com/KhronosGroup/MoltenVK)**.
- **Apple**, for the [Game Porting Toolkit](https://developer.apple.com/games/game-porting-toolkit/) and
  D3DMetal.
- **[highball-db](https://github.com/gauthierpiarrette/highball-db)** (CC0), for game compatibility
  data.
- **[mac-gaming-fixes](https://github.com/been-earth/mac-gaming-fixes)** (MIT) by been-earth: the optional
  wineserver registry-save / Wi-Fi latency fix (`Scripts/native/wineserver_fix.c`).

## License

[LGPL-2.1-or-later](LICENSE), as inherited from Silo. Wine is redistributed under the LGPL from
CrossOver's published sources. GPTK remains your own Apple-licensed download. You are responsible for
complying with the Steam Subscriber Agreement and applicable law.

OneClick is not affiliated with Valve, Apple, CodeWeavers, Slavic Magic or Hooded Horse.
