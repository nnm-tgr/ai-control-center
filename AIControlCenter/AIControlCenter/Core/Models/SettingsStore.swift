import Foundation
import Observation

@Observable
final class SettingsStore: @unchecked Sendable {
    private(set) var settings: Settings

    private enum Keys {
        static let watchedRootPaths = "watchedRootPaths"
        static let scanDepth = "scanDepth"
        static let excludedDirectoryNames = "excludedDirectoryNames"
        static let preferredTerminal = "preferredTerminal"
        static let notificationsEnabled = "notificationsEnabled"
        static let notificationLevel = "notificationLevel"
        static let doNotDisturbEnabled = "doNotDisturbEnabled"
        static let gitIntegrationEnabled = "gitIntegrationEnabled"
        static let gitPollInterval = "gitPollInterval"
        static let showMenuBarIcon = "showMenuBarIcon"
        static let activityRetentionCount = "activityRetentionCount"
        static let launchAtLogin = "launchAtLogin"
    }

    init() {
        settings = SettingsStore.load()
    }

    func update(_ mutation: (inout Settings) -> Void) {
        mutation(&settings)
        save(settings)
    }

    private static func load() -> Settings {
        let defaults = UserDefaults.standard
        let paths = defaults.stringArray(forKey: Keys.watchedRootPaths) ?? []
        let rootURLs = paths.map { URL(filePath: $0) }

        let terminalRaw = defaults.string(forKey: Keys.preferredTerminal) ?? ""
        let terminal = TerminalProviderType(rawValue: terminalRaw) ?? .terminal

        let levelRaw = defaults.integer(forKey: Keys.notificationLevel)
        let level = NotificationLevel(rawValue: levelRaw) ?? .normal

        return Settings(
            watchedRootURLs: rootURLs,
            scanDepth: defaults.integer(forKey: Keys.scanDepth).nonZero(default: 3),
            excludedDirectoryNames: defaults.stringArray(forKey: Keys.excludedDirectoryNames)
                ?? Settings.defaultExcludedNames,
            preferredTerminal: terminal,
            notificationsEnabled: defaults.bool(forKey: Keys.notificationsEnabled, default: true),
            notificationLevel: level,
            doNotDisturbEnabled: defaults.bool(forKey: Keys.doNotDisturbEnabled, default: false),
            gitIntegrationEnabled: defaults.bool(forKey: Keys.gitIntegrationEnabled, default: true),
            gitPollInterval: defaults.double(forKey: Keys.gitPollInterval).nonZero(default: 30),
            showMenuBarIcon: defaults.bool(forKey: Keys.showMenuBarIcon, default: true),
            activityRetentionCount: defaults.integer(forKey: Keys.activityRetentionCount).nonZero(default: 200),
            launchAtLogin: defaults.bool(forKey: Keys.launchAtLogin, default: false)
        )
    }

    private func save(_ settings: Settings) {
        let defaults = UserDefaults.standard
        defaults.set(settings.watchedRootURLs.map(\.path), forKey: Keys.watchedRootPaths)
        defaults.set(settings.scanDepth, forKey: Keys.scanDepth)
        defaults.set(settings.excludedDirectoryNames, forKey: Keys.excludedDirectoryNames)
        defaults.set(settings.preferredTerminal.rawValue, forKey: Keys.preferredTerminal)
        defaults.set(settings.notificationsEnabled, forKey: Keys.notificationsEnabled)
        defaults.set(settings.notificationLevel.rawValue, forKey: Keys.notificationLevel)
        defaults.set(settings.doNotDisturbEnabled, forKey: Keys.doNotDisturbEnabled)
        defaults.set(settings.gitIntegrationEnabled, forKey: Keys.gitIntegrationEnabled)
        defaults.set(settings.gitPollInterval, forKey: Keys.gitPollInterval)
        defaults.set(settings.showMenuBarIcon, forKey: Keys.showMenuBarIcon)
        defaults.set(settings.activityRetentionCount, forKey: Keys.activityRetentionCount)
        defaults.set(settings.launchAtLogin, forKey: Keys.launchAtLogin)
    }
}

// MARK: - Helpers

private extension Int {
    func nonZero(default value: Int) -> Int { self == 0 ? value : self }
}

private extension Double {
    func nonZero(default value: Double) -> Double { self == 0 ? value : self }
}

private extension UserDefaults {
    func bool(forKey key: String, default value: Bool) -> Bool {
        object(forKey: key) == nil ? value : bool(forKey: key)
    }
}
