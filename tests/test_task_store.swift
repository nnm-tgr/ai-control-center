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

struct TaskNote: Identifiable, Codable, Equatable {
    let id: UUID
    var content: String
    let createdAt: Date
    var updatedAt: Date

    init(id: UUID = UUID(), content: String, createdAt: Date = .now, updatedAt: Date = .now) {
        self.id = id; self.content = content
        self.createdAt = createdAt; self.updatedAt = updatedAt
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
    var notes: [TaskNote]
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
        id: UUID = UUID(), title: String, notes: [TaskNote] = [],
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

    enum CodingKeys: String, CodingKey {
        case id, title, notes, status, priority, scope
        case parentID, categoryID, progress, createdAt, updatedAt, dueDate
    }

    // Migration: [TaskNote] (new) | String (legacy) | absent → []
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id         = try  c.decode(UUID.self,         forKey: .id)
        title      = try  c.decode(String.self,       forKey: .title)
        status     = try (c.decodeIfPresent(TaskStatus.self,   forKey: .status)   ?? .todo)
        priority   = try (c.decodeIfPresent(TaskPriority.self, forKey: .priority) ?? .medium)
        scope      = try  c.decode(TaskScope.self,    forKey: .scope)
        parentID   = try  c.decodeIfPresent(UUID.self,         forKey: .parentID)
        categoryID = try  c.decodeIfPresent(UUID.self,         forKey: .categoryID)
        let raw    = try  c.decodeIfPresent(Int.self,          forKey: .progress)  ?? 0
        progress   = min(max(raw, 0), 100)
        createdAt  = try  c.decode(Date.self,         forKey: .createdAt)
        updatedAt  = try (c.decodeIfPresent(Date.self,         forKey: .updatedAt) ?? Date())
        dueDate    = try  c.decodeIfPresent(Date.self,         forKey: .dueDate)
        if let array = try? c.decode([TaskNote].self, forKey: .notes) {
            notes = array
        } else if let legacy = try? c.decode(String.self, forKey: .notes),
                  !legacy.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            notes = [TaskNote(content: legacy)]
        } else {
            notes = []
        }
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
    notes: [TaskNote(content: "Needs scope filtering")],
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
    check(decoded.notes.count == 1, "notes count preserved")
    check(decoded.notes.first?.content == "Needs scope filtering", "notes content preserved")
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
// Test 15: TaskNote Codable round-trip
// ──────────────────────────────────────────
print("\n=== Test 15: TaskNote Codable round-trip ===")

let note1 = TaskNote(content: "First note with **markdown**")
do {
    let data = try JSONEncoder().encode(note1)
    let decoded = try JSONDecoder().decode(TaskNote.self, from: data)
    check(decoded.id == note1.id, "note id preserved")
    check(decoded.content == note1.content, "note content preserved")
    check(abs(decoded.createdAt.timeIntervalSince(note1.createdAt)) < 0.001, "createdAt preserved")
} catch {
    check(false, "TaskNote Codable failed: \(error)")
}

// Array of notes round-trip
let noteArray = [
    TaskNote(content: "# Heading"),
    TaskNote(content: "- list item"),
    TaskNote(content: "`code block`"),
]
do {
    let data = try JSONEncoder().encode(noteArray)
    let decoded = try JSONDecoder().decode([TaskNote].self, from: data)
    check(decoded.count == 3, "note array count preserved")
    check(decoded.map(\.content) == noteArray.map(\.content), "note contents preserved in order")
} catch {
    check(false, "TaskNote array Codable failed: \(error)")
}

// ──────────────────────────────────────────
// Test 16: Legacy String notes → [TaskNote] migration
// ──────────────────────────────────────────
print("\n=== Test 16: Legacy String notes migration ===")

// Build old-format JSON manually (notes as String)
let legacyJSON = """
{
  "id": "\(UUID().uuidString)",
  "title": "Legacy task",
  "notes": "This is a legacy note",
  "status": "todo",
  "priority": "medium",
  "scope": {"kind": "global"},
  "progress": 0,
  "createdAt": \(Date().timeIntervalSinceReferenceDate),
  "updatedAt": \(Date().timeIntervalSinceReferenceDate)
}
"""

if let legacyData = legacyJSON.data(using: .utf8),
   let migrated = try? JSONDecoder().decode(TaskItem.self, from: legacyData) {
    check(migrated.notes.count == 1, "legacy string migrated to 1 note (got \(migrated.notes.count))")
    check(migrated.notes.first?.content == "This is a legacy note", "legacy note content preserved")
} else {
    check(false, "legacy JSON decode failed")
}

// Empty legacy string → []
let emptyLegacyJSON = """
{
  "id": "\(UUID().uuidString)",
  "title": "Empty notes task",
  "notes": "",
  "status": "todo",
  "priority": "medium",
  "scope": {"kind": "global"},
  "progress": 0,
  "createdAt": \(Date().timeIntervalSinceReferenceDate),
  "updatedAt": \(Date().timeIntervalSinceReferenceDate)
}
"""

if let data = emptyLegacyJSON.data(using: .utf8),
   let migrated = try? JSONDecoder().decode(TaskItem.self, from: data) {
    check(migrated.notes.isEmpty, "empty legacy string → empty notes array")
} else {
    check(false, "empty legacy string decode failed")
}

// ──────────────────────────────────────────
// Test 17: Absent notes key → []
// ──────────────────────────────────────────
print("\n=== Test 17: Absent notes key → empty array ===")

let noNotesJSON = """
{
  "id": "\(UUID().uuidString)",
  "title": "No notes key",
  "status": "inProgress",
  "priority": "high",
  "scope": {"kind": "global"},
  "progress": 50,
  "createdAt": \(Date().timeIntervalSinceReferenceDate),
  "updatedAt": \(Date().timeIntervalSinceReferenceDate)
}
"""

if let data = noNotesJSON.data(using: .utf8),
   let decoded = try? JSONDecoder().decode(TaskItem.self, from: data) {
    check(decoded.notes.isEmpty, "absent notes key → []")
    check(decoded.status == .inProgress, "other fields decoded correctly")
    check(decoded.progress == 50, "progress decoded correctly")
} else {
    check(false, "absent notes key decode failed")
}

// ──────────────────────────────────────────
// Test 18: Note CRUD simulation
// ──────────────────────────────────────────
print("\n=== Test 18: Note CRUD operations ===")

var notesTasks: [TaskItem] = [TaskItem(title: "Task with notes")]
let noteTaskID = notesTasks[0].id

// addNote
func addNote(to taskID: UUID, content: String, in tasks: inout [TaskItem]) {
    guard let idx = tasks.firstIndex(where: { $0.id == taskID }) else { return }
    tasks[idx].notes.append(TaskNote(content: content))
    tasks[idx].updatedAt = .now
}

// updateNote
func updateNote(taskID: UUID, noteID: UUID, content: String, in tasks: inout [TaskItem]) {
    guard let taskIdx = tasks.firstIndex(where: { $0.id == taskID }),
          let noteIdx = tasks[taskIdx].notes.firstIndex(where: { $0.id == noteID })
    else { return }
    tasks[taskIdx].notes[noteIdx].content = content
    tasks[taskIdx].notes[noteIdx].updatedAt = .now
    tasks[taskIdx].updatedAt = .now
}

// deleteNote
func deleteNote(taskID: UUID, noteID: UUID, in tasks: inout [TaskItem]) {
    guard let taskIdx = tasks.firstIndex(where: { $0.id == taskID }) else { return }
    tasks[taskIdx].notes.removeAll { $0.id == noteID }
    tasks[taskIdx].updatedAt = .now
}

addNote(to: noteTaskID, content: "First note", in: &notesTasks)
addNote(to: noteTaskID, content: "Second note", in: &notesTasks)
check(notesTasks[0].notes.count == 2, "addNote: 2 notes added")
check(notesTasks[0].notes[0].content == "First note", "first note content correct")
check(notesTasks[0].notes[1].content == "Second note", "second note content correct")

let firstNoteID = notesTasks[0].notes[0].id
updateNote(taskID: noteTaskID, noteID: firstNoteID, content: "Updated first note", in: &notesTasks)
check(notesTasks[0].notes[0].content == "Updated first note", "updateNote: content updated")
check(notesTasks[0].notes.count == 2, "updateNote: count unchanged")

deleteNote(taskID: noteTaskID, noteID: firstNoteID, in: &notesTasks)
check(notesTasks[0].notes.count == 1, "deleteNote: count reduced to 1")
check(notesTasks[0].notes[0].content == "Second note", "remaining note is second note")

// Codable round-trip with notes
do {
    let data = try JSONEncoder().encode(notesTasks)
    let reloaded = try JSONDecoder().decode([TaskItem].self, from: data)
    check(reloaded[0].notes.count == 1, "notes persisted after Codable round-trip")
    check(reloaded[0].notes[0].content == "Second note", "note content persisted")
} catch {
    check(false, "notes Codable round-trip failed: \(error)")
}

// ──────────────────────────────────────────
// Test 19: Edit flow preserves TaskNotes
// (simulates AddEditTaskSheet configure + save)
// configure() reads: title, status, priority, scope, parentID, categoryID, progress — NOT notes
// save()      writes: those fields back via updateTask; notes are never touched
// ──────────────────────────────────────────
print("\n=== Test 19: Edit flow (configure+save) preserves notes ===")

let originalNotes = [
    TaskNote(content: "Architecture decision: Observer pattern"),
    TaskNote(content: "Blocked on backend API"),
]
var editableTask = TaskItem(
    title: "Feature: Notifications",
    notes: originalNotes,
    status: .inProgress,
    priority: .high,
    scope: .global,
    progress: 40
)

// Simulate configure() — read non-notes fields into @State
let stateTitle    = editableTask.title
let stateStatus   = editableTask.status
let statePriority = editableTask.priority
let stateScope    = editableTask.scope
let stateParent   = editableTask.parentID
let stateCatID    = editableTask.categoryID
// (notes are NOT read into @State by AddEditTaskSheet)

// Simulate user edits
let updatedTitle    = "Feature: Push Notifications"
let updatedProgress = 60

// Simulate save() — write @State back; notes untouched
editableTask.title      = updatedTitle
editableTask.status     = stateStatus
editableTask.priority   = statePriority
editableTask.scope      = stateScope
editableTask.parentID   = stateParent
editableTask.categoryID = stateCatID
editableTask.progress   = updatedProgress

check(editableTask.title == "Feature: Push Notifications", "title updated by edit")
check(editableTask.progress == 60, "progress updated by edit")
check(editableTask.notes.count == 2,
      "notes count unchanged after edit (got \(editableTask.notes.count))")
check(editableTask.notes[0].content == "Architecture decision: Observer pattern",
      "first note content unchanged")
check(editableTask.notes[1].content == "Blocked on backend API",
      "second note content unchanged")
check(editableTask.notes.map(\.id) == originalNotes.map(\.id),
      "note IDs unchanged after edit")

// ──────────────────────────────────────────
// Test 20: onEdit callback closure pattern
// TaskRowView receives onEdit: (TaskItem) -> Void
// Tap on title area (or right-click → Edit) should call onEdit(task)
// DashboardView receives the task and sets editingTask, triggering the sheet
// ──────────────────────────────────────────
print("\n=== Test 20: onEdit callback closure pattern ===")

var capturedTask: TaskItem? = nil
let callbackSample = TaskItem(
    title: "Callback test task",
    notes: [TaskNote(content: "Note preserved through callback")]
)

let onEditCallback: (TaskItem) -> Void = { task in capturedTask = task }
// Simulate tap gesture firing onEdit
onEditCallback(callbackSample)

check(capturedTask != nil, "onEdit callback was called")
check(capturedTask?.id == callbackSample.id, "correct task passed to onEdit (by id)")
check(capturedTask?.title == callbackSample.title, "task title preserved through callback")
check(capturedTask?.notes.count == 1, "task notes preserved through callback")
check(capturedTask?.notes.first?.content == "Note preserved through callback",
      "note content intact through callback")

// Simulate a different task being passed (subtask scenario)
var capturedSubtask: TaskItem? = nil
let subtaskSample = TaskItem(title: "Subtask item", parentID: callbackSample.id)
let onEditSubCallback: (TaskItem) -> Void = { task in capturedSubtask = task }
onEditSubCallback(subtaskSample)
check(capturedSubtask?.id == subtaskSample.id, "subtask onEdit passes correct id")
check(capturedSubtask?.parentID == callbackSample.id, "subtask parentID preserved through callback")

// ──────────────────────────────────────────
// Test 21: toggleDone full cycle (todo → done → todo)
// Root cause for instability: when transitioning done→todo,
// progress must reset to 0; without this reset the UI shows
// progress=100 while status=todo, causing visual confusion and
// misread "already done" clicks.
// ──────────────────────────────────────────
print("\n=== Test 21: toggleDone full cycle — todo→done→todo progress reset ===")

func toggleDone(id: UUID, in tasks: inout [TaskItem]) {
    guard let idx = tasks.firstIndex(where: { $0.id == id }) else { return }
    if tasks[idx].isDone {
        tasks[idx].status = .todo
        tasks[idx].progress = 0
        tasks[idx].updatedAt = .now
    } else {
        tasks[idx].status = .done
        tasks[idx].progress = 100
        tasks[idx].updatedAt = .now
    }
}

var cycleTask = [TaskItem(title: "Cycle task", progress: 0)]
let cycleID = cycleTask[0].id

// Initial state
check(cycleTask[0].status == .todo,     "initial status is .todo")
check(cycleTask[0].progress == 0,       "initial progress is 0")
check(!cycleTask[0].isDone,             "initial isDone is false")

// todo → done
toggleDone(id: cycleID, in: &cycleTask)
check(cycleTask[0].status == .done,     "after 1st toggle: status = .done")
check(cycleTask[0].progress == 100,     "after 1st toggle: progress = 100")
check(cycleTask[0].isDone,              "after 1st toggle: isDone = true")

// done → todo (progress MUST reset)
toggleDone(id: cycleID, in: &cycleTask)
check(cycleTask[0].status == .todo,     "after 2nd toggle: status = .todo")
check(cycleTask[0].progress == 0,       "after 2nd toggle: progress reset to 0")
check(!cycleTask[0].isDone,             "after 2nd toggle: isDone = false")

// todo → done again (should still work after reset)
toggleDone(id: cycleID, in: &cycleTask)
check(cycleTask[0].status == .done,     "after 3rd toggle: status = .done")
check(cycleTask[0].progress == 100,     "after 3rd toggle: progress = 100")

// ──────────────────────────────────────────
// Test 22: toggleDone from non-todo statuses
// Ensures toggle always lands in a clean state regardless of
// what status the task had before being marked done.
// ──────────────────────────────────────────
print("\n=== Test 22: toggleDone from non-todo starting statuses ===")

// inProgress(50%) → done → todo(0%)
var inProgressTask = [TaskItem(title: "In progress", status: .inProgress, progress: 50)]
let inProgressID = inProgressTask[0].id

toggleDone(id: inProgressID, in: &inProgressTask)
check(inProgressTask[0].status == .done,   "inProgress → done: status = .done")
check(inProgressTask[0].progress == 100,   "inProgress → done: progress = 100")

toggleDone(id: inProgressID, in: &inProgressTask)
check(inProgressTask[0].status == .todo,   "done → todo: status = .todo")
check(inProgressTask[0].progress == 0,     "done → todo: progress reset to 0 (was 100)")

// onHold(30%) → done → todo(0%)
var onHoldTask = [TaskItem(title: "On hold", status: .onHold, progress: 30)]
let onHoldID = onHoldTask[0].id

toggleDone(id: onHoldID, in: &onHoldTask)
check(onHoldTask[0].isDone,                "onHold → done: isDone = true")
check(onHoldTask[0].progress == 100,       "onHold → done: progress = 100")

toggleDone(id: onHoldID, in: &onHoldTask)
check(!onHoldTask[0].isDone,               "done → todo: isDone = false")
check(onHoldTask[0].progress == 0,         "done → todo: progress reset to 0 (was 30)")

// ──────────────────────────────────────────
// Test 23: toggleDone idempotency on wrong id
// Calling toggleDone on a non-existent ID should be a no-op.
// ──────────────────────────────────────────
print("\n=== Test 23: toggleDone no-op for unknown id ===")

var noopTasks = [TaskItem(title: "Safe task", progress: 40)]
let unknownID = UUID()
let beforeStatus = noopTasks[0].status
let beforeProgress = noopTasks[0].progress

toggleDone(id: unknownID, in: &noopTasks)

check(noopTasks[0].status == beforeStatus,     "unknown id: status unchanged")
check(noopTasks[0].progress == beforeProgress, "unknown id: progress unchanged")
check(noopTasks.count == 1,                    "unknown id: task list unchanged")

// ──────────────────────────────────────────
// Helpers for parent-sync tests
// (mirrors TaskStore.syncParent logic)
// ──────────────────────────────────────────

func syncParent(id: UUID, in tasks: inout [TaskItem]) {
    let children = tasks.filter { $0.parentID == id }
    guard !children.isEmpty,
          let idx = tasks.firstIndex(where: { $0.id == id })
    else { return }

    let avg = children.map(\.progress).reduce(0, +) / children.count

    tasks[idx].progress = avg
    tasks[idx].status   = avg == 100 ? .done       :
                          avg >  0   ? .inProgress :
                                       .todo
}

// ──────────────────────────────────────────
// Test 24: syncParent — all children done → parent done/100%
// ──────────────────────────────────────────
print("\n=== Test 24: syncParent — all children done → parent done/100% ===")

let parentID24 = UUID()
var tasks24: [TaskItem] = [
    TaskItem(id: parentID24, title: "Parent"),
    TaskItem(title: "Child A", status: .done, parentID: parentID24, progress: 100),
    TaskItem(title: "Child B", status: .done, parentID: parentID24, progress: 100),
    TaskItem(title: "Child C", status: .done, parentID: parentID24, progress: 100),
]

syncParent(id: parentID24, in: &tasks24)
let parent24 = tasks24.first(where: { $0.id == parentID24 })!
check(parent24.status   == .done, "all children done → parent status = .done")
check(parent24.progress == 100,   "all children done → parent progress = 100")

// ──────────────────────────────────────────
// Test 25: syncParent — partial progress → parent gets average
// ──────────────────────────────────────────
print("\n=== Test 25: syncParent — partial progress → parent gets average ===")

let parentID25 = UUID()
var tasks25: [TaskItem] = [
    TaskItem(id: parentID25, title: "Parent"),
    TaskItem(title: "Child A", status: .done, parentID: parentID25, progress: 100),
    TaskItem(title: "Child B", status: .inProgress, parentID: parentID25, progress: 60),
    TaskItem(title: "Child C", status: .todo, parentID: parentID25, progress: 0),
]

syncParent(id: parentID25, in: &tasks25)
let parent25 = tasks25.first(where: { $0.id == parentID25 })!
check(parent25.progress == 53,          // (100+60+0)/3 = 53
      "partial progress → parent avg = 53 (got \(parent25.progress))")
check(parent25.status == .inProgress,
      "any child inProgress → parent status = .inProgress")

// ──────────────────────────────────────────
// Test 26: syncParent — status derivation rules
// ──────────────────────────────────────────
print("\n=== Test 26: syncParent — status derivation rules ===")

// avg > 0 and < 100 → inProgress (child status irrelevant)
let parentID26a = UUID()
var tasks26a: [TaskItem] = [
    TaskItem(id: parentID26a, title: "Parent"),
    TaskItem(title: "C1", status: .onHold, parentID: parentID26a, progress: 20),
    TaskItem(title: "C2", status: .onHold, parentID: parentID26a, progress: 30),
]
syncParent(id: parentID26a, in: &tasks26a)
let p26a = tasks26a.first(where: { $0.id == parentID26a })!
check(p26a.status   == .inProgress, "avg=25 (0<p<100) → parent = .inProgress")
check(p26a.progress == 25,          "onHold children avg = 25 (got \(p26a.progress))")

// 0% + 100% mix → avg=50 → inProgress
let parentID26b = UUID()
var tasks26b: [TaskItem] = [
    TaskItem(id: parentID26b, title: "Parent"),
    TaskItem(title: "C1", status: .done, parentID: parentID26b, progress: 100),
    TaskItem(title: "C2", status: .todo, parentID: parentID26b, progress: 0),
]
syncParent(id: parentID26b, in: &tasks26b)
let p26b = tasks26b.first(where: { $0.id == parentID26b })!
check(p26b.status   == .inProgress, "avg=50 → parent = .inProgress")
check(p26b.progress == 50,          "done+todo mix → parent progress = 50 (got \(p26b.progress))")

// all children at 0% → parent todo
let parentID26c = UUID()
var tasks26c: [TaskItem] = [
    TaskItem(id: parentID26c, title: "Parent"),
    TaskItem(title: "C1", status: .todo, parentID: parentID26c, progress: 0),
    TaskItem(title: "C2", status: .todo, parentID: parentID26c, progress: 0),
]
syncParent(id: parentID26c, in: &tasks26c)
check(tasks26c.first(where: { $0.id == parentID26c })!.status == .todo,
      "all children 0% → parent = .todo")

// ──────────────────────────────────────────
// Test 27: syncParent — no-op when children list is empty
// ──────────────────────────────────────────
print("\n=== Test 27: syncParent — no-op when no children ===")

let loneID = UUID()
var tasks27: [TaskItem] = [
    TaskItem(id: loneID, title: "Lone task", status: .inProgress, progress: 60),
]
syncParent(id: loneID, in: &tasks27)
let lone = tasks27.first(where: { $0.id == loneID })!
check(lone.status   == .inProgress, "no children → status unchanged (got \(lone.status))")
check(lone.progress == 60,          "no children → progress unchanged")

// ──────────────────────────────────────────
// Test 28: syncParent after child toggleDone (full integration)
// Simulates the full flow: toggle child → sync parent
// ──────────────────────────────────────────
print("\n=== Test 28: full flow — toggle child → syncParent ===")

let parentID28 = UUID()
var tasks28: [TaskItem] = [
    TaskItem(id: parentID28, title: "Parent", status: .todo, progress: 0),
    TaskItem(title: "Sub 1", status: .todo, parentID: parentID28, progress: 0),
    TaskItem(title: "Sub 2", status: .todo, parentID: parentID28, progress: 0),
]

// Toggle Sub 1 → done
if let idx = tasks28.firstIndex(where: { $0.title == "Sub 1" }) {
    tasks28[idx].status   = .done
    tasks28[idx].progress = 100
}
syncParent(id: parentID28, in: &tasks28)
let p28a = tasks28.first(where: { $0.id == parentID28 })!
check(p28a.progress == 50,         "1/2 done → parent progress = 50 (got \(p28a.progress))")
check(p28a.status   == .inProgress, "1/2 done → parent status = .inProgress")

// Toggle Sub 2 → done
if let idx = tasks28.firstIndex(where: { $0.title == "Sub 2" }) {
    tasks28[idx].status   = .done
    tasks28[idx].progress = 100
}
syncParent(id: parentID28, in: &tasks28)
let p28b = tasks28.first(where: { $0.id == parentID28 })!
check(p28b.progress == 100,  "2/2 done → parent progress = 100")
check(p28b.status   == .done, "2/2 done → parent status = .done")

// Toggle Sub 1 back → todo (parent must revert)
if let idx = tasks28.firstIndex(where: { $0.title == "Sub 1" }) {
    tasks28[idx].status   = .todo
    tasks28[idx].progress = 0
}
syncParent(id: parentID28, in: &tasks28)
let p28c = tasks28.first(where: { $0.id == parentID28 })!
check(p28c.progress == 50,         "revert Sub1 → parent progress back to 50 (got \(p28c.progress))")
check(p28c.status   == .inProgress, "revert Sub1 → parent status = .inProgress (avg=50)")

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
