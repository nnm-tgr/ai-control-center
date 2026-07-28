import Foundation

struct Agent: Identifiable, Sendable, Hashable {
    let id: UUID
    let projectID: UUID
    var agentType: AgentType
    var status: AgentStatus
    var currentTask: String?
    var workflowPhase: WorkflowPhase?
    var progress: Double?
    var branch: String?
    var worktreePath: URL?
    var startedAt: Date?
    var updatedAt: Date
    /// 古い順（追記順）で保持。activities[0] が最古、activities.last が最新。
    /// UI での表示は .reversed() で逆順にすること。
    var activities: [Activity]
    var schemaVersion: String

    private let maxActivityCount = 200

    init(
        id: UUID = UUID(),
        projectID: UUID,
        agentType: AgentType,
        status: AgentStatus,
        currentTask: String? = nil,
        workflowPhase: WorkflowPhase? = nil,
        progress: Double? = nil,
        branch: String? = nil,
        worktreePath: URL? = nil,
        startedAt: Date? = nil,
        updatedAt: Date = .now,
        activities: [Activity] = [],
        schemaVersion: String = "1.0"
    ) {
        self.id = id
        self.projectID = projectID
        self.agentType = agentType
        self.status = status
        self.currentTask = currentTask
        self.workflowPhase = workflowPhase
        self.progress = progress
        self.branch = branch
        self.worktreePath = worktreePath
        self.startedAt = startedAt
        self.updatedAt = updatedAt
        self.activities = activities
        self.schemaVersion = schemaVersion
    }

    /// 直前のステータス（activities.last が最新エントリ）
    var previousStatus: AgentStatus? {
        activities.last?.status
    }

    /// 現在のステータスが継続している時間
    var elapsedSinceLastChange: TimeInterval {
        Date.now.timeIntervalSince(updatedAt)
    }

    /// ユーザーのアクションが必要な状態か
    var needsAttention: Bool {
        status == .waitingUser || status == .error
    }

    /// Activity を末尾に追加し、最大件数を超えた場合は最古エントリを削除
    mutating func appendActivity(_ activity: Activity) {
        activities.append(activity)
        if activities.count > maxActivityCount {
            activities.removeFirst()
        }
    }
}
