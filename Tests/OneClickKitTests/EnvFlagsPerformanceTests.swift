import Foundation
import Testing
@testable import OneClickKit

/// `D3DM_SUPPORT_DXR` tri-state and the `D3DM_MAX_FPS` frame cap — both from Apple's GPTK 4.0b2 Read Me.
@Suite("EnvFlags raytracing + frame cap")
struct EnvFlagsPerformanceTests {
    @Test("Raytracing: Automatic emits nothing, On/Off pin D3DM_SUPPORT_DXR")
    func raytracingTriState() {
        // `.auto` must emit no key: Apple's default is per chip (off on M1/M2, on for M3+).
        #expect(EnvFlags(raytracing: .auto).environment(graphics: .gptk)["D3DM_SUPPORT_DXR"] == nil)
        #expect(EnvFlags(raytracing: .on).environment(graphics: .gptk)["D3DM_SUPPORT_DXR"] == "1")
        // `.off` must emit an explicit 0 — the only way to disable DXR on an M3+ Mac.
        #expect(EnvFlags(raytracing: .off).environment(graphics: .gptk)["D3DM_SUPPORT_DXR"] == "0")
    }

    @Test("Raytracing and frame cap are D3DMetal-only")
    func gptkOnly() {
        let flags = EnvFlags(raytracing: .off, maxFPS: 60)
        for graphics in [GraphicsBackend.dxmt, .dxvk] {
            let env = flags.environment(graphics: graphics)
            #expect(env["D3DM_SUPPORT_DXR"] == nil)
            #expect(env["D3DM_MAX_FPS"] == nil)
        }
    }

    @Test("Frame cap emits D3DM_MAX_FPS only for a positive value")
    func frameCap() {
        #expect(EnvFlags(maxFPS: 60).environment(graphics: .gptk)["D3DM_MAX_FPS"] == "60")
        #expect(EnvFlags().environment(graphics: .gptk)["D3DM_MAX_FPS"] == nil)
        #expect(EnvFlags(maxFPS: 0).environment(graphics: .gptk)["D3DM_MAX_FPS"] == nil)
        #expect(EnvFlags(maxFPS: -5).environment(graphics: .gptk)["D3DM_MAX_FPS"] == nil)
        // `extra` still merges last and can override the picker.
        #expect(EnvFlags(maxFPS: 60, extra: ["D3DM_MAX_FPS": "45"]).environment(graphics: .gptk)["D3DM_MAX_FPS"] == "45")
    }

    @Test("Legacy dxr Bool migrates without changing the launch environment")
    func legacyDXRMigration() throws {
        let wasOn = try JSONDecoder().decode(EnvFlags.self, from: Data(#"{"dxr":true,"extra":{}}"#.utf8))
        #expect(wasOn.raytracing == .on)
        // Legacy `false` emitted nothing, so it must become `.auto` (not `.off`, which would emit =0).
        let wasOff = try JSONDecoder().decode(EnvFlags.self, from: Data(#"{"dxr":false,"extra":{}}"#.utf8))
        #expect(wasOff.raytracing == .auto)
        // The new key wins over a stale legacy one.
        let both = try JSONDecoder().decode(
            EnvFlags.self, from: Data(#"{"raytracing":"off","dxr":true,"extra":{}}"#.utf8))
        #expect(both.raytracing == .off)
    }

    @Test("Unknown raytracing value degrades to Automatic; maxFPS round-trips")
    func tolerantDecodeAndRoundTrip() throws {
        let future = try JSONDecoder().decode(
            EnvFlags.self, from: Data(#"{"raytracing":"pathtraced","extra":{}}"#.utf8))
        #expect(future.raytracing == .auto)
        #expect(future.maxFPS == nil)

        let original = EnvFlags(raytracing: .off, maxFPS: 60)
        let decoded = try JSONDecoder().decode(EnvFlags.self, from: JSONEncoder().encode(original))
        #expect(decoded == original)
    }
}
