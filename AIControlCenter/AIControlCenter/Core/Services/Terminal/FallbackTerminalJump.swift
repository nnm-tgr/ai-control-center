import AppKit

/// AppleScript 自動化権限が拒否された場合のフォールバック処理 (T114b)
///
/// 1. `cd '<path>'` をクリップボードにコピー
/// 2. ターミナルアプリを NSWorkspace で起動
/// 3. 呼び出し元がインラインバナーを表示する
enum FallbackTerminalJump {

    @MainActor
    static func execute(workingDirectory: URL, terminalBundleID: String) throws {
        let escaped = workingDirectory.path.shellEscaped
        let command = "cd \(escaped)"

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(command, forType: .string)

        guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: terminalBundleID)
                ?? NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Terminal") else {
            throw AppError.terminal(.providerNotAvailable(name: terminalBundleID))
        }

        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        NSWorkspace.shared.openApplication(at: appURL, configuration: config)
    }
}

// MARK: - Shell Escaping

extension String {
    /// シングルクォートでラップし、パス内のシングルクォートをエスケープする
    var shellEscaped: String {
        "'\(replacingOccurrences(of: "'", with: "'\\''"))'"
    }
}
