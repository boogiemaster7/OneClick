import Testing
@testable import OneClickKit

@Suite("Smoke")
struct SmokeTests {
    @Test("Version metadata resolves to a non-empty value (Versions.swift was generated)")
    func versionResolves() {
        #expect(!OneClick.version.isEmpty)   // the real version-sync guard lives in VersionsTests
    }
}
