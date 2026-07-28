import Foundation

enum AgentType: String, Codable, Sendable, CaseIterable {
    case claudeCode = "claude-code"
    case cursor = "cursor"
    case openaiCodex = "openai-codex"
    case geminiCLI = "gemini-cli"
    case aider = "aider"
    case unknown = "unknown"

    /// 未知の文字列は .unknown にフォールバック（アプリをクラッシュさせない）
    init(rawString: String) {
        self = AgentType(rawValue: rawString) ?? .unknown
    }

    var displayName: String {
        switch self {
        case .claudeCode: "Claude Code"
        case .cursor: "Cursor"
        case .openaiCodex: "OpenAI Codex"
        case .geminiCLI: "Gemini CLI"
        case .aider: "Aider"
        case .unknown: "Unknown"
        }
    }

    var iconSystemName: String {
        switch self {
        case .claudeCode: "sparkles"
        case .cursor: "cursorarrow.rays"
        case .openaiCodex: "brain"
        case .geminiCLI: "star.circle"
        case .aider: "terminal"
        case .unknown: "questionmark.circle"
        }
    }
}
