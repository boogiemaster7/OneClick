import Foundation
import Testing
@testable import OneClickKit

@Suite("Wineserver tuning wrapper")
struct WineserverTuningTests {
    /// A fake runtime: `bin/wineserver` is a shell script standing in for the Mach-O server, recording its
    /// arguments and `REGSAVE_LOG` so the wrapper's hand-off can be checked without Wine.
    private func makeRuntime() throws -> (root: URL, dylib: URL, log: URL, out: URL) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("oneclick-wst-\(UUID().uuidString)")
        let bin = root.appendingPathComponent("bin")
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        let out = root.appendingPathComponent("server-out.txt")
        let server = bin.appendingPathComponent("wineserver")
        try "#!/bin/sh\necho \"args=$* log=$REGSAVE_LOG\" > \"\(out.path)\"\n".write(to: server, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: server.path)
        let dylib = root.appendingPathComponent("wineserver_fix.dylib")
        try Data([0xCF, 0xFA, 0xED, 0xFE]).write(to: dylib)
        return (root, dylib, root.appendingPathComponent("regsave.log"), out)
    }

    @Test("Install moves the real server aside, writes the wrapper, and is idempotent")
    func installIdempotent() throws {
        let rt = try makeRuntime()
        let original = try Data(contentsOf: rt.root.appendingPathComponent("bin/wineserver"))
        let tuning = WineserverTuning(runtimeRoot: rt.root)
        #expect(!tuning.isInstalled())

        #expect(try tuning.install(dylib: rt.dylib, regsaveLog: rt.log))
        #expect(tuning.isInstalled())
        #expect(try Data(contentsOf: tuning.realServer) == original)
        #expect(FileManager.default.contentsEqual(atPath: rt.dylib.path, andPath: tuning.installedDylib.path))
        let script = try String(contentsOf: tuning.server, encoding: .utf8)
        #expect(script.contains(WineserverTuning.marker))
        #expect(script.contains(rt.log.path))

        // Second install changes nothing — and never moves the wrapper over the real server.
        #expect(try tuning.install(dylib: rt.dylib, regsaveLog: rt.log) == false)
        #expect(try Data(contentsOf: tuning.realServer) == original)
    }

    @Test("Uninstall restores the original server byte for byte")
    func uninstallRestores() throws {
        let rt = try makeRuntime()
        let original = try Data(contentsOf: rt.root.appendingPathComponent("bin/wineserver"))
        let tuning = WineserverTuning(runtimeRoot: rt.root)
        try tuning.install(dylib: rt.dylib, regsaveLog: rt.log)
        #expect(try tuning.uninstall())
        #expect(!tuning.isInstalled())
        #expect(try Data(contentsOf: tuning.server) == original)
        #expect(!FileManager.default.fileExists(atPath: tuning.realServer.path))
        #expect(!FileManager.default.fileExists(atPath: tuning.installedDylib.path))
        #expect(try tuning.uninstall() == false)
    }

    @Test("The wrapper execs the real server with its arguments and the regsave log")
    func wrapperHandsOff() throws {
        let rt = try makeRuntime()
        let tuning = WineserverTuning(runtimeRoot: rt.root)
        try tuning.install(dylib: rt.dylib, regsaveLog: rt.log)
        let process = Process()
        process.executableURL = tuning.server
        process.arguments = ["-p", "-f"]
        try process.run(); process.waitUntilExit()
        #expect(process.terminationStatus == 0)
        #expect(try String(contentsOf: rt.out, encoding: .utf8) == "args=-p -f log=\(rt.log.path)\n")
    }

    @Test("Without the dylib the wrapper still starts the plain server")
    func wrapperFallsBack() throws {
        let rt = try makeRuntime()
        let tuning = WineserverTuning(runtimeRoot: rt.root)
        try tuning.install(dylib: rt.dylib, regsaveLog: rt.log)
        try FileManager.default.removeItem(at: tuning.installedDylib)
        let process = Process()
        process.executableURL = tuning.server
        process.arguments = ["-k"]
        try process.run(); process.waitUntilExit()
        #expect(try String(contentsOf: rt.out, encoding: .utf8) == "args=-k log=\n")   // no log env either
    }

    @Test("Not a wine runtime: install is a no-op; setting defaults off and tolerates old configs")
    func noRuntimeAndDefaults() throws {
        let empty = FileManager.default.temporaryDirectory.appendingPathComponent("oneclick-wst-\(UUID().uuidString)")
        #expect(try WineserverTuning(runtimeRoot: empty).install(dylib: empty, regsaveLog: empty) == false)
        #expect(BackendConfig().smoothRegistrySaves == false)
        let old = try JSONDecoder().decode(BackendConfig.self, from: Data(#"{"retinaMode":true}"#.utf8))
        #expect(old.smoothRegistrySaves == false)
    }
}
