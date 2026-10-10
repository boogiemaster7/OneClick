import Foundation
import Testing
@testable import OneClickKit

@Suite("Steam install scripts")
struct SteamInstallScriptTests {
    /// Trimmed from Anno 1800's `anno1800_install_script.vdf` (Steam 916440).
    static let anno = #"""
    "InstallScript"
    {
        "Registry"
        {
            "HKEY_LOCAL_MACHINE\\SOFTWARE\\Ubisoft\\Anno 1800"
            {
                "string"
                {
                    "installdir"        "%INSTALLDIR%"
                }
                "string"
                {
                    "english" { "language" "en-US" }
                    "german"  { "language" "de-DE" }
                }
            }
        }
        "Run Process"
        {
            "DirectX"
            {
                "process 1"     "%INSTALLDIR%\\Support\\DirectX\\DXSETUP.exe"
                "command 1"     "/silent"
                "NoCleanUp"     "1"
                "description"   "DirectX End-User Runtimes"
            }
            "Redist"
            {
                "process 1"     "%INSTALLDIR%\\Support\\Redist\\redist_2015_Update3\\VC_redist.x64.exe"
                "command 1"     "/silent"
                "description"   "MS Visual C++ Redistributable"
                "Requirement_OS" { "OSType" "Windows 7" }
            }
            "GameLauncher"
            {
                "process 1"     "%INSTALLDIR%\\Support\\Ubisoft\\UbisoftConnectInstaller.exe"
                "command 1"     "/S"
                "description"   "Ubisoft Connect Client"
            }
            "Shaders"
            {
                "process 1"     "%INSTALLDIR%\\Bin\\Win64\\cleanup.exe"
                "command 1"     "home shaders"
                "description"   "Refreshing shaders"
            }
        }
    }
    "kvsignatures" { "InstallScript" "5f52" }
    """#

    static let dir = #"C:\Program Files (x86)\Steam\steamapps\common\Anno 1800"#

    @Test("Registry: %INSTALLDIR% is substituted and the English language block is picked")
    func registry() throws {
        let script = try SteamInstallScript.parse(Self.anno, installDirWindows: Self.dir)
        let key = #"HKEY_LOCAL_MACHINE\SOFTWARE\Ubisoft\Anno 1800"#
        #expect(script.registry == [
            .init(key: key, name: "installdir", type: "REG_SZ", data: Self.dir),
            .init(key: key, name: "language", type: "REG_SZ", data: "en-US"),
        ])
    }

    @Test("Steps: Windows-7-only steps are skipped; paths are relative to the install dir")
    func steps() throws {
        let script = try SteamInstallScript.parse(Self.anno, installDirWindows: Self.dir)
        #expect(script.steps.map(\.id) == ["DirectX", "GameLauncher", "Shaders"])
        let launcher = try #require(script.steps.first { $0.id == "GameLauncher" })
        #expect(launcher.processes == [.init(relativePath: "Support/Ubisoft/UbisoftConnectInstaller.exe",
                                             raw: #"%INSTALLDIR%\Support\Ubisoft\UbisoftConnectInstaller.exe"#,
                                             arguments: ["/S"])])
        #expect(script.steps.last?.processes.first?.arguments == ["home", "shaders"])
    }

    @Test("Paths outside the install dir are not run; a script without InstallScript is empty")
    func outsideAndEmpty() throws {
        let outside = #""InstallScript" { "Run Process" { "X" { "process 1" "C:\\Windows\\evil.exe" } } }"#
        let script = try SteamInstallScript.parse(outside, installDirWindows: Self.dir)
        #expect(script.steps.first?.processes.first?.relativePath == nil)
        let traversal = #""InstallScript" { "Run Process" { "X" { "process 1" "%INSTALLDIR%\\..\\x.exe" } } }"#
        #expect(try SteamInstallScript.parse(traversal, installDirWindows: Self.dir).steps.first?.processes.first?.relativePath == nil)
        #expect(try SteamInstallScript.parse(#""Other" { }"#, installDirWindows: Self.dir) == .init(registry: [], steps: []))
    }

    @Test("Windows paths: drive_c maps to C:, anything else to Z:; fingerprint changes with the text")
    func pathsAndFingerprint() {
        let prefix = URL(fileURLWithPath: "/b/SteamBottle")
        #expect(SteamInstallScript.windowsPath(
            for: prefix.appendingPathComponent("drive_c/Program Files (x86)/Steam/steamapps/common/Anno 1800"),
            prefix: prefix) == Self.dir)
        #expect(SteamInstallScript.windowsPath(for: URL(fileURLWithPath: "/Volumes/Games/Anno"), prefix: prefix)
                == #"Z:\Volumes\Games\Anno"#)
        #expect(SteamInstallScript.fingerprint("a") != SteamInstallScript.fingerprint("b"))
        #expect(SteamInstallScript.fingerprint("a").count == 16)
    }

    @Test("Locate finds the game-specific script name in the install root")
    func locate() throws {
        let tmp = try TempDir(); defer { tmp.cleanup() }
        try "x".write(to: tmp.url.appendingPathComponent("anno1800_install_script.vdf"), atomically: true, encoding: .utf8)
        try "x".write(to: tmp.url.appendingPathComponent("other.vdf"), atomically: true, encoding: .utf8)
        #expect(SteamInstallScript.locate(in: tmp.url)?.lastPathComponent == "anno1800_install_script.vdf")
    }

    @Test("Running writes each registry value to both views and runs present installers with their args")
    func run() async throws {
        let tmp = try TempDir(); defer { tmp.cleanup() }
        let install = tmp.url.appendingPathComponent("Anno 1800")
        try tmp.makeDir("Anno 1800/Support/Ubisoft")
        FileManager.default.createFile(
            atPath: install.appendingPathComponent("Support/Ubisoft/UbisoftConnectInstaller.exe").path, contents: Data())
        let script = try SteamInstallScript.parse(Self.anno, installDirWindows: Self.dir)
        let fake = FakeProcessRunner()
        let wine = URL(fileURLWithPath: "/w/bin/wine64")
        let outcome = await LaunchOrchestrator(runner: fake, linker: GraphicsLinker())
            .runInstallScript(script, installURL: install, prefix: tmp.url.appendingPathComponent("pfx"), wine: wine)

        #expect(outcome.registryWritten == 4)                       // 2 values × 2 registry views
        let regViews = fake.invocations.filter { $0.arguments.first == "reg" }.map { $0.arguments.last }
        #expect(regViews == ["/reg:32", "/reg:64", "/reg:32", "/reg:64"])
        let installer = try #require(fake.invocations.first { $0.arguments.first?.hasSuffix("UbisoftConnectInstaller.exe") == true })
        #expect(installer.arguments.dropFirst() == ["/S"])
        #expect(installer.environment["WINEMSYNC"] == "1")
        // DXSETUP and cleanup.exe aren't in this fake install: reported, not run, and the launch isn't blocked.
        #expect(outcome.problems.contains { $0.hasPrefix("DirectX:") && $0.hasSuffix("not found") })
        #expect(outcome.stepsRun == ["DirectX", "GameLauncher", "Shaders"])
    }
}
