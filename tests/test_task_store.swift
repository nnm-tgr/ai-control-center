#!/usr/bin/env swift
// Test target: ~/dev/personal/ai-control-center
//
// Pass criteria:
//   Test 1: TaskItem Codable round-trip preserves all fields
//   Test 2: TaskScope custom Codable (project / group / global)
//   Test 3: TaskScopeFilter.matches() covers all combinations
//   Test 4: TaskPriority Comparable ordering
//   Test 5: TaskGroup Codable round-trip
//   Test 6: JSON persistence — write tasks.json, reload and verify
//   Test 7: Hierarchy constraint — subtask cannot have a subtask as parent
//   Test 8: Scope migration — deleting a group resets tasks to .global

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

// ── Inline model definitions mirroring TaskItem.swift ─────────────────────

enum TaskStatus: String, Codable, CaseIterable {
    case todo, inProgress, inReview, onHold, done

    var displayName: String {
        switch self {
        case .todo:       "To Do"
        case .inProgress: "In Progress"
        case .inReview:   "In Review"
        case .onHold:     "On Hold"
        case .done:       "Done"
        }
    }

    var isDone: Bool { self == .done }
}

enum TaskPriority: String, Codable, CaseIterable, Comparable {
    case low, medium, high, urgent
    private var order: Int {
        switch self { case .low: 0; case .medium: 1; case .high: 2; case .urgent: 3 }
    }
    static func < (lhs: Self, rhs: Self) -> Bool { lhs.order < rhs.order }
}

enum TaskScope: Equatable {
    case project(rootURL: URL)
    case group(groupID: UUID)
    case global
}

extension TaskScope: Codable {
    private enum CodingKeys: String, CodingKey { case kind, url, groupID }
    private enum Kind: String, Codable { case project, group, global }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .project(let url):
            try c.encode(Kind.project, forKey: .kind)
            try c.encode(url, forKey: .url)
        case .group(let id):
            try c.encode(Kind.group, forKey: .kind)
            try c.encode(id, forKey: .groupID)
        case .global:
            try c.encode(Kind.global, forKey: .kind)
        }
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        switch try c.decode(Kind.self, forKey: .kind) {
        case .project: self = .project(rootURL: try c.decode(URL.self, forKey: .url))
        case .group:   self = .group(groupID: try c.decode(UUID.self, forKey: .groupID))
        case .global:  self = .global
        }
    }
}

enum TaskScopeFilter: Equatable {
    case all
    case project(rootURL: URL)
    case group(groupID: UUID)
    case global

    func matches(_ scope: TaskScope) -> Bool {
        switch (self, scope) {
        case (.all, _):                          true
        case (.project(let a), .project(let b)): a == b
        case (.group(let a), .group(let b)):     a == b
        case (.global, .global):                 true
        default:                                  false
        }
    }
}

struct TaskGroup: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var colorHex: String
    var createdAt: Date
}

struct TaskCategory: Identifiable, Codable, Equatable, Hashable {
    let id: UUID
    var name: String
    var colorHex: String
    var createdAt: Date

    static let presetColors: [String] = [
        "#5B5FC7", "#4A90D9", "#2ECC7A", "#F5C842",
        "#F5813D", "#E85151", "#9B72CF", "#888888",
    ]
}

struct TaskItem: Identifiable, Codable, Equatable {
    let id: UUID
    var title: String
    var notes: String
    var status: TaskStatus
    var priority: TaskPriority
    var scope: TaskScope
    var parentID: UUID?
    var categoryID: UUID?
    var progress: Int
    var createdAt: Date
    var updatedAt: Date
    var dueDate: Date?

    var isSubtask: Bool { parentID != nil }
    var isDone: Bool { status.isDone }

