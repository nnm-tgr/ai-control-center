import Foundation

enum AgentStatus: String, Codable, Sendable, CaseIterable {
    case idle = "idle"
    case thinking = "thinking"
    case runningCommand = "running_command"
    case waitingUser = "waiting_user"
    case completed = "completed"
    case error = "error"

    var displayName: String {
        switch self {
        case .idle: "Idle"
        case .thinking: "Thinking"
        case .runningCommand: "Running"
        case .waitingUser: "Waiting"
        case .completed: "Done"
        case .error: "Error"
        }
    }

    /// 複数エージェントの aggregatedStatus 判定に使用。値が大きいほど優先
    var priority: Int {
        switch self {
        case .idle: 0
        case .thinking: 1
        case .completed: 1
        case .runningCommand: 2
        case .waitingUser: 4
        case .error: 5
        }
    }
}

/// Dashboard のフィルター用グループ
enum StatusGroup: String, CaseIterable, Sendable {
    case all = "All"
    case needsAttention = "Needs Attention"
    case active = "Active"
    case passive = "Passive"

    var statuses: [AgentStatus] {
        switch self {
        case .all: AgentStatus.allCases
        case .needsAttention: [.waitingUser, .error]
        case .active: [.thinking, .runningCommand]
        case .passive: [.idle, .completed]
        }
    }
}
