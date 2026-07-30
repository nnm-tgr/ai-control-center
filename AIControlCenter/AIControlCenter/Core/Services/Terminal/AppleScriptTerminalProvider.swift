import AppKit
import Darwin

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

    /// 指定ディレクトリにいる既存のターミナルセッションにフォーカスする。
    /// lsof を使わず proc_pidinfo (Swift直接呼び出し) + ps -t でCWDを取得する。
    func jumpToExisting(workingDirectory: URL) async throws -> Bool {
        switch providerType {
        case .terminal:
            return try await jumpInTerminalApp(workingDirectory: workingDirectory)
        case .iTerm2:
            return try await jumpInITerm2(workingDirectory: workingDirectory)
        default:
            return false
        }
    }

    // MARK: - CWD via proc_pidinfo (no lsof, no subprocess)
    //
    // proc_vnodepathinfo layout (sys/proc_info.h):
    //   vinfo_stat:       152 bytes
    //   vnode_info:       vinfo_stat(152) + vi_type(4) + vi_pad(4) + vi_fsid(8) = 168 bytes
    //   vnode_info_path:  vnode_info(168) + vip_path[MAXPATHLEN=1024]
    //   pvi_cdir.vip_path starts at offset 168

    private static let cwdPathOffset = 168

    private func cwdForPID(_ pid: pid_t) -> String? {
        var buffer = [UInt8](repeating: 0, count: 8192)
        let ret = buffer.withUnsafeMutableBytes {
            Darwin.proc_pidinfo(pid, 9 /* PROC_PIDVNODEPATHINFO */, 0, $0.baseAddress, Int32($0.count))
        }
        guard ret > 0 else { return nil }
        return buffer.withUnsafeBytes { raw in
            let cStr = raw.baseAddress!
                .advanced(by: Self.cwdPathOffset)
                .assumingMemoryBound(to: CChar.self)
            let s = String(cString: cStr)
            return s.isEmpty ? nil : s
        }
    }

    // MARK: - Terminal.app

    private struct TabInfo {
        let windowIndex: Int
        let tabIndex: Int
        let pid: pid_t
    }

    private func jumpInTerminalApp(workingDirectory: URL) async throws -> Bool {
        // One AppleScript call that returns "wi:ti:pid\n" lines.
        // Uses `ps -t <tty>` per tab — lightweight, no lsof, no permission errors.
        let infoScript = """
tell application "Terminal"
    set out to ""
    repeat with wi from 1 to count of windows
        repeat with ti from 1 to count of tabs of window wi
            set ttyPath to tty of tab ti of window wi
            set p to ""
            try
                set p to do shell script "ps -t " & quoted form of ttyPath & " -o pid= 2>/dev/null | head -1 | tr -d ' '"
            end try
            if p is not "" then
                set out to out & wi & ":" & ti & ":" & p & linefeed
            end if
        end repeat
    end repeat
    return out
end tell
"""
        let raw = try await runAppleScriptReturningString(infoScript, terminalName: providerType.displayName)

        for tab in parseTabInfo(from: raw) {
            guard let cwd = cwdForPID(tab.pid), cwd == workingDirectory.path else { continue }
            let focusScript = """
tell application "Terminal"
    activate
    set frontmost of window \(tab.windowIndex) to true
    set selected of tab \(tab.tabIndex) of window \(tab.windowIndex) to true
end tell
"""
            try await runAppleScript(focusScript, terminalName: providerType.displayName)
            return true
        }
        return false
    }

    // MARK: - iTerm2

    private func jumpInITerm2(workingDirectory: URL) async throws -> Bool {
        let infoScript = """
tell application "iTerm2"
    set out to ""
    repeat with wi from 1 to count of windows
        repeat with ti from 1 to count of tabs of window wi
            repeat with s in sessions of tab ti of window wi
                set ttyPath to tty of s
                set p to ""
                try
                    set p to do shell script "ps -t " & quoted form of ttyPath & " -o pid= 2>/dev/null | head -1 | tr -d ' '"
                end try
                if p is not "" then
                    set out to out & wi & ":" & ti & ":" & p & linefeed
                end if
            end repeat
        end repeat
    end repeat
    return out
end tell
"""
        let raw = try await runAppleScriptReturningString(infoScript, terminalName: providerType.displayName)

        for tab in parseTabInfo(from: raw) {
            guard let cwd = cwdForPID(tab.pid), cwd == workingDirectory.path else { continue }
            let focusScript = """
tell application "iTerm2"
    activate
    set current window to window \(tab.windowIndex)
    set current tab of window \(tab.windowIndex) to tab \(tab.tabIndex) of window \(tab.windowIndex)
end tell
"""
            try await runAppleScript(focusScript, terminalName: providerType.displayName)
            return true
        }
        return false
    }

    private func parseTabInfo(from raw: String) -> [TabInfo] {
        raw.components(separatedBy: "\n").compactMap { line in
            let parts = line.components(separatedBy: ":")
            guard parts.count == 3,
                  let wi = Int(parts[0]),
                  let ti = Int(parts[1]),
                  let pid = pid_t(parts[2].trimmingCharacters(in: .whitespaces))
            else { return nil }
            return TabInfo(windowIndex: wi, tabIndex: ti, pid: pid)
        }
    }

    // MARK: - Execution

    private func runAppleScriptReturningString(_ source: String, terminalName: String) async throws -> String {
        return try await withCheckedThrowingContinuation { continuation in
            var error: NSDictionary?
            let result = NSAppleScript(source: source)?.executeAndReturnError(&error)
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
                continuation.resume(returning: result?.stringValue ?? "")
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