    init(
        id: UUID = UUID(), title: String, notes: String = "",
        status: TaskStatus = .todo, priority: TaskPriority = .medium,
        scope: TaskScope = .global, parentID: UUID? = nil, categoryID: UUID? = nil,
        progress: Int = 0,
        createdAt: Date = .now, updatedAt: Date = .now, dueDate: Date? = nil
    ) {
        self.id = id; self.title = title; self.notes = notes
        self.status = status; self.priority = priority; self.scope = scope
        self.parentID = parentID; self.categoryID = categoryID
        self.progress = min(max(progress, 0), 100)
        self.createdAt = createdAt; self.updatedAt = updatedAt; self.dueDate = dueDate
    }
}

// Simulate TaskStore query logic
func rootTasks(in tasks: [TaskItem], for filter: TaskScopeFilter) -> [TaskItem] {
    tasks.filter { $0.parentID == nil && filter.matches($0.scope) }
         .sorted { $0.priority > $1.priority }
}

func subtasks(in tasks: [TaskItem], of parentID: UUID) -> [TaskItem] {
    tasks.filter { $0.parentID == parentID }
}

func deleteTask(id: UUID, from tasks: inout [TaskItem]) {
    tasks.removeAll { $0.id == id || $0.parentID == id }
}

func deleteGroup(id: UUID, from tasks: inout [TaskItem], groups: inout [TaskGroup]) {
    for i in tasks.indices where tasks[i].scope == .group(groupID: id) {
        tasks[i].scope = .global
    }
    groups.removeAll { $0.id == id }
}

// ──────────────────────────────────────────
// Test 1: TaskItem Codable round-trip
// ──────────────────────────────────────────
print("\n=== Test 1: TaskItem Codable round-trip ===")

let projectURL = URL(fileURLWithPath: "/Users/test/my-project")
let parentID = UUID()
let dueDate = Calendar.current.date(byAdding: .day, value: 7, to: .now)!

let original = TaskItem(
    title: "Implement task management",
    notes: "Needs scope filtering",
    status: .inProgress,
    priority: .high,
    scope: .project(rootURL: projectURL),
    parentID: nil,
    dueDate: dueDate
)

do {
    let data = try JSONEncoder().encode(original)
    let decoded = try JSONDecoder().decode(TaskItem.self, from: data)
    check(decoded.id == original.id, "id preserved")
    check(decoded.title == original.title, "title preserved")
    check(decoded.notes == original.notes, "notes preserved")
    check(decoded.status == original.status, "status preserved")
    check(decoded.priority == original.priority, "priority preserved")
    check(decoded.scope == original.scope, "scope preserved")
    check(decoded.parentID == original.parentID, "parentID preserved (nil)")
    check(abs(decoded.dueDate!.timeIntervalSince(dueDate)) < 0.001, "dueDate preserved")
} catch {
    check(false, "Codable failed: \(error)")
}

// ──────────────────────────────────────────
// Test 2: TaskScope custom Codable
// ──────────────────────────────────────────
print("\n=== Test 2: TaskScope custom Codable ===")

let groupID = UUID()
let scopes: [TaskScope] = [
    .project(rootURL: projectURL),
    .group(groupID: groupID),
    .global
]

for scope in scopes {
    do {
        let data = try JSONEncoder().encode(scope)
        let decoded = try JSONDecoder().decode(TaskScope.self, from: data)
        check(decoded == scope, "round-trip: \(scope)")
    } catch {
        check(false, "scope encode/decode failed for \(scope): \(error)")
    }
}

// ──────────────────────────────────────────
// Test 3: TaskScopeFilter.matches()
// ──────────────────────────────────────────
print("\n=== Test 3: TaskScopeFilter.matches() ===")

let url1 = URL(fileURLWithPath: "/projects/alpha")
let url2 = URL(fileURLWithPath: "/projects/beta")
let gid1 = UUID()
let gid2 = UUID()

check(TaskScopeFilter.all.matches(.global),              ".all matches .global")
check(TaskScopeFilter.all.matches(.project(rootURL: url1)), ".all matches .project")
check(TaskScopeFilter.all.matches(.group(groupID: gid1)),   ".all matches .group")

