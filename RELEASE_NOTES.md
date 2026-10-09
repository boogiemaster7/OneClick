# OneClick 0.1.0

First OneClick build, forked from Silo 0.5.0.

- Renamed to OneClick: app, bundle IDs (`com.oneclick.*`), the `oneclick://` link scheme, and the data folder (`~/Library/Application Support/OneClick/`).
- The app updates from this repository's Releases; the Wine, DXMT and DXVK runtimes still come from Silo's published from-source builds.
- Builds and tests on a Mac with only the Command Line Tools.

---

OneClick downloads its own Wine (built from CrossOver's open-source code) and imports Apple's GPTK from your `.dmg`. Runs on macOS 15+ on Apple Silicon. Gatekeeper: the build is ad-hoc signed, so right-click → **Open** on first launch (or `xattr -dr com.apple.quarantine OneClick.app`).
