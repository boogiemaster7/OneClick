import Foundation

/// Wraps a Wine runtime's `bin/wineserver` so it starts with `wineserver_fix.dylib` injected
/// (`Scripts/native/wineserver_fix.c`, from github.com/been-earth/mac-gaming-fixes, MIT). The fix:
/// - **defers the periodic save of a large registry branch while the bottle is busy.** wineserver is
///   single-threaded and rewrites each dirty `.reg` file every 30 s; a Steam bottle's ~12 MB `system.reg`
///   blocks every process in the bottle for ~240 ms. Deferred saves retry 30 s later and still go through
///   once the bottle is quiet; saves on server exit are untouched.
/// - **tags UDP sockets with a real-time network service class**, so the Mac's Wi-Fi stops holding packets
///   for up to ~25 ms.
///
/// Wine starts the `wineserver` that sits next to its own binary before it ever reads `$WINESERVER`
/// (`dlls/ntdll/unix/loader.c`), so the wrapper has to live at `bin/wineserver`; the real server moves to
/// `bin/wineserver.real`. The wrapper falls back to the plain server when the dylib is missing, so a broken
/// install can never stop Wine from starting. Install and remove are idempotent.
public struct WineserverTuning: Sendable {
    /// First lines of every wrapper this type writes; how an installed wrapper is recognised.
    static let marker = "# oneclick-wineserver-wrapper v1"

    public let runtimeRoot: URL

    public init(runtimeRoot: URL) { self.runtimeRoot = runtimeRoot }
    public init(wineBinary: URL) { self.init(runtimeRoot: WineRuntimeLayout(wineBinary: wineBinary).root) }

    var server: URL { runtimeRoot.appendingPathComponent("bin/wineserver") }
    var realServer: URL { runtimeRoot.appendingPathComponent("bin/wineserver.real") }
    var installedDylib: URL { runtimeRoot.appendingPathComponent("lib/oneclick/wineserver_fix.dylib") }

    /// The wrapper script. `regsaveLog` receives one line per deferred/allowed save (diagnostics).
    static func wrapperScript(regsaveLog: URL) -> String {
        """
        #!/bin/sh
        \(marker)
        # Starts the real wineserver with OneClick's registry-save / UDP fix injected (see WineserverTuning).
        here="$(cd "$(dirname "$0")" && pwd)"
        fix="$here/../lib/oneclick/wineserver_fix.dylib"
        if [ -f "$fix" ]; then
          export DYLD_INSERT_LIBRARIES="$fix${DYLD_INSERT_LIBRARIES:+:$DYLD_INSERT_LIBRARIES}"
          export REGSAVE_LOG="${REGSAVE_LOG:-\(regsaveLog.path)}"
        fi
        exec "$here/wineserver.real" "$@"

        """
    }

    /// Whether `bin/wineserver` is currently OneClick's wrapper.
    public func isInstalled(fileManager fm: FileManager = .default) -> Bool {
        guard let head = try? String(contentsOf: server, encoding: .utf8) else { return false }   // binary → not UTF-8
        return head.contains(Self.marker) && fm.fileExists(atPath: realServer.path)
    }

    /// Install (or refresh) the wrapper. `dylib` is the build's `wineserver_fix.dylib`; it is copied into the
    /// runtime so the app bundle can move without breaking the wrapper. Returns whether anything changed.
    @discardableResult
    public func install(dylib: URL, regsaveLog: URL, fileManager fm: FileManager = .default) throws -> Bool {
        guard fm.fileExists(atPath: server.path) else { return false }   // not a wine runtime
        var changed = false

        // 1. Copy the dylib in (refresh when the build's copy differs).
        try fm.createDirectory(at: installedDylib.deletingLastPathComponent(), withIntermediateDirectories: true)
        if !fm.contentsEqual(atPath: dylib.path, andPath: installedDylib.path) {
            try? fm.removeItem(at: installedDylib)
            try fm.copyItem(at: dylib, to: installedDylib)
            changed = true
        }

        // 2. Move the real server aside, once. A wrapper already in place is never moved over the real one.
        let alreadyWrapped = (try? String(contentsOf: server, encoding: .utf8))?.contains(Self.marker) == true
        if !alreadyWrapped {
            if fm.fileExists(atPath: realServer.path) { try fm.removeItem(at: realServer) }   // stale leftover
            try fm.moveItem(at: server, to: realServer)
            changed = true
        }

        // 3. Write the wrapper when missing or different.
        let script = Self.wrapperScript(regsaveLog: regsaveLog)
        if (try? String(contentsOf: server, encoding: .utf8)) != script {
            try script.write(to: server, atomically: true, encoding: .utf8)
            try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: server.path)
            changed = true
        }
        return changed
    }

    /// Restore the plain wineserver. Returns whether anything changed.
    @discardableResult
    public func uninstall(fileManager fm: FileManager = .default) throws -> Bool {
        guard isInstalled(fileManager: fm) else { return false }
        try fm.removeItem(at: server)
        try fm.moveItem(at: realServer, to: server)
        try? fm.removeItem(at: installedDylib)
        return true
    }

    /// The `wineserver_fix.dylib` shipped in the running app bundle, if any (absent under `swift run`/tests).
    public static var bundledDylib: URL? {
        Bundle.main.url(forResource: "wineserver_fix", withExtension: "dylib")
    }
}