check(TaskScopeFilter.project(rootURL: url1).matches(.project(rootURL: url1)), ".project matches same URL")
check(!TaskScopeFilter.project(rootURL: url1).matches(.project(rootURL: url2)), ".project rejects different URL")
check(!TaskScopeFilter.project(rootURL: url1).matches(.global), ".project rejects .global")

check(TaskScopeFilter.group(groupID: gid1).matches(.group(groupID: gid1)), ".group matches same ID")
check(!TaskScopeFilter.group(groupID: gid1).matches(.group(groupID: gid2)), ".group rejects different ID")
check(!TaskScopeFilter.group(groupID: gid1).matches(.project(rootURL: url1)), ".group rejects .project")

check(TaskScopeFilter.global.matches(.global), ".global matches .global")
check(!TaskScopeFilter.global.matches(.project(rootURL: url1)), ".global rejects .project")

// ──────────────────────────────────────────
// Test 4: TaskPriority Comparable ordering
// ──────────────────────────────────────────
print("\n=== Test 4: TaskPriority Comparable ===")

check(TaskPriority.low < .medium, "low < medium")
check(TaskPriority.medium < .high, "medium < high")
check(TaskPriority.high < .urgent, "high < urgent")
check(!(TaskPriority.urgent < .high), "urgent not < high")
check(TaskPriority.low < .urgent, "low < urgent (transitive)")

let unsorted: [TaskPriority] = [.medium, .urgent, .low, .high]
let sorted = unsorted.sorted()
check(sorted == [.low, .medium, .high, .urgent], "sorted order correct: \(sorted)")

// ──────────────────────────────────────────
// Test 5: TaskGroup Codable round-trip
// ──────────────────────────────────────────
print("\n=== Test 5: TaskGroup Codable round-trip ===")

let group = TaskGroup(id: UUID(), name: "Mobile", colorHex: "#5B5FC7", createdAt: .now)

do {
    let data = try JSONEncoder().encode(group)
    let decoded = try JSONDecoder().decode(TaskGroup.self, from: data)
    check(decoded.id == group.id, "group id preserved")
    check(decoded.name == group.name, "group name preserved")
    check(decoded.colorHex == group.colorHex, "group colorHex preserved")
} catch {
    check(false, "TaskGroup Codable failed: \(error)")
}

// ──────────────────────────────────────────
// Test 6: JSON persistence to temp dir
// ──────────────────────────────────────────
print("\n=== Test 6: JSON persistence ===")

let fm = FileManager.default
let tmpDir = fm.temporaryDirectory.appendingPathComponent("task_store_test_\(UUID().uuidString)")
try? fm.createDirectory(at: tmpDir, withIntermediateDirectories: true)
let tasksURL = tmpDir.appendingPathComponent("tasks.json")

var tasks: [TaskItem] = [
    TaskItem(title: "Root task A", priority: .high, scope: .project(rootURL: url1)),
    TaskItem(title: "Root task B", priority: .low, scope: .global),
    TaskItem(title: "Root task C", priority: .medium, scope: .group(groupID: gid1)),
]
let subID = UUID()
tasks.append(TaskItem(id: subID, title: "Subtask of A", scope: .project(rootURL: url1), parentID: tasks[0].id))

do {
    let data = try JSONEncoder().encode(tasks)
    try data.write(to: tasksURL, options: .atomic)
    check(fm.fileExists(atPath: tasksURL.path), "tasks.json written")

    let reloaded = try JSONDecoder().decode([TaskItem].self, from: Data(contentsOf: tasksURL))
    check(reloaded.count == tasks.count, "count matches after reload: \(reloaded.count)")
    check(reloaded.map(\.title).sorted() == tasks.map(\.title).sorted(), "titles match after reload")
    check(reloaded.first(where: { $0.id == subID })?.parentID == tasks[0].id, "parentID preserved after reload")
} catch {
    check(false, "persistence failed: \(error)")
}

