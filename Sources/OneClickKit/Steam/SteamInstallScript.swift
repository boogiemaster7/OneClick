import CryptoKit
import Foundation

/// A game's Steam install script (`installscript.vdf`, or a game-specific `*_install_script.vdf` in the install
/// root): the registry keys and first-run installers Steam applies the first time a game is played on Windows —
/// e.g. Anno 1800's writes `HKLM\SOFTWARE\Ubisoft\Anno 1800\installdir` and silently installs Ubisoft Connect.
/// OneClick launches games directly rather than through Steam's Play button, so nothing ran these; OneClick now
/// applies them itself, once per script version (`LaunchOrchestrator.runInstallScript`).
///
/// Pure: parsing does no I/O beyond the text it is handed, so the whole format is unit-tested.
public struct SteamInstallScript: Sendable, Equatable {
    public struct RegistryValue: Sendable, Equatable {
        /// Full key, e.g. `HKEY_LOCAL_MACHINE\SOFTWARE\Ubisoft\Anno 1800`.
        public let key: String
        public let name: String
        /// `REG_SZ` or `REG_DWORD`.
        public let type: String
        public let data: String
    }

    public struct Step: Sendable, Equatable {
        /// The step's name in the script, e.g. `GameLauncher`.
        public let id: String
        public let description: String
        /// Processes in order (`process 1`/`command 1`, `process 2`/…), with `%INSTALLDIR%` resolved to a path
        /// relative to the install directory where possible.
        public let processes: [Process]
    }

    public struct Process: Sendable, Equatable {
        /// The executable as written in the script with `%INSTALLDIR%` stripped, using `/` separators
        /// (`Support/Ubisoft/UbisoftConnectInstaller.exe`). `nil` when it points outside the install dir.
        public let relativePath: String?
        /// The raw value from the script (for logging).
        public let raw: String
        public let arguments: [String]
    }

    public let registry: [RegistryValue]
    public let steps: [Step]

    /// Language used for language-keyed registry values (Steam passes the client language; OneClick is English).
    public static let language = "english"

    /// Find the install script in a game's install root: `installscript.vdf` or `*install*script*.vdf`.
    public static func locate(in installURL: URL, fileManager: FileManager = .default) -> URL? {
        let entries = (try? fileManager.contentsOfDirectory(at: installURL, includingPropertiesForKeys: nil)) ?? []
        return entries
            .filter {
                let name = $0.lastPathComponent.lowercased()
                return name.hasSuffix(".vdf") && name.contains("install") && name.contains("script")
            }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
            .first
    }

    /// Parse the script text. `installDirWindows` replaces `%INSTALLDIR%` in registry data
    /// (e.g. `C:\Program Files (x86)\Steam\steamapps\common\Anno 1800`).
    public static func parse(_ text: String, installDirWindows: String) throws -> SteamInstallScript {
        let root = try KeyValuesParser().parse(text: text)
        guard let script = root["InstallScript"] else { return SteamInstallScript(registry: [], steps: []) }

        var registry: [RegistryValue] = []
        for keyPair in script["Registry"]?.pairs ?? [] {
            for typePair in keyPair.value.pairs {
                let type: String
                switch typePair.key.lowercased() {
                case "string": type = "REG_SZ"
                case "dword": type = "REG_DWORD"
                default: continue                                   // binary/other: not used by known scripts
                }
                for valuePair in typePair.value.pairs {
                    if let data = valuePair.value.stringValue {
                        registry.append(RegistryValue(key: keyPair.key, name: valuePair.key, type: type,
                                                      data: substitute(data, installDirWindows)))
                    } else if valuePair.key.caseInsensitiveCompare(language) == .orderedSame {
                        // Language-keyed block: { "english" { "language" "en-US" } }
                        for inner in valuePair.value.pairs {
                            guard let data = inner.value.stringValue else { continue }
                            registry.append(RegistryValue(key: keyPair.key, name: inner.key, type: type,
                                                          data: substitute(data, installDirWindows)))
                        }
                    }
                }
            }
        }

        var steps: [Step] = []
        for stepPair in script["Run Process"]?.pairs ?? [] {
            let node = stepPair.value
            // Steps limited to an older Windows (e.g. a VC++ 2015 redist for "Windows 7") don't apply to the
            // Windows 10 Wine reports.
            if let os = node["Requirement_OS"]?["OSType"]?.stringValue,
               !os.lowercased().contains("windows 10"), !os.lowercased().contains("windows 11") { continue }
            var processes: [Process] = []
            for index in 1...16 {
                guard let raw = node["process \(index)"]?.stringValue else { break }
                let command = node["command \(index)"]?.stringValue ?? ""
                processes.append(Process(relativePath: relativeToInstallDir(raw), raw: raw,
                                         arguments: command.split(whereSeparator: \.isWhitespace).map(String.init)))
            }
            guard !processes.isEmpty else { continue }
            steps.append(Step(id: stepPair.key, description: node["description"]?.stringValue ?? stepPair.key,
                              processes: processes))
        }
        return SteamInstallScript(registry: registry, steps: steps)
    }

