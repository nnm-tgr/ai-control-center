import Foundation

struct Project: Identifiable, Sendable, Hashable {
    let id: UUID
    var name: String
    let rootURL: URL
    var agents: [Agent]
    var gitStatus: GitStatus?
    let isGitRepository: Bool
    let discoveredAt: Date
    var lastSeenAt: Date
    var isReachable: Bool

    init(
        id: UUID = UUID(),
        name: String,
        rootURL: URL,
        agents: [Agent] = [],
        gitStatus: GitStatus? = nil,
        isGitRepository: Bool = false,
        discoveredAt: Date = .now,
        lastSeenAt: Date = .now,
        isReachable: Bool = true
    ) {
        self.id = id
        self.name = name
        self.rootURL = rootURL
        self.agents = agents
        self.gitStatus = gitStatus
        self.isGitRepository = isGitRepository
        self.discoveredAt = discoveredAt
        self.lastSeenAt = lastSeenAt
        self.isReachable = isReachable
    }

    /// .ai/agent-status.json のパス
    var statusFileURL: URL {
        rootURL.appending(components: ".ai", "agent-status.json")
    }

    /// updatedAt が最新のエージェントを返す
    var primaryAgent: Agent? {
        agents.max(by: { $0.updatedAt < $1.updatedAt })
    }

    /// エージェント中で最も優先度の高いステータス
    var aggregatedStatus: AgentStatus {
        agents
            .map(\.status)
            .max(by: { $0.priority < $1.priority })
            ?? .idle
    }
}