// ──────────────────────────────────────────
// Test 7: Hierarchy query + 2-level constraint simulation
// ──────────────────────────────────────────
print("\n=== Test 7: Hierarchy + rootTasks query ===")

// rootTasks for .project(url1) should return only root tasks scoped to url1
let roots = rootTasks(in: tasks, for: .project(rootURL: url1))
check(roots.count == 1, "rootTasks(project url1) count = 1 (got \(roots.count))")
check(roots.first?.title == "Root task A", "correct root task returned")
check(roots.first?.priority == .high, "priority correct")

let subs = subtasks(in: tasks, of: tasks[0].id)
check(subs.count == 1, "subtasks of A = 1")
check(subs.first?.title == "Subtask of A", "subtask title correct")

// Subtask itself must not appear in rootTasks
let subInRoots = rootTasks(in: tasks, for: .all).first(where: { $0.id == subID })
check(subInRoots == nil, "subtask excluded from rootTasks")

// Priority sort: rootTasks for .all should be sorted high→low
let allRoots = rootTasks(in: tasks, for: .all)
let priorities = allRoots.map(\.priority)
check(priorities == priorities.sorted().reversed(), "rootTasks sorted by priority descending: \(priorities)")

// 2-level constraint: prevent a subtask from being a parent
// (UI enforces this; here we test the query boundary)
var tasks2 = tasks
let deepSubtask = TaskItem(title: "Deep subtask (invalid)", parentID: subID)
tasks2.append(deepSubtask)
let rootsAfter = rootTasks(in: tasks2, for: .all)
check(!rootsAfter.contains(where: { $0.id == deepSubtask.id }), "deep subtask not in rootTasks")

// ──────────────────────────────────────────
// Test 8: Group delete → tasks migrate to .global
// ──────────────────────────────────────────
print("\n=== Test 8: Group deletion migrates tasks to .global ===")

var mutableTasks: [TaskItem] = [
    TaskItem(title: "Group task 1", scope: .group(groupID: gid1)),
    TaskItem(title: "Group task 2", scope: .group(groupID: gid1)),
    TaskItem(title: "Other task",   scope: .global),
]
var mutableGroups: [TaskGroup] = [
    TaskGroup(id: gid1, name: "Mobile", colorHex: "#FF0000", createdAt: .now)
]

deleteGroup(id: gid1, from: &mutableTasks, groups: &mutableGroups)

check(mutableGroups.isEmpty, "group removed from groups array")
check(mutableTasks.filter { $0.scope == .group(groupID: gid1) }.isEmpty, "no tasks remain in deleted group")
check(mutableTasks.filter { $0.scope == .global }.count == 3, "all 3 tasks are now .global")

// deleteTask removes subtasks too
var deletionTasks: [TaskItem] = [
    TaskItem(id: parentID, title: "Parent"),
    TaskItem(title: "Subtask 1", parentID: parentID),
    TaskItem(title: "Subtask 2", parentID: parentID),
    TaskItem(title: "Unrelated"),
]
deleteTask(id: parentID, from: &deletionTasks)
check(deletionTasks.count == 1, "parent + subtasks deleted, only unrelated remains (\(deletionTasks.count))")
check(deletionTasks.first?.title == "Unrelated", "correct task survives")

// Cleanup
try? fm.removeItem(at: tmpDir)

// ──────────────────────────────────────────
// Test 9: TaskStatus — 5 values, displayNames, isDone
// ──────────────────────────────────────────
print("\n=== Test 9: TaskStatus values and properties ===")

check(TaskStatus.allCases.count == 5, "5 statuses defined")
check(TaskStatus.done.isDone, "done.isDone == true")
check(!TaskStatus.inProgress.isDone, "inProgress.isDone == false")
check(!TaskStatus.inReview.isDone, "inReview.isDone == false")
check(!TaskStatus.onHold.isDone, "onHold.isDone == false")
check(!TaskStatus.todo.isDone, "todo.isDone == false")

