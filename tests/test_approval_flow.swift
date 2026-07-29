#!/usr/bin/env swift
// Test target: ~/dev/personal/ai-control-center
//
// Pass criteria:
//   Test 1: .ai/agent-status.json exists and was updated within the last 5 minutes
//            (= this session's hooks are actively firing → app can see current session)
//   Test 2: ai-status script writes correct JSON and the file reflects the update
//   Test 3: pending.json schema can be parsed correctly
//   Test 4: approval.json can be written and read back correctly
//   Test 5: ai-approve exits 0 when approval is disabled (no blocking)
//   Test 6: ai-approve deny flow → exit 2

import Foundation

var passed = 0
var failed = 0

func check(_ condition: Bool, _ message: String, file: String = #file, line: Int = #line) {
    if condition {
        print("  PASS: \(message)")
        passed += 1
    } else {
        print("  FAIL: \(message) (\(file):\(line))")
        failed += 1
    }
}

let ROOT = NSString(string: "~/dev/personal/ai-control-center").expandingTildeInPath
let AI_DIR = "\(ROOT)/.ai"
let STATUS_FILE = "\(AI_DIR)/agent-status.json"
let PENDING_FILE = "\(AI_DIR)/pending.json"
let APPROVAL_FILE = "\(AI_DIR)/approval.json"
let SETTINGS_FILE = "\(AI_DIR)/settings.json"
let AI_STATUS_SCRIPT = "\(ROOT)/scripts/ai-status"
let APPROVE_SCRIPT = "\(ROOT)/scripts/ai-approve"

let fm = FileManager.default
let isoFmt = ISO8601DateFormatter()

// ──────────────────────────────────────────
// Test 1: 現在のセッションが監視されているか
//   判定基準: updated_at が 5 分以内
//   根拠: hooks は各 Bash/Edit ツール実行前後に ai-status を呼ぶため、
//         アクティブなセッションなら必ず 5 分以内に更新される
// ──────────────────────────────────────────
print("\n=== Test 1: Current session monitoring (5-minute threshold) ===")

check(fm.fileExists(atPath: STATUS_FILE), ".ai/agent-status.json exists")

if let data = try? Data(contentsOf: URL(fileURLWithPath: STATUS_FILE)),
   let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
    check(json["agent"] != nil, "agent field present")
    check(json["status"] != nil, "status field present")
    check(json["updated_at"] != nil, "updated_at field present")

    if let updatedAtStr = json["updated_at"] as? String,
       let date = isoFmt.date(from: updatedAtStr) {
        let age = Date().timeIntervalSince(date)
        check(age < 300, "updated_at within 5 min (age: \(Int(age))s) — current session is monitored")
        if age >= 300 {
            print("    Hint: hooks may not be firing. Try running 'ai-status thinking' manually.")
        }
    } else {
        check(false, "updated_at is valid ISO8601")
    }
} else {
    check(false, "agent-status.json is valid JSON")
}

// ──────────────────────────────────────────
// Test 2: ai-status スクリプトが正しく書き込むか
// ──────────────────────────────────────────
print("\n=== Test 2: ai-status script writes correct JSON ===")

check(fm.fileExists(atPath: AI_STATUS_SCRIPT), "ai-status script exists")
check(fm.isExecutableFile(atPath: AI_STATUS_SCRIPT), "ai-status is executable")

let beforeDate = Date()

let writeProc = Process()
writeProc.executableURL = URL(fileURLWithPath: "/usr/bin/env")
writeProc.arguments = ["bash", AI_STATUS_SCRIPT, "thinking", "--task", "テスト実行中", "--phase", "testing"]
writeProc.standardOutput = FileHandle.nullDevice
writeProc.standardError = FileHandle.nullDevice
try? writeProc.run()
writeProc.waitUntilExit()
check(writeProc.terminationStatus == 0, "ai-status exits 0")

if let data = try? Data(contentsOf: URL(fileURLWithPath: STATUS_FILE)),
   let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
    check(json["status"] as? String == "thinking", "status = thinking after ai-status call")
    check(json["agent"] as? String == "claude-code", "agent = claude-code")
    check(json["workflow_phase"] as? String == "testing", "workflow_phase = testing")
    if let updatedAtStr = json["updated_at"] as? String,
       let date = isoFmt.date(from: updatedAtStr) {
        let age = date.timeIntervalSince(beforeDate)
        check(age >= -1 && age < 10, "updated_at is fresh (written now, age from before: \(String(format: "%.1f", age))s)")
    } else {
        check(false, "updated_at is valid ISO8601 after write")
    }
} else {
    check(false, "agent-status.json readable and valid after write")
}

// ──────────────────────────────────────────
// Test 3: pending.json スキーマ検証
// ──────────────────────────────────────────
print("\n=== Test 3: pending.json schema ===")

let pendingJSON = """
{
  "schema_version": "1.0",
  "session_id": "session_test_001",
  "tool": "Bash",
  "input": {"command": "ls -la /tmp"},
  "requested_at": "2026-07-29T01:00:00Z",
  "timeout_seconds": 30
}
"""

