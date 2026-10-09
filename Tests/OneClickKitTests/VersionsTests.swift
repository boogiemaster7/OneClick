import Foundation
import Testing
@testable import OneClickKit

@Suite("Versions ↔ versions.env")
struct VersionsTests {

    /// Parse `KEY=VALUE` out of versions.env (located relative to this source file → repo root).
    private func envValue(_ key: String) throws -> String? {
        let repoRoot = URL(fileURLWithPath: #filePath)   // Tests/OneClickKitTests/VersionsTests.swift
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let text = try String(contentsOf: repoRoot.appendingPathComponent("versions.env"), encoding: .utf8)
        for line in text.split(whereSeparator: \.isNewline) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.hasPrefix("#"), trimmed.hasPrefix("\(key)=") else { continue }
            return String(trimmed.dropFirst(key.count + 1))
        }
        return nil
    }

    /// Guards against editing versions.env without re-running Scripts/gen-versions.sh — the generated
    /// `Versions.swift` is committed, so it can drift out of sync silently otherwise.
    @Test("Versions.swift mirrors versions.env (run Scripts/gen-versions.sh after editing it)")
    func versionsInSync() throws {
        #expect(try envValue("ONECLICK_VERSION") == Versions.oneclick)
        #expect(try envValue("ONECLICK_GITHUB_REPO") == Versions.githubRepo)
        #expect(try envValue("RUNTIME_GITHUB_REPO") == Versions.runtimeRepo)
        #expect(try envValue("CROSSOVER_VERSION") == Versions.crossoverVersion)
    }

    @Test("OneClick's public constants are sourced from Versions")
    func oneClickConstantsSourced() {
        #expect(OneClick.version == Versions.oneclick)
        #expect(OneClick.updateRepo == Versions.githubRepo)
        #expect(OneClick.wineRepo == Versions.runtimeRepo)
    }
}
