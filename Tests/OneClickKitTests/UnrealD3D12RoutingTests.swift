import Foundation
import Testing
@testable import OneClickKit

/// Regression for Manor Lords (2026-10-09/10): a working D3DMetal launch was misread as a GPTK failure, the
/// game learned DXMT, and DXMT (no D3D12) crashed it on every launch.
@Suite("Unreal + D3D12 routing")
struct UnrealD3D12RoutingTests {
    /// Excerpt of the real log: wined3d's probe line appears, but D3DMetal is converting shaders.
    static let manorLordsLog = """
    060c:trace:loaddll:build_module Loaded L"C:\\\\windows\\\\system32\\\\wined3d.dll" at 00006FFFE79F0000: builtin
    060c:err:winediag:wined3d_adapter_create Using the Vulkan renderer for d3d10/11 applications.
    060c:trace:loaddll:build_module Loaded L"C:\\\\windows\\\\system32\\\\d3d12.dll" at 00006FFFE5DD0000: builtin
    [metal-shaderconverter] Warning: Undefined: Shader might rely on forward progress/persistent thread
    """

    @Test("Metal Shader Converter output proves D3DMetal engaged, despite wined3d's probe line")
    func shaderConverterIsEngagement() {
        #expect(GraphicsFallback.classify(Self.manorLordsLog, backend: .gptk) == .engaged)
        // It is D3DMetal-specific: the same lines under DXMT still read as a fallback.
        #expect(GraphicsFallback.classify(Self.manorLordsLog, backend: .dxmt) == .fallback)
        // And without the converter line, the wined3d line is still a fallback for GPTK (unchanged).
        let noConverter = Self.manorLordsLog.replacingOccurrences(of: "[metal-shaderconverter]", with: "")
        #expect(GraphicsFallback.classify(noConverter, backend: .gptk) == .fallback)
    }

    @Test("The scan follows an Unreal bootstrap stub to the Shipping exe and sees D3D12")
    func unrealStubLayout() throws {
        let tmp = try TempDir(); defer { tmp.cleanup() }
        let stub = tmp.url.appendingPathComponent("Manor Lords/ManorLords.exe")
        try tmp.makeDir("Manor Lords/ManorLords/Binaries/Win64")
        try PEFixture.withImports(magic: 0x20b, machine: 0x8664, imports: ["kernel32.dll"]).write(to: stub)
        let shipping = tmp.url.appendingPathComponent(
            "Manor Lords/ManorLords/Binaries/Win64/ManorLords-Win64-Shipping.exe")
        try PEFixture.withDelayImports(magic: 0x20b, machine: 0x8664, imports: ["d3d12.dll"]).write(to: shipping)

        #expect(D3DProfile.unrealShippingExecutables(besideStub: stub).map(\.lastPathComponent)
                == ["ManorLords-Win64-Shipping.exe"])
        let profile = D3DProfile.scan(executable: stub)
        #expect(profile.usesD3D12)
        #expect(!BackendChooser.dxmtMightHelp(profile: profile))
    }

    @Test("A stale learned DXMT/DXVK hint is ignored for a D3D12 game; still honored otherwise")
    func staleHintDropped() {
        var d3d12 = D3DProfile(); d3d12.usesD3D12 = true
        #expect(BackendChooser.choose(.auto, is32Bit: false, profile: d3d12, learned: .dxmt) == .gptk)

        var d3d11 = D3DProfile(); d3d11.usesD3D1x = true
        #expect(BackendChooser.choose(.auto, is32Bit: false, profile: d3d11, learned: .dxmt) == .dxmt)
        // Unknown profiles still fail open and keep the hint.
        #expect(BackendChooser.choose(.auto, is32Bit: false, profile: D3DProfile(), learned: .dxmt) == .dxmt)
        // A user pin still wins over everything.
        #expect(BackendChooser.choose(.dxmt, is32Bit: false, profile: d3d12, learned: nil) == .dxmt)
    }
}