do {
    try pendingJSON.write(toFile: PENDING_FILE, atomically: true, encoding: .utf8)
    check(true, "pending.json written atomically")

    if let data = try? Data(contentsOf: URL(fileURLWithPath: PENDING_FILE)),
       let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
        check(json["session_id"] as? String == "session_test_001", "session_id parsed")
        check(json["tool"] as? String == "Bash", "tool parsed")
        check((json["input"] as? [String: String])?["command"] == "ls -la /tmp", "input.command parsed")
        check(json["timeout_seconds"] as? Int == 30, "timeout_seconds parsed")
        check(json["requested_at"] != nil, "requested_at present")
    } else {
        check(false, "pending.json is valid JSON after write")
    }
    try? fm.removeItem(atPath: PENDING_FILE)
    check(true, "pending.json cleaned up")
} catch {
    check(false, "pending.json write: \(error)")
}

// ──────────────────────────────────────────
// Test 4: approval.json 書き込みと読み戻し
// ──────────────────────────────────────────
print("\n=== Test 4: approval.json write/read ===")

struct ApprovalResponse: Codable {
    let schemaVersion: String
    let sessionID: String
    let decision: String
    let decidedAt: String

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case sessionID = "session_id"
        case decision
        case decidedAt = "decided_at"
    }
}

let now = isoFmt.string(from: Date())
let approvalJSON = """
{
  "schema_version": "1.0",
  "session_id": "session_test_001",
  "decision": "allow",
  "decided_at": "\(now)"
}
"""

do {
    try approvalJSON.write(toFile: APPROVAL_FILE, atomically: true, encoding: .utf8)
    check(true, "approval.json written")

    if let data = try? Data(contentsOf: URL(fileURLWithPath: APPROVAL_FILE)),
       let resp = try? JSONDecoder().decode(ApprovalResponse.self, from: data) {
        check(resp.decision == "allow", "decision = allow")
        check(resp.sessionID == "session_test_001", "session_id matches")
        check(!resp.decidedAt.isEmpty, "decided_at present")
    } else {
        check(false, "approval.json decoded correctly")
    }
    try? fm.removeItem(atPath: APPROVAL_FILE)
    check(true, "approval.json cleaned up")
} catch {
    check(false, "approval.json: \(error)")
}

// ──────────────────────────────────────────
// Test 5: ai-approve — disabled → immediate exit 0
// ──────────────────────────────────────────
print("\n=== Test 5: ai-approve exits 0 when disabled ===")

check(fm.fileExists(atPath: APPROVE_SCRIPT), "ai-approve script exists")
check(fm.isExecutableFile(atPath: APPROVE_SCRIPT), "ai-approve is executable")

let proc = Process()
proc.executableURL = URL(fileURLWithPath: "/usr/bin/env")
proc.arguments = ["bash", APPROVE_SCRIPT, "Bash"]
proc.environment = ProcessInfo.processInfo.environment.merging([
    "CLAUDE_TOOL_INPUT": "{\"command\": \"echo test\"}",
    "CLAUDE_SESSION_ID": "session_test_001"
]) { _, new in new }
try? proc.run()
proc.waitUntilExit()
check(proc.terminationStatus == 0, "ai-approve exits 0 when no settings.json (approval disabled)")

// ──────────────────────────────────────────
// Test 6: ai-approve — enabled + deny → exit 2
// ──────────────────────────────────────────
print("\n=== Test 6: ai-approve deny flow → exit 2 ===")

let settingsJSON = """
{
  "approval": {
    "enabled": true,
    "timeout_seconds": 5
  }
}
"""

do {
    try settingsJSON.write(toFile: SETTINGS_FILE, atomically: true, encoding: .utf8)

    let approveProc = Process()
    approveProc.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    approveProc.arguments = ["bash", APPROVE_SCRIPT, "Bash"]
    approveProc.environment = ProcessInfo.processInfo.environment.merging([
        "CLAUDE_TOOL_INPUT": "{\"command\": \"rm -rf /important\"}",
        "CLAUDE_SESSION_ID": "session_test_flow"
    ]) { _, new in new }
    try approveProc.run()

    // pending.json が書かれるまで待機
    Thread.sleep(forTimeInterval: 1.5)

    // deny で応答
    let denyJSON = "{\"schema_version\":\"1.0\",\"session_id\":\"session_test_flow\",\"decision\":\"deny\",\"decided_at\":\"\(now)\"}"
    try denyJSON.write(toFile: APPROVAL_FILE, atomically: true, encoding: .utf8)

    approveProc.waitUntilExit()
    check(approveProc.terminationStatus == 2, "ai-approve exits 2 on deny (got: \(approveProc.terminationStatus))")

    try? fm.removeItem(atPath: PENDING_FILE)
    try? fm.removeItem(atPath: APPROVAL_FILE)
    try? fm.removeItem(atPath: SETTINGS_FILE)
    check(true, "all test files cleaned up")
} catch {
    check(false, "deny flow: \(error)")
    try? fm.removeItem(atPath: PENDING_FILE)
    try? fm.removeItem(atPath: APPROVAL_FILE)
    try? fm.removeItem(atPath: SETTINGS_FILE)
}

// ──────────────────────────────────────────
// Summary
// ──────────────────────────────────────────
print("\n=== Results ===")
print("Passed: \(passed)")
print("Failed: \(failed)")
if failed == 0 {
    print("ALL TESTS PASSED")
    exit(0)
} else {
    print("SOME TESTS FAILED")
    exit(1)
}
