#!/usr/bin/env swift
// Test target: ~/dev/personal/ai-control-center
//
// Covers the pure functions in NotificationService.swift:
//   NotificationRule.shouldNotify(from:to:)
//   NotificationRule.level(for:)

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

// ── Inline model definitions mirroring AgentStatus.swift / NotificationService.swift ──

enum AgentStatus: String {
    case idle, thinking, runningCommand, waitingUser, completed, error

    var displayName: String {
        switch self {
        case .idle:           "Idle"
        case .thinking:       "Thinking"
        case .runningCommand: "Running"
        case .waitingUser:    "Waiting"
        case .completed:      "Completed"
        case .error:          "Error"
        }
    }
}

enum NotificationLevel: Int, Comparable {
    case low = 0, normal = 1, high = 2, critical = 3
    static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
}

enum NotificationRule {

    static func shouldNotify(from old: AgentStatus?, to new: AgentStatus) -> Bool {
        switch new {
        case .error:          return true
        case .waitingUser:    return true
        case .completed:      return old == .runningCommand || old == .thinking
        case .idle:           return false
        case .thinking, .runningCommand:
            return old == .idle || old == nil
        }
    }

    static func level(for status: AgentStatus) -> NotificationLevel {
        switch status {
        case .error:          .critical
        case .waitingUser:    .high
        case .completed:      .normal
        default:              .low
        }
    }
}

// ──────────────────────────────────────────
// Test 1: .error is always notified
// ──────────────────────────────────────────
print("\n=== Test 1: .error always notifies ===")

for old in ([AgentStatus?.none] + AgentStatus.allCases.map { Optional($0) }) {
    check(NotificationRule.shouldNotify(from: old, to: .error),
          ".error notifies from \(old.map(\.rawValue) ?? "nil")")
}

// ──────────────────────────────────────────
// Test 2: .waitingUser is always notified
// ──────────────────────────────────────────
print("\n=== Test 2: .waitingUser always notifies ===")

for old in ([AgentStatus?.none] + AgentStatus.allCases.map { Optional($0) }) {
    check(NotificationRule.shouldNotify(from: old, to: .waitingUser),
          ".waitingUser notifies from \(old.map(\.rawValue) ?? "nil")")
}

// ──────────────────────────────────────────
// Test 3: .completed only from runningCommand/thinking
// ──────────────────────────────────────────
print("\n=== Test 3: .completed notifies only from runningCommand or thinking ===")

check(NotificationRule.shouldNotify(from: .runningCommand, to: .completed),
      "completed from runningCommand → notify")
check(NotificationRule.shouldNotify(from: .thinking, to: .completed),
      "completed from thinking → notify")
check(!NotificationRule.shouldNotify(from: .idle, to: .completed),
      "completed from idle → no notify")
check(!NotificationRule.shouldNotify(from: .waitingUser, to: .completed),
      "completed from waitingUser → no notify")
check(!NotificationRule.shouldNotify(from: .error, to: .completed),
      "completed from error → no notify")
check(!NotificationRule.shouldNotify(from: .completed, to: .completed),
      "completed from completed → no notify")
check(!NotificationRule.shouldNotify(from: nil, to: .completed),
      "completed from nil → no notify")

// ──────────────────────────────────────────
// Test 4: .idle never notifies
// ──────────────────────────────────────────
print("\n=== Test 4: .idle never notifies ===")

for old in ([AgentStatus?.none] + AgentStatus.allCases.map { Optional($0) }) {
    check(!NotificationRule.shouldNotify(from: old, to: .idle),
          ".idle does not notify from \(old.map(\.rawValue) ?? "nil")")
}

// ──────────────────────────────────────────
// Test 5: .thinking / .runningCommand: only inactive → active
// ──────────────────────────────────────────
print("\n=== Test 5: .thinking/.runningCommand notify only from idle or nil ===")

for active in [AgentStatus.thinking, .runningCommand] {
    check(NotificationRule.shouldNotify(from: .idle, to: active),
          "\(active.rawValue) from idle → notify")
    check(NotificationRule.shouldNotify(from: nil, to: active),
          "\(active.rawValue) from nil → notify")
    check(!NotificationRule.shouldNotify(from: .thinking, to: active),
          "\(active.rawValue) from thinking → no notify")
    check(!NotificationRule.shouldNotify(from: .runningCommand, to: active),
          "\(active.rawValue) from runningCommand → no notify")
    check(!NotificationRule.shouldNotify(from: .waitingUser, to: active),
          "\(active.rawValue) from waitingUser → no notify")
    check(!NotificationRule.shouldNotify(from: .completed, to: active),
          "\(active.rawValue) from completed → no notify")
    check(!NotificationRule.shouldNotify(from: .error, to: active),
          "\(active.rawValue) from error → no notify")
}

// ──────────────────────────────────────────
// Test 6: level(for:) mapping
// ──────────────────────────────────────────
print("\n=== Test 6: NotificationRule.level(for:) ===")

check(NotificationRule.level(for: .error) == .critical,         "error → .critical")
check(NotificationRule.level(for: .waitingUser) == .high,       "waitingUser → .high")
check(NotificationRule.level(for: .completed) == .normal,       "completed → .normal")
check(NotificationRule.level(for: .idle) == .low,               "idle → .low")
check(NotificationRule.level(for: .thinking) == .low,           "thinking → .low")
check(NotificationRule.level(for: .runningCommand) == .low,     "runningCommand → .low")

// ──────────────────────────────────────────
// Test 7: level ordering (critical > high > normal > low)
// ──────────────────────────────────────────
print("\n=== Test 7: NotificationLevel ordering ===")

check(NotificationLevel.critical > .high,    "critical > high")
check(NotificationLevel.high > .normal,      "high > normal")
check(NotificationLevel.normal > .low,       "normal > low")
check(!(NotificationLevel.low > .normal),    "low not > normal")

// ──────────────────────────────────────────
// Test 8: no false positives for typical idle-loop transitions
// ──────────────────────────────────────────
print("\n=== Test 8: idle-loop transitions produce no spurious notifications ===")

// Agent cycles: thinking → runningCommand → thinking should not re-notify
check(!NotificationRule.shouldNotify(from: .thinking, to: .runningCommand),
      "thinking → runningCommand: no notify (already active)")
check(!NotificationRule.shouldNotify(from: .runningCommand, to: .thinking),
      "runningCommand → thinking: no notify (already active)")

// completed → idle is quiet
check(!NotificationRule.shouldNotify(from: .completed, to: .idle),
      "completed → idle: no notify")

// error → error is still notified (each new error matters)
check(NotificationRule.shouldNotify(from: .error, to: .error),
      "error → error: notify (each error surface matters)")

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

extension AgentStatus: CaseIterable {
    static var allCases: [AgentStatus] {
        [.idle, .thinking, .runningCommand, .waitingUser, .completed, .error]
    }
}
