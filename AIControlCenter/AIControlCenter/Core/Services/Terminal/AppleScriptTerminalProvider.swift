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

    /// 既存ターミナルセッションにフォーカスする。
    ///
    /// proc_listpids(PROC_ALL_PIDS) は App Sandbox でブロックされるため使わない。
    /// 代わりに:
    ///   Step 1: Apple Events で各タブの TTY パスを取得
    ///   Step 2: sysctl(KERN_PROC_TTY) で各 TTY に紐づく PID を取得
    ///   Step 3: proc_pidinfo(pid, PROC_PIDVNODEPATHINFO) で CWD を取得
    ///   Step 4: CWD が一致したタブを Apple Events でフォーカス
    func jumpToExisting(workingDirectory: URL) async throws -> Bool {
        guard !NSRunningApplication.runningApplications(
            withBundleIdentifier: providerType.bundleIdentifier
        ).isEmpty else { return false }

        let targetPath = workingDirectory.path
        let parentPath = URL(fileURLWithPath: targetPath).deletingLastPathComponent().path

        let ttyPaths = try await fetchTTYPaths()

        // Pass 1: exact match or cwd inside project
        for ttyPath in ttyPaths {
            for pid in pidsForTTY(ttyPath) {
                guard let cwd = cwdForPID(pid) else { continue }
                if cwd == targetPath || cwd.hasPrefix(targetPath + "/") {
                    return try await focusByTTY(ttyPath: ttyPath)
                }
            }
        }

        // Pass 2: cwd == direct parent of project root
        // (common when user launched Claude Code from the repo root)
        if parentPath != "/" {
            for ttyPath in ttyPaths {
                for pid in pidsForTTY(ttyPath) {
                    guard let cwd = cwdForPID(pid) else { continue }
                    if cwd == parentPath {
                        return try await focusByTTY(ttyPath: ttyPath)
                    }
                }
            }
        }

        return false
    }

    // MARK: - TTY Path List via Apple Events

    private func fetchTTYPaths() async throws -> [String] {
        let appName = appleScriptAppName
        let script: String
        switch providerType {
        case .terminal:
            script = """
tell application "\(appName)"
    set out to ""
    set wc to count of windows
    repeat with wi from 1 to wc
        set tc to count of tabs of window wi
        repeat with ti from 1 to tc
            set out to out & (tty of tab ti of window wi) & linefeed
        end repeat
    end repeat
    return out
end tell
"""
        case .iTerm2:
            script = """
tell application "\(appName)"
    set out to ""
    repeat with w in windows
        set tc to count of tabs of w
        repeat with ti from 1 to tc
            repeat with s in sessions of tab ti of w
                set out to out & (tty of s) & linefeed
            end repeat
        end repeat
    end repeat
    return out
end tell
"""
        default:
            return []
        }

        let raw = try await runAppleScriptReturning(script)
        return raw.components(separatedBy: "\n").map {
            $0.trimmingCharacters(in: .whitespaces)
        }.filter { !$0.isEmpty }
    }

    // MARK: - PID Lookup via sysctl(KERN_PROC_TTY)

    /// sysctl(CTL_KERN, KERN_PROC, KERN_PROC_TTY, dev) — no proc_listpids needed.
    private func pidsForTTY(_ ttyPath: String) -> [pid_t] {
        var sb = stat()
        guard Darwin.lstat(ttyPath, &sb) == 0 else { return [] }
        let dev = Int32(bitPattern: UInt32(truncatingIfNeeded: sb.st_rdev))

        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_TTY, dev]
        var size = 0
        guard sysctl(&mib, 4, nil, &size, nil, 0) == 0, size > 0 else { return [] }

        let count = size / MemoryLayout<kinfo_proc>.size
        var buffer = [kinfo_proc](repeating: kinfo_proc(), count: count + 1)
        let ret = buffer.withUnsafeMutableBytes { ptr in
            sysctl(&mib, 4, ptr.baseAddress, &size, nil, 0)
        }
        guard ret == 0 else { return [] }

        return buffer.compactMap { p in
            let pid = p.kp_proc.p_pid
            return pid > 0 ? pid : nil
        }
    }

    // MARK: - CWD via proc_pidinfo(PROC_PIDVNODEPATHINFO)

    // Empirically verified on Darwin 25 (macOS 15): pvi_cdir.vip_path at offset 152.
    private static let cwdPathOffset = 152

    private func cwdForPID(_ pid: pid_t) -> String? {
        var buffer = [UInt8](repeating: 0, count: 8192)
        let ret = buffer.withUnsafeMutableBytes {
            Darwin.proc_pidinfo(pid, 9, 0, $0.baseAddress, Int32($0.count))
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

    // MARK: - Focus via Apple Events

    private func focusByTTY(ttyPath: String) async throws -> Bool {
        let appName = appleScriptAppName
        let escaped = ttyPath.replacingOccurrences(of: "\"", with: "\\\"")

        let script: String
        switch providerType {
        case .terminal:
            script = """
tell application "\(appName)"
    activate
    set targetTTY to "\(escaped)"
    set wc to count of windows
    repeat with wi from 1 to wc
        set tc to count of tabs of window wi
        repeat with ti from 1 to tc
            if (tty of tab ti of window wi) is equal to targetTTY then
                tell window wi
                    set frontmost to true
                    set selected of tab ti to true
                end tell
                return
            end if
        end repeat
    end repeat
end tell
"""
        case .iTerm2:
            script = """
tell application "\(appName)"
    activate
    set targetTTY to "\(escaped)"
    repeat with w in windows
        set tc to count of tabs of w
        repeat with ti from 1 to tc
            repeat with s in sessions of tab ti of w
                if (tty of s) is equal to targetTTY then
                    set current window to w
                    tell w
                        set current tab to tab ti
                    end tell
                    return
                end if
            end repeat
        end repeat
    end repeat
end tell
"""
        default:
            return false
        }

        try await runAppleScript(script, terminalName: providerType.displayName)
        return true
    }

    // MARK: - AppleScript Helpers

    /// open() と同じくアプリ名で tell する（application id は -600 になりやすい）
    private var appleScriptAppName: String {
        switch providerType {
        case .terminal: "Terminal"
        case .iTerm2: "iTerm2"
        default: providerType.displayName
        }
    }

    /// -1743: TCC Automation 拒否
    /// -600: サンドボックス/権限で Apple Events が届かないときによく出る誤診メッセージ
    private func mapAppleScriptError(_ error: NSDictionary, terminalName: String) -> AppError {
        let code = error[NSAppleScript.errorNumber] as? Int ?? 0
        if code == -1743 || code == -600 {
            return .terminal(.automationPermissionDenied(terminalName: terminalName))
        }
        let reason = error[NSAppleScript.errorMessage] as? String ?? "Unknown error"
        return .terminal(.activationFailed(reason: reason))
    }

    private func runAppleScriptReturning(_ source: String) async throws -> String {
        return try await withCheckedThrowingContinuation { continuation in
            var error: NSDictionary?
            let result = NSAppleScript(source: source)?.executeAndReturnError(&error)
            if let error {
                continuation.resume(throwing: mapAppleScriptError(
                    error, terminalName: providerType.displayName
                ))
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
            NSAppleScript(source: source)?.executeAndReturnError(&error)
            if let error {
                continuation.resume(throwing: mapAppleScriptError(error, terminalName: terminalName))
            } else {
                continuation.resume()
            }
        }
    }
}
