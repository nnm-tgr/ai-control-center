import Foundation
import Observation

@Observable
@MainActor
final class AppState {

    // MARK: - Projects

    private(set) var projects: [Project] = []
    private(set) var isScanning: Bool = false

    // MARK: - Settings

    var settings: Settings {
        didSet { settingsStore.update { $0 = settings } }
    }

    // MARK: - Notifications

    private(set) var notifications: [AppNotification] = []
    var pendingBanners: [BannerMessage] = []

    var unreadCount: Int { notifications.filter { !$0.isRead }.count }

    // MARK: - Error

    private(set) var lastError: AppError?

    // MARK: - Services

    private let scanner = ProjectScannerService()
    private let watcher = FileWatcherService()
    private let settingsStore: SettingsStore

    // MARK: - Init

    init(settingsStore: SettingsStore = SettingsStore()) {
        self.settingsStore = settingsStore
        self.settings = settingsStore.settings
    }

    // MARK: - Lifecycle

    func start() async {
        await refresh()
        startWatcher()
    }

    func stop() {
        watcher.stop()
    }

    // MARK: - Scan

    func refresh() async {
        guard !isScanning else { return }
        isScanning = true
        defer { isScanning = false }

        let discovered = await scanner.scan(roots: settings.watchedRootURLs, settings: settings)
        mergeProjects(discovered)
    }

    // MARK: - File Watcher

    private func startWatcher() {
        watcher.start(roots: settings.watchedRootURLs, excludedNames: settings.excludedDirectoryNamesSet)

        Task { [weak self] in
            guard let self else { return }
            // watcher の agentByProjectID 変化を polling で拾う（Sprint 6: AsyncStream 化予定）
            while !Task.isCancelled {
                self.applyWatcherUpdates()
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    private func applyWatcherUpdates() {
        for (projectID, newAgent) in watcher.agentByProjectID {
            guard let idx = projects.firstIndex(where: { $0.id == projectID }) else { continue }
            var project = projects[idx]

            if let agentIdx = project.agents.firstIndex(where: { $0.id == newAgent.id }) {
                let oldAgent = project.agents[agentIdx]
                project.agents[agentIdx] = newAgent
                if oldAgent.status != newAgent.status {
                    recordTransition(from: oldAgent.status, to: newAgent.status, in: project, agent: newAgent)
                }
            } else {
                project.agents.append(newAgent)
            }
            project.lastSeenAt = .now
            projects[idx] = project
        }

        if let error = watcher.lastError {
            lastError = error
        }
    }

    // MARK: - Project Merging

    private func mergeProjects(_ discovered: [Project]) {
        var existing = Dictionary(uniqueKeysWithValues: projects.map { ($0.id, $0) })

        for new in discovered {
            if var current = existing[new.id] {
                // 既存プロジェクトは agents / lastSeenAt を更新
                current.agents = new.agents.isEmpty ? current.agents : new.agents
                current.lastSeenAt = .now
                current.isReachable = true
                existing[new.id] = current
            } else {
                existing[new.id] = new
            }
        }

        // スキャンで見つからなかった既存プロジェクトは isReachable = false にする
        let discoveredIDs = Set(discovered.map(\.id))
        for id in existing.keys where !discoveredIDs.contains(id) {
            existing[id]?.isReachable = false
        }

        projects = Array(existing.values).sorted { $0.name < $1.name }
    }

    // MARK: - Notifications

    private func recordTransition(
        from oldStatus: AgentStatus,
        to newStatus: AgentStatus,
        in project: Project,
        agent: Agent
    ) {
        let transition = StatusTransition(
            from: oldStatus,
            to: newStatus,
            projectName: project.name,
            taskName: agent.currentTask
        )
        let level: NotificationLevel = newStatus == .error || newStatus == .waitingUser ? .high : .normal
        let notification = AppNotification(
            projectID: project.id,
            agentID: agent.id,
            level: level,
            title: "\(project.name) — \(newStatus.displayName)",
            body: agent.currentTask ?? "",
            triggeredBy: transition
        )
        notifications.append(notification)
    }

    func markAllRead() {
        for i in notifications.indices { notifications[i].isRead = true }
    }

    func dismissBanner(_ id: UUID) {
        pendingBanners.removeAll { $0.id == id }
    }

    // MARK: - Settings Sync

    func updateSettings(_ mutation: (inout Settings) -> Void) {
        mutation(&settings)
        // 監視ルートが変わった場合はウォッチャーを再起動
        watcher.stop()
        startWatcher()
    }

    // MARK: - Project Access

    func project(for id: UUID) -> Project? {
        projects.first { $0.id == id }
    }
}
