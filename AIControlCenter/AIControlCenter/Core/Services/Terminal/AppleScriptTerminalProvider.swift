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
    ///
    /// 方針: do shell script (ps / lsof) を一切使わない。
    ///   1. AppleScript: Terminal.app の全タブの TTY パスを取得（Apple Events のみ）
    ///   2. Swift: stat() で TTY の device number を取得
    ///   3. Swift: proc_listpids + proc_pidinfo で全プロセスを走査、
    ///             controlling terminal と CWD が一致するプロセスを探す
    ///   4. AppleScript: 一致したウィンドウ/タブをフォーカス（Apple Events のみ）
    ///
    /// 上記はサブプロセスを一切起動しないため、lsof / ps が引き起こす
    /// "task name port right" 等の権限エラーが発生しない。
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

    // MARK: - Process Info (Swift direct calls, no subprocess)

    // proc_vnodepathinfo layout (sys/proc_info.h):
    //   vinfo_stat  = 152 bytes
    //   vnode_info  = vinfo_stat(152) + vi_type(4) + vi_pad(4) + vi_fsid(8) = 168 bytes
    //   pvi_cdir.vip_path starts at offset 168 within proc_vnodepathinfo
    private static let cwdPathOffset = 168

    // proc_bsdinfo layout (sys/proc_info.h):
    //   pbi_flags(4) + pbi_status(4) + pbi_xstatus(4) + pbi_pid(4) + pbi_ppid(4)
    //   + uid/gid * 3 pairs(24) + rfu_1(4) + pbi_comm[16](16) + pbi_name[32](32)
    //   + pbi_nfiles(4) + pbi_pgid(4) + pbi_pjobc(4) → e_tdev at offset 108
    private static let eTdevOffset = 108

    /// CWD of a process via proc_pidinfo(PROC_PIDVNODEPATHINFO=9). No subprocess.
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

    /// Controlling terminal device number via proc_pidinfo(PROC_PIDTBSDINFO=3). No subprocess.
    private func ttyDeviceForPID(_ pid: pid_t) -> dev_t? {
        var buffer = [UInt8](repeating: 0, count: 2048)
        let ret = buffer.withUnsafeMutableBytes {
            Darwin.proc_pidinfo(pid, 3, 0, $0.baseAddress, Int32($0.count))
        }
        guard ret > 0 else { return nil }
        let raw = buffer.withUnsafeBytes { $0 }
        let devU32 = raw.baseAddress!
            .advanced(by: Self.eTdevOffset)
            .assumingMemoryBound(to: UInt32.self)
            .pointee
        // 0xFFFFFFFF == NODEV (no controlling terminal)
        guard devU32 != 0xFFFF_FFFF, devU32 != 0 else { return nil }
        return dev_t(Int32(bitPattern: devU32))
    }

    /// All running PIDs via proc_listpids(PROC_ALL_PIDS=1). No subprocess.
    private func allPIDs() -> [pid_t] {
        let sizeHint = Darwin.proc_listpids(1, 0, nil, 0)
        guard sizeHint > 0 else { return [] }
        let capacity = Int(sizeHint) / MemoryLayout<pid_t>.size + 32
        var pids = [pid_t](repeating: 0, count: capacity)
        let written = pids.withUnsafeMutableBytes {
            Darwin.proc_listpids(1, 0, $0.baseAddress, Int32($0.count))
        }
        let count = Int(written) / MemoryLayout<pid_t>.size
        return Array(pids.prefix(count)).filter { $0 > 0 }
    }

    /// Device number (st_rdev) of a TTY path, e.g. "/dev/ttys001".
    /// Uses lstat to avoid the Swift naming collision between the stat struct and stat() function.
    private func deviceNumber(for ttyPath: String) -> dev_t? {
        var sb = stat()
        guard Darwin.lstat(ttyPath, &sb) == 0 else { return nil }
        return sb.st_rdev
    }

    // MARK: - Terminal.app

    private struct TabInfo {
        let windowIndex: Int
        let tabIndex: Int
        let ttyPath: String
    }

    private func jumpInTerminalApp(workingDirectory: URL) async throws -> Bool {
        // Pure Apple Events — no do shell script
        let ttyScript = """
tell application "Terminal"
    set out to ""
    repeat with wi from 1 to count of windows
        repeat with ti from 1 to count of tabs of window wi
            set out to out & wi & ":" & ti & ":" & (tty of tab ti of window wi) & linefeed
        end repeat
    end repeat
    return out
end tell
"""
        let raw = try await runAppleScriptReturningString(ttyScript, terminalName: providerType.displayName)
        return try await findAndFocus(
            tabs: parseTabInfo(from: raw),
            workingDirectory: workingDirectory,
            focusScript: { wi, ti in
                """
tell application "Terminal"
    activate
    set frontmost of window \(wi) to true
    set selected of tab \(ti) of window \(wi) to true
end tell
"""
            }
        )
    }

    // MARK: - iTerm2

    private func jumpInITerm2(workingDirectory: URL) async throws -> Bool {
        let ttyScript = """
tell application "iTerm2"
    set out to ""
    repeat with wi from 1 to count of windows
        repeat with ti from 1 to count of tabs of window wi
            repeat with s in sessions of tab ti of window wi
                set out to out & wi & ":" & ti & ":" & (tty of s) & linefeed
            end repeat
        end repeat
    end repeat
    return out
end tell
"""
        let raw = try await runAppleScriptReturningString(ttyScript, terminalName: providerType.displayName)
        return try await findAndFocus(
            tabs: parseTabInfo(from: raw),
            workingDirectory: workingDirectory,
            focusScript: { wi, ti in
                """
tell application "iTerm2"
    activate
    set current window to window \(wi)
    set current tab of window \(wi) to tab \(ti) of window \(wi)
end tell
"""
            }
        )
    }

    // MARK: - Matching Logic

    private func findAndFocus(
        tabs: [TabInfo],
        workingDirectory: URL,
        focusScript: (Int, Int) -> String
    ) async throws -> Bool {
        // Map device number → tab info
        var deviceToTab: [dev_t: TabInfo] = [:]
        for tab in tabs {
            if let dev = deviceNumber(for: tab.ttyPath) {
                deviceToTab[dev] = tab
            }
        }
        guard !deviceToTab.isEmpty else { return false }

        // Scan all PIDs: proc_pidinfo calls do not spawn subprocesses
        for pid in allPIDs() {
            guard let ttyDev = ttyDeviceForPID(pid),
                  let tab = deviceToTab[ttyDev],
                  let cwd = cwdForPID(pid),
                  cwd == workingDirectory.path
            else { continue }

            try await runAppleScript(
                focusScript(tab.windowIndex, tab.tabIndex),
                terminalName: providerType.displayName
            )
            return true
        }
        return false
    }

    private func parseTabInfo(from raw: String) -> [TabInfo] {
        // Line format: "wi:ti:/dev/ttysXXX"
        raw.components(separatedBy: "\n").compactMap { line in
            let parts = line.split(separator: ":", maxSplits: 2, omittingEmptySubsequences: false)
            guard parts.count == 3,
                  let wi = Int(parts[0]),
                  let ti = Int(parts[1])
            else { return nil }
            let tty = String(parts[2]).trimmingCharacters(in: .whitespaces)
            return tty.isEmpty ? nil : TabInfo(windowIndex: wi, tabIndex: ti, ttyPath: tty)
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
            NSAppleScript(source: source)?.executeAndReturnError(&error)

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
