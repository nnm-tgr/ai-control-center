import Foundation

/// ターミナルアプリの抽象インターフェース
protocol TerminalProvider: Sendable {
    var providerType: TerminalProviderType { get }
    /// AppleScript フォールバックをサポートするか（自動化権限拒否時に clipboard コピーで代替）
    var supportsFallback: Bool { get }
    /// 指定ディレクトリで新しいターミナルウィンドウを開く
    func open(workingDirectory: URL) async throws
}

extension TerminalProvider {
    var supportsFallback: Bool { true }
}
