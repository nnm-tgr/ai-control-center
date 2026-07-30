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
        // Escape for AppleScript string literal
        let asPath = path
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")

        // Strategy: iterate Terminal.app tabs via AppleScript to get each tab's TTY device,
        // then run a targeted shell command per TTY to check only that shell process's CWD.
        // This avoids the broad lsof +d scan which triggers permission errors for system processes.
        //
        // Per-tab shell pipeline:
        //   ps -t <tty> -o pid=   → PID of the foreground shell on that TTY
        //   lsof -p <pid> -d cwd  → CWD of that specific process (no broad scan, no permission errors)
        switch type {
        case .terminal:
            return #"""
set projectPath to "\#(asPath)"
tell application "Terminal"
    activate
    repeat with w in windows
        repeat with t in tabs of w
            set tabTTY to tty of t
            set cwdResult to ""
            try
                set cwdResult to do shell script "pid=$(ps -t $(echo " & tabTTY & " | sed 's|/dev/||') -o pid= 2>/dev/null | head -1 | tr -d ' '); [ -n \"$pid\" ] && lsof -p $pid -d cwd -Fn 2>/dev/null | grep '^n' | cut -c2- || true"
            end try
            if cwdResult = projectPath then
                set frontmost of w to true
                set selected of t to true
                return true
            end if
        end repeat
    end repeat
end tell
return false
"""#
        case .iTerm2:
            return #"""
set projectPath to "\#(asPath)"
tell application "iTerm2"
    activate
    repeat with w in windows
        repeat with t in tabs of w
            repeat with s in sessions of t
                set sessionTTY to tty of s
                set cwdResult to ""
                try
                    set cwdResult to do shell script "pid=$(ps -t $(echo " & sessionTTY & " | sed 's|/dev/||') -o pid= 2>/dev/null | head -1 | tr -d ' '); [ -n \"$pid\" ] && lsof -p $pid -d cwd -Fn 2>/dev/null | grep '^n' | cut -c2- || true"
                end try
                if cwdResult = projectPath then
                    set current window to w
                    set current tab of w to t
                    return true
                end if
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
