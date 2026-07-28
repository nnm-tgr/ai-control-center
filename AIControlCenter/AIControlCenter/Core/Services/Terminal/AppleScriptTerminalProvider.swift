import AppKit

/// Terminal.app と iTerm2 向け AppleScript 実装
struct AppleScriptTerminalProvider: TerminalProvider {
    let providerType: TerminalProviderType
    var supportsFallback: Bool { true }

    func open(workingDirectory: URL) async throws {
        let script = appleScript(for: providerType, path: workingDirectory.path)
        try await runAppleScript(script, terminalName: providerType.displayName)
    }

    // MARK: - AppleScript Templates

    private func appleScript(for type: TerminalProviderType, path: String) -> String {
        let escaped = path.replacingOccurrences(of: "\"", with: "\\\"")
        switch type {
        case .terminal:
            return """
            tell application "Terminal"
                activate
                do script "cd \\"\(escaped)\\""
            end tell
            """
        case .iTerm2:
            return """
            tell application "iTerm2"
                activate
                create window with default profile
                tell current session of current window
                    write text "cd \\"\(escaped)\\""
                end tell
            end tell
            """
        default:
            return ""
        }
    }

    // MARK: - Execution

    private func runAppleScript(_ source: String, terminalName: String) async throws {
        guard !source.isEmpty else {
            throw AppError.terminal(.providerNotAvailable(name: terminalName))
        }

        return try await withCheckedThrowingContinuation { continuation in
            var error: NSDictionary?
            let script = NSAppleScript(source: source)
            script?.executeAndReturnError(&error)

            if let error {
                let code = error[NSAppleScript.errorNumber] as? Int ?? 0
                if code == -1743 {
                    // -1743: Automation permission denied by user
                    continuation.resume(throwing: AppError.terminal(
                        .automationPermissionDenied(terminalName: terminalName)
                    ))
                } else {
                    let reason = error[NSAppleScript.errorMessage] as? String ?? "Unknown error"
                    continuation.resume(throwing: AppError.terminal(
                        .activationFailed(reason: reason)
                    ))
                }
            } else {
                continuation.resume()
            }
        }
    }
}
