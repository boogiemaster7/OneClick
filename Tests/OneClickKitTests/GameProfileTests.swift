import Foundation
import Testing
@testable import OneClickKit

@Suite("Game profiles")
struct GameProfileTests {
    @Test("Every bundled profile decodes, with unique ids and app IDs")
    func bundledProfilesDecode() {
        let result = GameProfileCatalog.decode(BundledProfiles.documents)
        #expect(result.failures.isEmpty, "bundled profile failed to decode: \(result.failures)")
        #expect(result.catalog.profiles.count == BundledProfiles.documents.count, "duplicate steam_appid")
        let ids = result.catalog.profiles.values.map(\.id)
        #expect(Set(ids).count == ids.count, "duplicate profile id")
    }

    @Test("Manor Lords profile: D3DMetal, raytracing off, 60 fps cap, msync")
    func manorLordsProfile() throws {
        let profile = try #require(GameProfileCatalog.bundled.profile(for: 1363080))
        #expect(profile.id == "manor-lords")
        #expect(profile.renderer == .gptk)
        #expect(profile.anticheat == nil)
        #expect(profile.conflicts.contains("native-mac-steam"))
        let env = profile.env.environment(graphics: .gptk)
        #expect(env["D3DM_SUPPORT_DXR"] == "0")
        #expect(env["D3DM_MAX_FPS"] == "60")
        #expect(env["WINEMSYNC"] == "1")
        #expect(env["ROSETTA_ADVERTISE_AVX"] == "1")
        #expect(env["D3DM_ENABLE_METALFX"] == nil)   // experimental until measured
    }

    @Test("Anno 1800 profile: D3DMetal, Steam-edition flag, explicit exe, raytracing off, 60 fps cap")
    func anno1800Profile() throws {
        let profile = try #require(GameProfileCatalog.bundled.profile(for: 916440))
        #expect(profile.id == "anno-1800")
        #expect(profile.renderer == .gptk)
        #expect(profile.args == ["-uplay_steam_mode"])          // what Steam passes; OneClick must too
        #expect(profile.executable == "Bin/Win64/Anno1800.exe")
        let env = profile.env.environment(graphics: .gptk)
        #expect(env["D3DM_SUPPORT_DXR"] == "0")
        #expect(env["D3DM_MAX_FPS"] == "60")
        #expect(env["WINEMSYNC"] == "1")
        #expect(profile.seededConfig().customArgs == ["-uplay_steam_mode"])
    }

    @Test("An unsaved game starts from its profile; a saved config wins; others get plain defaults")
    func configLookupPrecedence() throws {
        let profile = try #require(GameProfileCatalog.bundled.profile(for: 1363080))
        var state = AppState()
        #expect(state.config(for: 1363080) == profile.seededConfig())
        #expect(state.config(for: 42) == GameConfig(appID: 42))

        var mine = GameConfig(appID: 1363080, graphics: .dxmt)
        mine.envFlags.maxFPS = 30
        state.upsert(mine)
        #expect(state.config(for: 1363080) == mine)

        // An empty catalog means no profile seeding at all.
        #expect(AppState().config(for: 1363080, profiles: GameProfileCatalog(profiles: [])) == GameConfig(appID: 1363080))
    }

    @Test("Applying a profile replaces only profile-owned fields")
    func appliedKeepsUserState() throws {
        let profile = try #require(GameProfileCatalog.bundled.profile(for: 1363080))
        let played = Date(timeIntervalSince1970: 1_700_000_000)
        let custom = GameConfig(appID: 1363080, envFlags: EnvFlags(metalHUD: true), presence: .none,
                                graphics: .dxvk, learnedBackend: .dxmt, learnedUnderRuntime: "GPTK-x",
                                customArgs: ["-dx11"], needsVirtualDesktop: true, lastPlayed: played)
        #expect(!profile.matches(custom))
        let applied = profile.applied(to: custom)
        #expect(profile.matches(applied))
        #expect(applied.presence == .none)
        #expect(applied.learnedBackend == .dxmt)
        #expect(applied.learnedUnderRuntime == "GPTK-x")
        #expect(applied.needsVirtualDesktop)
        #expect(applied.lastPlayed == played)
    }

    @Test("A malformed profile is skipped without dropping the others; unknown renderer degrades")
    func tolerantDecode() {
        let good = #"{"id":"a","title":"A","steam_appid":1,"renderer":"metal9"}"#
        let bad = #"{"id":"b","title":"B"}"#   // no steam_appid
        let result = GameProfileCatalog.decode([good, bad])
        #expect(result.failures.count == 1)
        #expect(result.catalog.profile(for: 1)?.renderer == .auto)
        #expect(result.catalog.profile(for: 1)?.revision == 1)
    }

    @Test("Settings view model offers and applies the recommendation")
    @MainActor
    func viewModelRecommended() throws {
        let store = ConfigStore(paths: AppPaths(supportDir: FileManager.default.temporaryDirectory
            .appendingPathComponent("oneclick-profile-\(UUID().uuidString)")))
        let vm = GameSettingsViewModel(config: GameConfig(appID: 1363080, graphics: .dxmt), configStore: store)
        #expect(vm.profile?.id == "manor-lords")
        #expect(!vm.usesRecommended)
        vm.useRecommended()
        #expect(vm.usesRecommended)
        #expect(vm.config.graphics == GraphicsChoice.gptk)

        let noProfile = GameSettingsViewModel(config: GameConfig(appID: 42), configStore: store)
        #expect(noProfile.profile == nil)
        #expect(!noProfile.usesRecommended)
    }
}
