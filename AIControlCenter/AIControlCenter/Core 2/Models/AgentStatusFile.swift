import Foundation

/// agent-status.json の Decodable 表現。
/// ドメインモデル（Agent）とは別に定義し、JSON 仕様変更の影響をこのレイヤで吸収する。
/// 未知フィールドは additionalProperties のデフォルト動作で無視される。
struct AgentStatusFile: Decodable, Sendable {
    let schemaVersion: String
    let agent: String
    let status: String
    let task: String?
    let workflowPhase: String?
    let progress: Double?
    let branch: String?
    let worktree: String?
    let startedAt: String?
    let updatedAt: String
    let errorMessage: String?
    let metadata: [String: String]?

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case agent
        case status
        case task
        case workflowPhase = "workflow_phase"
        case progress
        case branch
        case worktree
        case startedAt = "started_at"
        case updatedAt = "updated_at"
        case errorMessage = "error_message"
        case metadata
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        // schema_version は省略可能。省略時は "1.0" をデフォルトとする
        schemaVersion = (try? container.decodeIfPresent(String.self, forKey: .schemaVersion)) ?? "1.0"
        agent = try container.decode(String.self, forKey: .agent)
        status = try container.decode(String.self, forKey: .status)
        task = try container.decodeIfPresent(String.self, forKey: .task)
        workflowPhase = try container.decodeIfPresent(String.self, forKey: .workflowPhase)
        progress = try container.decodeIfPresent(Double.self, forKey: .progress)
        branch = try container.decodeIfPresent(String.self, forKey: .branch)
        worktree = try container.decodeIfPresent(String.self, forKey: .worktree)
        startedAt = try container.decodeIfPresent(String.self, forKey: .startedAt)
        updatedAt = try container.decode(String.self, forKey: .updatedAt)
        errorMessage = try container.decodeIfPresent(String.self, forKey: .errorMessage)
        metadata = try container.decodeIfPresent([String: String].self, forKey: .metadata)
    }

    /// ISO 8601 文字列を Date に変換するユーティリティ
    func parseDate(_ string: String?) -> Date? {
        guard let string else { return nil }
        return ISO8601DateFormatter().date(from: string)
    }

    var updatedAtDate: Date {
        parseDate(updatedAt) ?? .now
    }

    var startedAtDate: Date? {
        parseDate(startedAt)
    }
}