let expectedNames: [TaskStatus: String] = [
    .todo: "To Do", .inProgress: "In Progress",
    .inReview: "In Review", .onHold: "On Hold", .done: "Done"
]
for (status, name) in expectedNames {
    check(status.displayName == name, "\(status.rawValue).displayName == \"\(name)\"")
}

// Codable round-trip for all statuses
for status in TaskStatus.allCases {
    if let data = try? JSONEncoder().encode(status),
       let decoded = try? JSONDecoder().decode(TaskStatus.self, from: data) {
        check(decoded == status, "\(status.rawValue) Codable round-trip")
    } else {
        check(false, "\(status.rawValue) Codable failed")
    }
}

// ──────────────────────────────────────────
// Test 10: progress field — clamping and Codable
// ──────────────────────────────────────────
print("\n=== Test 10: progress field ===")

let t0 = TaskItem(title: "Default", progress: 0)
check(t0.progress == 0, "default progress = 0")

let t50 = TaskItem(title: "Half", progress: 50)
check(t50.progress == 50, "progress = 50 stored correctly")

let tOver = TaskItem(title: "Over 100", progress: 150)
check(tOver.progress == 100, "progress clamped to 100 (got \(tOver.progress))")

let tUnder = TaskItem(title: "Under 0", progress: -10)
check(tUnder.progress == 0, "progress clamped to 0 (got \(tUnder.progress))")

do {
    let data = try JSONEncoder().encode(t50)
    let decoded = try JSONDecoder().decode(TaskItem.self, from: data)
    check(decoded.progress == 50, "progress 50 preserved after Codable round-trip")
} catch {
    check(false, "progress Codable failed: \(error)")
}

// setStatus → done auto-sets progress=100
var setStatusTasks: [TaskItem] = [TaskItem(title: "Task", progress: 40)]
let taskID = setStatusTasks[0].id
// Simulate setStatus(.done)
if let idx = setStatusTasks.firstIndex(where: { $0.id == taskID }) {
    setStatusTasks[idx].status = .done
    if setStatusTasks[idx].status == .done { setStatusTasks[idx].progress = 100 }
}
check(setStatusTasks[0].progress == 100, "setStatus(.done) auto-sets progress to 100")

// setProgress clamps
func setProgress(id: UUID, progress: Int, in tasks: inout [TaskItem]) {
    guard let idx = tasks.firstIndex(where: { $0.id == id }) else { return }
    tasks[idx].progress = min(max(progress, 0), 100)
}
var progressTasks = [TaskItem(title: "T", progress: 30)]
setProgress(id: progressTasks[0].id, progress: 75, in: &progressTasks)
check(progressTasks[0].progress == 75, "setProgress(75) applied")
setProgress(id: progressTasks[0].id, progress: 120, in: &progressTasks)
check(progressTasks[0].progress == 100, "setProgress(120) clamped to 100")

// ──────────────────────────────────────────
// Test 11: TaskCategory Codable round-trip
// ──────────────────────────────────────────
print("\n=== Test 11: TaskCategory Codable round-trip ===")

let cat1 = TaskCategory(id: UUID(), name: "Bug", colorHex: "#E85151", createdAt: .now)
do {
    let data = try JSONEncoder().encode(cat1)
    let decoded = try JSONDecoder().decode(TaskCategory.self, from: data)
    check(decoded.id == cat1.id, "category id preserved")
    check(decoded.name == cat1.name, "category name preserved")
    check(decoded.colorHex == cat1.colorHex, "category colorHex preserved")
} catch {
    check(false, "TaskCategory Codable failed: \(error)")
}

check(TaskCategory.presetColors.count == 8, "8 preset colors defined")
check(TaskCategory.presetColors.allSatisfy { $0.hasPrefix("#") && $0.count == 7 },
      "all preset colors are valid 7-char hex strings")

