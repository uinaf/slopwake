import Foundation

public struct WakePreferences: Equatable, Sendable {
    public static let currentSchemaVersion = 1
    public static let defaultBatteryCutoffPercentage = 15
    public static let supportedBatteryCutoffs: [Int?] = [nil, 5, 10, 15, 20, 25, 30]

    public var enabledSurfaces: Set<AgentSurface>
    public var preventsDisplaySleep: Bool
    public var batteryCutoffPercentage: Int?
    public var startsAtLogin: Bool

    public init(
        enabledSurfaces: Set<AgentSurface> = Set(AgentSurface.allCases),
        preventsDisplaySleep: Bool = false,
        batteryCutoffPercentage: Int? = Self.defaultBatteryCutoffPercentage,
        startsAtLogin: Bool = false
    ) {
        self.enabledSurfaces = enabledSurfaces
        self.preventsDisplaySleep = preventsDisplaySleep
        self.batteryCutoffPercentage = Self.normalizedBatteryCutoffPercentage(
            batteryCutoffPercentage
        )
        self.startsAtLogin = startsAtLogin
    }

    public static func load(from defaults: UserDefaults) -> WakePreferences {
        let schemaVersion = defaults.integer(forKey: Keys.schemaVersion)
        let legacyAutomaticEnabled = defaults.object(forKey: Keys.legacyAutomaticEnabled)
            .map { _ in defaults.bool(forKey: Keys.legacyAutomaticEnabled) }
        var enabledSurfaces: Set<AgentSurface> = []
        for surface in AgentSurface.allCases {
            let key = Keys.surface(surface)
            let enabled: Bool
            if defaults.object(forKey: key) != nil {
                enabled = defaults.bool(forKey: key)
            } else if schemaVersion == 0, let legacyAutomaticEnabled {
                enabled = legacyAutomaticEnabled
            } else {
                enabled = true
            }
            if enabled {
                enabledSurfaces.insert(surface)
            }
        }

        let cutoff: Int?
        if defaults.object(forKey: Keys.batteryCutoffPercentage) == nil {
            cutoff = defaultBatteryCutoffPercentage
        } else {
            let persisted = defaults.integer(forKey: Keys.batteryCutoffPercentage)
            cutoff = persisted == 0 ? nil : persisted
        }

        let preferences = WakePreferences(
            enabledSurfaces: enabledSurfaces,
            preventsDisplaySleep: defaults.bool(forKey: Keys.preventsDisplaySleep),
            batteryCutoffPercentage: cutoff,
            startsAtLogin: defaults.bool(forKey: Keys.startsAtLogin)
        )
        if schemaVersion == 0, legacyAutomaticEnabled != nil {
            preferences.save(to: defaults)
            defaults.removeObject(forKey: Keys.legacyAutomaticEnabled)
        }
        return preferences
    }

    public func save(to defaults: UserDefaults) {
        defaults.set(
            max(defaults.integer(forKey: Keys.schemaVersion), Self.currentSchemaVersion),
            forKey: Keys.schemaVersion
        )
        for surface in AgentSurface.allCases {
            defaults.set(enabledSurfaces.contains(surface), forKey: Keys.surface(surface))
        }
        defaults.set(preventsDisplaySleep, forKey: Keys.preventsDisplaySleep)
        defaults.set(batteryCutoffPercentage ?? 0, forKey: Keys.batteryCutoffPercentage)
        defaults.set(startsAtLogin, forKey: Keys.startsAtLogin)
    }

    public static func normalizedBatteryCutoffPercentage(_ percentage: Int?) -> Int? {
        guard let percentage, percentage > 0 else {
            return nil
        }
        return min(max(percentage, 5), 30)
    }

    private enum Keys {
        static let schemaVersion = "preferences.schema-version"
        static let legacyAutomaticEnabled = "automatic-detection-enabled"
        static let preventsDisplaySleep = "prevents-display-sleep"
        static let batteryCutoffPercentage = "battery-cutoff-percentage"
        static let startsAtLogin = "starts-at-login"

        static func surface(_ surface: AgentSurface) -> String {
            "detector.\(surface.rawValue).enabled"
        }
    }
}
