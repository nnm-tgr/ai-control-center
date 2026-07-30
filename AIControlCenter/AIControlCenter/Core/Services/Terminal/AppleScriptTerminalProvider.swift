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

    // MARK: - Jump to Existing Session

    /// 既存のターミナルウィンドウ/タブで projectDirectory にいるセッションにフォーカスする。
    /// 見つかれば true、一致なしは false を返す。
    func jumpToExisting(workingDirectory: URL) async throws -> Bool {
        let script = jumpScript(for: providerType, path: workingDirectory.path)
        guard !script.isEmpty else { return false }
        return try await runAppleScriptReturningBool(script, terminalName: providerType.displayName)
    }

    private func jumpScript(for type: TerminalProviderType, path: String) -> String {
        // Escape for AppleScript string literal (\\ and \" are the only special sequences)
        let asPath = path
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")

        // do shell script: lsof finds PIDs with CWD = project path, ps maps PID → TTY.
        // Runs via osascript (outside app sandbox). Path passed via AppleScript's
        // `quoted form of` to safely handle spaces and special characters.
        // `+d` restricts lsof to the exact directory; `-d cwd` narrows to the cwd descriptor.
        let ttyBlock = #"""
set projectPath to "\#(asPath)"
set ttyOutput to ""
try
    set ttyOutput to do shell script "lsof -a -d cwd -Fp +d " & quoted form of projectPath & " 2>/dev/null | sed 's/^p//' | while read pid; do ps -p $pid -o tty= 2>/dev/null; done | tr -d ' ' | grep -v '??' | sort -u | sed 's|^|/dev/tty|'"
end try
set ttyList to paragraphs of ttyOutput
"""#

        switch type {
        case .terminal:
            return ttyBlock + #"""

tell application "Terminal"
    activate
    repeat with w in windows
        repeat with t in tabs of w
            repeat with tt in ttyList
                if tt is not "" and tty of t is equal to tt then
                    set frontmost of w to true
                    set selected of t to true
                    return true
                end if
            end repeat
        end repeat
    end repeat
end tell
return false
"""#
        case .iTerm2:
            return ttyBlock + #"""

tell application "iTerm2"
    activate
    repeat with w in windows
        repeat with t in tabs of w
            repeat with s in sessions of t
                repeat with tt in ttyList
                    if tt is not "" and tty of s is equal to tt then
                        set current window to w
                        set current tab of w to t
                        return true
                    end if
                end repeat
            end repeat
        end repeat
    end repeat
end tell
return false
"""#
        default:
            return ""
        }
    }

    // MARK: - Execution

    private func runAppleScriptReturningBool(_ source: String, terminalName: String) async throws -> Bool {
        return try await withCheckedThrowingContinuation { continuation in
            var error: NSDictionary?
            let script = NSAppleScript(source: source)
            let result = script?.executeAndReturnError(&error)
            if let error {
                let code = error[NSAppleScript.errorNumber] as? Int ?? 0
                if code == -1743 {
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
                continuation.resume(returning: result?.booleanValue ?? false)
            }
        }
    }

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
