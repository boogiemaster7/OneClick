import Foundation

/// A per-game recipe: the recommended graphics backend, launch environment and arguments for one Steam
/// title, plus what is known about it. Profiles are DATA — adding a game means adding a JSON entry to
/// `BundledProfiles`, not writing code. Field names follow highball-db (CC0) where the concepts match.
///
/// A profile only ever supplies **defaults**: a game with no saved `GameConfig` starts from its profile
/// (`AppState.config(for:)`), and the moment the user saves their own settings those win. "Use
/// recommended settings" in the game's settings sheet re-applies the profile on request.
public struct GameProfile: Codable, Sendable, Hashable, Identifiable {
    /// Stable slug, e.g. `manor-lords`.
    public let id: String
    public let title: String
    /// Steam app ID the profile applies to.
    public let steamAppID: Int
    /// Bumped whenever the recommended values change, so the UI can tell a stale config from a current one.
    public let revision: Int
    /// Recommended backend (`GraphicsChoice` raw value). Unknown values degrade to Automatic.
    public let renderer: GraphicsChoice
    /// Recommended launch environment, in the same shape (and with the same tolerant decoding) as a game's
    /// own `EnvFlags`.
    public let env: EnvFlags
    /// Extra arguments for the game executable.
    public let args: [String]
    /// Executable relative to the install dir. `nil` keeps OneClick's auto-detection.
    public let executable: String?
    /// Executable to try when the normal one fails (informational until launch fallbacks land).
    public let fallbackExecutable: String?
    /// Anti-cheat in use (`nil` = none). Kernel anti-cheat titles are unsupported.
    public let anticheat: String?
    /// Known conflicts, e.g. `native-mac-steam`.
    public let conflicts: [String]
    /// Human-readable guidance shown in the game's settings sheet.
    public let notes: String
    /// When these values were last measured on real hardware (`yyyy-MM-dd`), or `nil` if never.
    public let lastVerified: String?

    private enum CodingKeys: String, CodingKey {
        case id, title, revision, renderer, env, args, executable, anticheat, conflicts, notes, lastVerified
        case steamAppID = "steam_appid"
        case fallbackExecutable = "fallback_executable"
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        title = try c.decode(String.self, forKey: .title)
        steamAppID = try c.decode(Int.self, forKey: .steamAppID)
        revision = try c.decodeIfPresent(Int.self, forKey: .revision) ?? 1
        renderer = (try c.decodeIfPresent(String.self, forKey: .renderer)).flatMap(GraphicsChoice.init(rawValue:)) ?? .auto
        env = try c.decodeIfPresent(EnvFlags.self, forKey: .env) ?? EnvFlags()
        args = try c.decodeIfPresent([String].self, forKey: .args) ?? []
        executable = try c.decodeIfPresent(String.self, forKey: .executable)
        fallbackExecutable = try c.decodeIfPresent(String.self, forKey: .fallbackExecutable)
        anticheat = try c.decodeIfPresent(String.self, forKey: .anticheat)
        conflicts = try c.decodeIfPresent([String].self, forKey: .conflicts) ?? []
        notes = try c.decodeIfPresent(String.self, forKey: .notes) ?? ""
        lastVerified = try c.decodeIfPresent(String.self, forKey: .lastVerified)
    }

    /// The `GameConfig` this profile recommends for its game. Only profile-owned fields are set; everything
    /// else keeps `GameConfig`'s defaults.
    public func seededConfig() -> GameConfig {
        GameConfig(appID: steamAppID, envFlags: env, graphics: renderer,
                   executableRelativePath: executable, customArgs: args)
    }

    /// `config` with the profile's recommended values applied, keeping the user's non-profile state (learned
    /// backend, presence strategy, last played, virtual-desktop flag).
    public func applied(to config: GameConfig) -> GameConfig {
        var result = config
        result.envFlags = env
        result.graphics = renderer
        result.executableRelativePath = executable
        result.customArgs = args
        return result
    }

    /// Whether `config` already matches this profile's recommended values.
    public func matches(_ config: GameConfig) -> Bool {
        config.envFlags == env && config.graphics == renderer
            && config.executableRelativePath == executable && config.customArgs == args
    }
}

/// The set of known profiles, keyed by Steam app ID. Pure: `bundled` is decoded from in-binary JSON, so
/// lookups do no I/O and behave identically in tests and in the app.
public struct GameProfileCatalog: Sendable {
    public let profiles: [Int: GameProfile]

    public init(profiles: [GameProfile]) {
        // Last one wins on a duplicate app ID; `BundledProfilesTests` guards against duplicates.
        self.profiles = Dictionary(profiles.map { ($0.steamAppID, $0) }, uniquingKeysWith: { _, new in new })
    }

    /// Decode a list of JSON profile documents, skipping (and reporting) any that fail, so one malformed
    /// entry can't take the others down.
    public static func decode(_ documents: [String]) -> (catalog: GameProfileCatalog, failures: [String]) {
        var decoded: [GameProfile] = []
        var failures: [String] = []
        for document in documents {
            do {
                decoded.append(try JSONDecoder().decode(GameProfile.self, from: Data(document.utf8)))
            } catch {
                failures.append(String(describing: error))
            }
        }
        return (GameProfileCatalog(profiles: decoded), failures)
    }

    /// Profiles compiled into the app (`BundledProfiles.documents`).
    public static let bundled: GameProfileCatalog = decode(BundledProfiles.documents).catalog

    public func profile(for appID: Int) -> GameProfile? { profiles[appID] }
}
