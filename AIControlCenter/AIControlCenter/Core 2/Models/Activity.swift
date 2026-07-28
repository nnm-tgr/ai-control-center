import Foundation

/// エージェントの状態変化を記録するログエントリ。
/// activities 配列は古い順（追記順）で保持する。UI では .reversed() で表示すること。
struct Activity: Identifiable, Sendable, Hashable {
    let id: UUID
    let agentID: UUID
    let status: AgentStatus
    let task: String?
    let workflowPhase: WorkflowPhase?
    let timestamp: Date
    var duration: TimeInterval?

    init(
        id: UUID = UUID(),
        agentID: UUID,
        status: AgentStatus,
        task: String? = nil,
        workflowPhase: WorkflowPhase? = nil,
        timestamp: Date = .now,
        duration: TimeInterval? = nil
    ) {
        self.id = id
        self.agentID = agentID
        self.status = status
        self.task = task
        self.workflowPhase = workflowPhase
        self.timestamp = timestamp
        self.duration = duration
    }

    /// 今日なら HH:mm、昨日以前なら MM/dd HH:mm
    var formattedTimestamp: String {
        let calendar = Calendar.current
        if calendar.isDateInToday(timestamp) {
            return timestamp.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits))
        } else {
            return timestamp.formatted(.dateTime.month(.twoDigits).day(.twoDigits).hour(.twoDigits(amPM: .omitted)).minute(.twoDigits))
        }
    }

    /// duration を "3m 12s" 形式にフォーマット
    var formattedDuration: String? {
        guard let duration else { return nil }
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        if minutes > 0 {
            return "\(minutes)m \(seconds)s"
        } else {
            return "\(seconds)s"
        }
    }
}
