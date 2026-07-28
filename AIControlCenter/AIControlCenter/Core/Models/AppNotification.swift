import Foundation

enum NotificationLevel: Int, Comparable, Sendable, CaseIterable, Codable {
    case low = 1
    case normal = 2
    case high = 3
    case critical = 4

    static func < (lhs: NotificationLevel, rhs: NotificationLevel) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    var displayName: String {
        switch self {
        case .low: "Low"
        case .normal: "Normal"
        case .high: "High"
        case .critical: "Critical"
        }
    }
}

struct StatusTransition: Sendable {
    let from: AgentStatus?
    let to: AgentStatus
    let projectName: String
    let taskName: String?
}

struct AppNotification: Identifiable, Sendable {
    let id: UUID
    let projectID: UUID
    let agentID: UUID
    let level: NotificationLevel
    let title: String
    let body: String
    let triggeredBy: StatusTransition
    let createdAt: Date
    var isRead: Bool

    init(
        id: UUID = UUID(),
        projectID: UUID,
        agentID: UUID,
        level: NotificationLevel,
        title: String,
        body: String,
        triggeredBy: StatusTransition,
        createdAt: Date = .now,
        isRead: Bool = false
    ) {
        self.id = id
        self.projectID = projectID
        self.agentID = agentID
        self.level = level
        self.title = title
        self.body = body
        self.triggeredBy = triggeredBy
        self.createdAt = createdAt
        self.isRead = isRead
    }

    /// UNNotificationRequest の identifier に使用
    var notificationIdentifier: String {
        "ai-control-center.\(projectID.uuidString).\(triggeredBy.to.rawValue)"
    }
}

/// Dashboard のインラインバナー通知
struct BannerMessage: Identifiable, Sendable {
    let id: UUID
    let message: String
    let level: BannerLevel
    let autoDismissAfter: TimeInterval?

    init(
        id: UUID = UUID(),
        message: String,
        level: BannerLevel = .info,
        autoDismissAfter: TimeInterval? = 8
    ) {
        self.id = id
        self.message = message
        self.level = level
        self.autoDismissAfter = autoDismissAfter
    }

    enum BannerLevel: Sendable {
        case info
        case warning
        case error
    }
}
