import Foundation

struct ToolApprovalRequest: Identifiable, Sendable {
    let id: UUID
    let projectID: UUID
    let projectName: String
    let sessionID: String
    let tool: String
    let input: [String: String]
    let requestedAt: Date
    let timeoutSeconds: Int
    let pendingFileURL: URL

    var commandPreview: String? { input["command"] ?? input["file_path"] }
}

struct ToolApprovalResponse: Codable, Sendable {
    let schemaVersion: String
    let sessionID: String
    let decision: Decision
    let decidedAt: Date

    enum Decision: String, Codable { case allow, deny }

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case sessionID = "session_id"
        case decision
        case decidedAt = "decided_at"
    }
}
