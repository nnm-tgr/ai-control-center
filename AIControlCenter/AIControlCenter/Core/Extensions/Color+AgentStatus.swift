import SwiftUI

extension AgentStatus {
    /// ステータスに対応するシステムカラー。ダークモード対応は自動
    var color: Color {
        switch self {
        case .idle: .secondary
        case .thinking: .blue
        case .runningCommand: .yellow
        case .waitingUser: .orange
        case .completed: .green
        case .error: .red
        }
    }
}