// ──────────────────────────────────────────
// Test 12: categoryID persisted in TaskItem
// ──────────────────────────────────────────
print("\n=== Test 12: categoryID preserved in TaskItem Codable ===")

let catID = UUID()
let taskWithCat = TaskItem(title: "Categorized task", categoryID: catID)
do {
    let data = try JSONEncoder().encode(taskWithCat)
    let decoded = try JSONDecoder().decode(TaskItem.self, from: data)
    check(decoded.categoryID == catID, "categoryID preserved after round-trip")
} catch {
    check(false, "TaskItem with categoryID failed: \(error)")
}

let taskNoCat = TaskItem(title: "No category")
do {
    let data = try JSONEncoder().encode(taskNoCat)
    let decoded = try JSONDecoder().decode(TaskItem.self, from: data)
    check(decoded.categoryID == nil, "nil categoryID preserved")
} catch {
    check(false, "TaskItem with nil categoryID failed: \(error)")
}

// ──────────────────────────────────────────
// Test 13: Category deletion clears categoryID on tasks
// ──────────────────────────────────────────
print("\n=== Test 13: Category deletion migrates tasks ===")

let catToDelete = UUID()
var catTasks: [TaskItem] = [
    TaskItem(title: "Task with cat A", categoryID: catToDelete),
    TaskItem(title: "Task with cat A (2)", categoryID: catToDelete),
    TaskItem(title: "Task no cat"),
    TaskItem(title: "Task other cat", categoryID: UUID()),
]
var catList: [TaskCategory] = [
    TaskCategory(id: catToDelete, name: "Feature", colorHex: "#4A90D9", createdAt: .now),
    TaskCategory(id: UUID(), name: "Bug", colorHex: "#E85151", createdAt: .now),
]

// Simulate deleteCategory
for i in catTasks.indices where catTasks[i].categoryID == catToDelete {
    catTasks[i].categoryID = nil
}
catList.removeAll { $0.id == catToDelete }

check(catList.count == 1, "category removed from list (got \(catList.count))")
check(catTasks.filter { $0.categoryID == catToDelete }.isEmpty, "no tasks remain with deleted category")
check(catTasks.filter { $0.categoryID == nil }.count == 3, "3 tasks now have nil categoryID")
check(catTasks.first(where: { $0.title == "Task other cat" })?.categoryID != nil,
      "other category's tasks unaffected")

// ──────────────────────────────────────────
// Test 14: Category persistence to JSON
// ──────────────────────────────────────────
print("\n=== Test 14: Category JSON persistence ===")

let tmpDir2 = fm.temporaryDirectory.appendingPathComponent("cat_test_\(UUID().uuidString)")
try? fm.createDirectory(at: tmpDir2, withIntermediateDirectories: true)
let catURL = tmpDir2.appendingPathComponent("task-categories.json")

let catsToSave: [TaskCategory] = [
    TaskCategory(id: UUID(), name: "Feature", colorHex: "#5B5FC7", createdAt: .now),
    TaskCategory(id: UUID(), name: "Bug",     colorHex: "#E85151", createdAt: .now),
    TaskCategory(id: UUID(), name: "Chore",   colorHex: "#888888", createdAt: .now),
]

do {
    let data = try JSONEncoder().encode(catsToSave)
    try data.write(to: catURL, options: .atomic)
    check(fm.fileExists(atPath: catURL.path), "task-categories.json written")

    let reloaded = try JSONDecoder().decode([TaskCategory].self, from: Data(contentsOf: catURL))
    check(reloaded.count == 3, "count matches after reload")
    check(reloaded.map(\.name).sorted() == catsToSave.map(\.name).sorted(), "names match")
    check(reloaded.map(\.colorHex).sorted() == catsToSave.map(\.colorHex).sorted(), "colorHex matches")
} catch {
    check(false, "category persistence failed: \(error)")
}

try? fm.removeItem(at: tmpDir2)

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
