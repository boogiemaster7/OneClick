# Wine patch series

Applied in lexical order to the pristine CrossOver source (`CROSSOVER_VERSION` in `versions.env`) by
`Scripts/apply-wine-patches.sh`. OneClick's runtime is built by `Scripts/build-wine-overlay.sh`
(`.github/workflows/build-wine-overlay.yml`): upstream's published runtime with the unix-side modules these
patches touch rebuilt and swapped in (`share/oneclick/build-info.txt` in the runtime lists every hash).
A patch that doesn't apply stops the build. Every patch keeps its upstream header (author, description,
measurements). All are LGPL-2.1-or-later, like Wine.

| # | Patch | Source | What it fixes |
|---|---|---|---|
| 0001 | winemac: remove per-click stalls | athei/wine `ddbdcd53b9` (Alexander Theißen) | 1–3 ms stall per mouse press on EDR displays in full-screen Metal games (fps 120 → ~107 while clicking fast, measured upstream) |
| 0002 | win32u, winemac: destroy-window races | athei/wine `e1e9291773` (Alexander Theißen) | Deadlock when several threads create/move/destroy windows with D3DMetal client surfaces |
| 0003 | winemac: cross-process child swapchains | gauthierpiarrette/highball-engine `0007` (at `ac5cc83`) | Wine bug 60263: CEF launchers (Ubisoft Connect, Rockstar, Steam's browser) render a black/white window because their GPU process can't present into the browser process's window |
| 0004 | msync: unregister on early return | gauthierpiarrette/highball-engine `0014` | wineserver memory leak / node-pool exhaustion under msync (highball#224) |
| 0005 | winecoreaudio: I/O buffer under half a period | gauthierpiarrette/highball-engine `0015` | Audio dropouts/crackle at 44.1/48 kHz (highball#127) |

Order matters: 0001–0002 must apply before 0003 (all three touch `dlls/winemac.drv/window.c`'s window
teardown). Verified to apply without fuzz to crossover-sources-26.3.0, 2026-10-10.
