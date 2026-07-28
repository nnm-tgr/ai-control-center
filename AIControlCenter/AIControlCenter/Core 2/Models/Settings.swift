import Foundation

struct Settings: Sendable {
    var watchedRootURLs: [URL]
    var scanDepth: Int
    var excludedDirectoryNames: [String]
    var preferredTerminal: TerminalProviderType
    var notificationsEnabled: Bool
    var notificationLevel: NotificationLevel
    var doNotDisturbEnabled: Bool
    var gitIntegrationEnabled: Bool
    var gitPollInterval: TimeInterval
    var showMenuBarIcon: Bool
    var activityRetentionCount: Int
    var launchAtLogin: Bool

    init(
        watchedRootURLs: [URL] = [],
        scanDepth: Int = 3,
        excludedDirectoryNames: [String] = Self.defaultExcludedNames,
        preferredTerminal: TerminalProviderType = .terminal,
        notificationsEnabled: Bool = true,
        notificationLevel: NotificationLevel = .normal,
        doNotDisturbEnabled: Bool = false,
        gitIntegrationEnabled: Bool = true,
        gitPollInterval: TimeInterval = 30,
        showMenuBarIcon: Bool = true,
        activityRetentionCount: Int = 200,
        launchAtLogin: Bool = false
    ) {
        self.watchedRootURLs = watchedRootURLs
        self.scanDepth = scanDepth
        self.excludedDirectoryNames = excludedDirectoryNames
        self.preferredTerminal = preferredTerminal
        self.notificationsEnabled = notificationsEnabled
        self.notificationLevel = notificationLevel
        self.doNotDisturbEnabled = doNotDisturbEnabled
        self.gitIntegrationEnabled = gitIntegrationEnabled
        self.gitPollInterval = gitPollInterval
        self.showMenuBarIcon = showMenuBarIcon
        self.activityRetentionCount = activityRetentionCount
        self.launchAtLogin = launchAtLogin
    }

    static let defaultExcludedNames: [String] = [
        ".git", ".svn", "node_modules", ".build", ".swiftpm",
        "DerivedData", ".gradle", "target", "__pycache__",
        ".venv", "venv", ".tox", "vendor", "Pods", "Carthage",
        ".yarn", ".pnpm", "dist", "build", "out", ".next", ".nuxt"
    ]

    /// FSEventStream コールバック内で参照する除外セグメントの Set（値コピー渡し用）
    var excludedDirectoryNamesSet: Set<String> {
        Set(excludedDirectoryNames)
    }
}