    /// A short, stable fingerprint of the script text, so a changed script runs again.
    public static func fingerprint(_ text: String) -> String {
        String(SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined().prefix(16))
    }

    /// The Windows path Wine shows for `url` in `prefix`: `drive_c/...` → `C:\...`, anything else → `Z:\...`
    /// (Wine maps the Mac's `/` to Z:).
    public static func windowsPath(for url: URL, prefix: URL) -> String {
        let driveC = prefix.appendingPathComponent("drive_c").standardizedFileURL.path
        let path = url.standardizedFileURL.path
        if path == driveC || path.hasPrefix(driveC + "/") {
            return "C:" + String(path.dropFirst(driveC.count)).replacingOccurrences(of: "/", with: "\\")
        }
        return "Z:" + path.replacingOccurrences(of: "/", with: "\\")
    }

    private static func substitute(_ value: String, _ installDir: String) -> String {
        value.replacingOccurrences(of: "%INSTALLDIR%", with: installDir, options: .caseInsensitive)
    }

    private static func relativeToInstallDir(_ raw: String) -> String? {
        let token = "%INSTALLDIR%"
        guard raw.range(of: token, options: [.caseInsensitive, .anchored]) != nil else { return nil }
        var rest = String(raw.dropFirst(token.count)).replacingOccurrences(of: "\\", with: "/")
        while rest.hasPrefix("/") { rest.removeFirst() }
        return rest.isEmpty || rest.contains("..") ? nil : rest
    }
}

/// What applying an install script did, for status and logging.
public struct InstallScriptOutcome: Sendable, Equatable {
    public var registryWritten = 0
    public var stepsRun: [String] = []
    /// Steps that couldn't run or exited non-zero: `"<id>: <reason>"`.
    public var problems: [String] = []
}

extension LaunchOrchestrator {
    /// Apply a game's install script inside the Steam bottle: registry values (written to both registry views,
    /// since Steam — a 32-bit process — writes HKLM through WOW6432Node), then each step's processes in order,
    /// run to completion with the bottle's msync env so they share its wineserver. Never throws: problems are
    /// collected so one failing redistributable can't block the game.
    public func runInstallScript(
        _ script: SteamInstallScript, installURL: URL, prefix: URL, wine: URL
    ) async -> InstallScriptOutcome {
        var outcome = InstallScriptOutcome()
        let env = OneClick.msyncWineEnvironment(prefix: prefix, wine: wine)

        for value in script.registry {
            for view in ["/reg:32", "/reg:64"] {
                let result = try? await processRunner.run(
                    executable: wine,
                    arguments: ["reg", "add", value.key, "/v", value.name, "/t", value.type, "/d", value.data,
                                "/f", view],
                    environment: env, currentDirectory: nil)
                if result?.succeeded == true { outcome.registryWritten += 1 }
                else { outcome.problems.append("registry \(value.key)\\\(value.name) \(view): failed") }
            }
        }

        for step in script.steps {
            for process in step.processes {
                guard let relative = process.relativePath else {
                    outcome.problems.append("\(step.id): \(process.raw) is outside the install folder")
                    continue
                }
                let exe = installURL.appendingPathComponent(relative)
                guard FileManager.default.fileExists(atPath: exe.path) else {
                    outcome.problems.append("\(step.id): \(relative) not found")
                    continue
                }
                do {
                    let result = try await processRunner.run(
                        executable: wine, arguments: [exe.path] + process.arguments,
                        environment: env, currentDirectory: exe.deletingLastPathComponent())
                    if !result.succeeded { outcome.problems.append("\(step.id): exited \(result.exitCode)") }
                } catch {
                    outcome.problems.append("\(step.id): \(error.localizedDescription)")
                }
            }
            outcome.stepsRun.append(step.id)
        }
        return outcome
    }
}
