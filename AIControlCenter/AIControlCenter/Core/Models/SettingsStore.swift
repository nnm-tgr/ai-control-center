import Foundation
import Observation

@Observable
final class SettingsStore: @unchecked Sendable {
    private(set) var settings: Settings

    private enum Keys {
        static let watchedRootPaths = "watchedRootPaths"
        static let securityBookmarks = "securityBookmarks"
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
        static let approvalEnabled = "approvalEnabled"
        static let approvalTimeoutSeconds = "approvalTimeoutSeconds"
    }

    init() {
        settings = SettingsStore.load()
    }

    func update(_ mutation: (inout Settings) -> Void) {
        mutation(&settings)
        save(settings)
    }

    // MARK: - Security-Scoped Bookmarks

    /// NSOpenPanel で選択された URL の security-scoped bookmark を永続化する
    func createBookmark(for url: URL) {
        guard let data = try? url.bookmarkData(
            options: .withSecurityScope,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        ) else { return }
        var bookmarks = storedBookmarks()
        bookmarks[url.path] = data
        UserDefaults.standard.set(bookmarks, forKey: Keys.securityBookmarks)
    }

    func removeBookmark(for url: URL) {
        var bookmarks = storedBookmarks()
        bookmarks.removeValue(forKey: url.path)
        UserDefaults.standard.set(bookmarks, forKey: Keys.securityBookmarks)
    }

    /// アプリ起動時に呼び出し、保存済みブックマークをすべてアクティブ化する
    /// アクセス可能になった URL の配列を返す
    @discardableResult
    func activateAllBookmarks() -> [URL] {
        var accessible: [URL] = []
        for (_, data) in storedBookmarks() {
            var stale = false
            guard let url = try? URL(
                resolvingBookmarkData: data,
                options: .withSecurityScope,
                relativeTo: nil,
                bookmarkDataIsStale: &stale
            ) else { continue }
            guard url.startAccessingSecurityScopedResource() else { continue }
            accessible.append(url)
            if stale { createBookmark(for: url) }
        }
        return accessible
    }

    private func storedBookmarks() -> [String: Data] {
        UserDefaults.standard.dictionary(forKey: Keys.securityBookmarks) as? [String: Data] ?? [:]
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
            launchAtLogin: defaults.bool(forKey: Keys.launchAtLogin, default: false),
            approvalEnabled: defaults.bool(forKey: Keys.approvalEnabled, default: false),
            approvalTimeoutSeconds: defaults.integer(forKey: Keys.approvalTimeoutSeconds).nonZero(default: 30)
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
        defaults.set(settings.approvalEnabled, forKey: Keys.approvalEnabled)
        defaults.set(settings.approvalTimeoutSeconds, forKey: Keys.approvalTimeoutSeconds)
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
