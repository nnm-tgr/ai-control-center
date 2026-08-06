import Foundation
import Observation

@Observable
@MainActor
final class TaskStore {
    private(set) var tasks: [TaskItem] = []
    private(set) var taskGroups: [TaskGroup] = []

    init() { load() }

    // MARK: - Persistence

    private static let storeDirectory: URL? = {
        guard let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        else { return nil }
        let dir = base.appendingPathComponent("AIControlCenter", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    private static var tasksURL:  URL? { storeDirectory?.appendingPathComponent("tasks.json") }
    private static var groupsURL: URL? { storeDirectory?.appendingPathComponent("task-groups.json") }

    private func load() {
        if let url = Self.tasksURL,
           let data = try? Data(contentsOf: url),
           let decoded = try? JSONDecoder().decode([TaskItem].self, from: data) {
            tasks = decoded
        }
        if let url = Self.groupsURL,
           let data = try? Data(contentsOf: url),
           let decoded = try? JSONDecoder().decode([TaskGroup].self, from: data) {
            taskGroups = decoded
        }
    }

    private func saveTasks() {
        guard let url = Self.tasksURL,
              let data = try? JSONEncoder().encode(tasks) else { return }
        try? data.write(to: url, options: .atomic)
    }

    private func saveGroups() {
        guard let url = Self.groupsURL,
              let data = try? JSONEncoder().encode(taskGroups) else { return }
        try? data.write(to: url, options: .atomic)
    }

    // MARK: - Task CRUD

    func addTask(_ task: TaskItem) {
        tasks.append(task)
        saveTasks()
    }

    func updateTask(_ task: TaskItem) {
        guard let idx = tasks.firstIndex(where: { $0.id == task.id }) else { return }
        var updated = task
        updated.updatedAt = .now
        tasks[idx] = updated
        saveTasks()
    }

    func deleteTask(id: UUID) {
        tasks.removeAll { $0.id == id || $0.parentID == id }
        saveTasks()
    }

    func toggleDone(id: UUID) {
        guard let idx = tasks.firstIndex(where: { $0.id == id }) else { return }
        tasks[idx].status = tasks[idx].isDone ? .todo : .done
        tasks[idx].updatedAt = .now
        saveTasks()
    }

    // MARK: - Group CRUD

    func addTaskGroup(_ group: TaskGroup) {
        taskGroups.append(group)
        saveGroups()
    }

    func updateTaskGroup(_ group: TaskGroup) {
        guard let idx = taskGroups.firstIndex(where: { $0.id == group.id }) else { return }
        taskGroups[idx] = group
        saveGroups()
    }

    func deleteTaskGroup(id: UUID) {
        for i in tasks.indices where tasks[i].scope == .group(groupID: id) {
            tasks[i].scope = .global
            tasks[i].updatedAt = .now
        }
        taskGroups.removeAll { $0.id == id }
        saveGroups()
        saveTasks()
    }

    // MARK: - Queries

    func rootTasks(for filter: TaskScopeFilter) -> [TaskItem] {
        tasks
            .filter { $0.parentID == nil && filter.matches($0.scope) }
            .sorted { $0.priority > $1.priority }
    }

    func subtasks(of parentID: UUID) -> [TaskItem] {
        tasks
            .filter { $0.parentID == parentID }
            .sorted { $0.priority > $1.priority }
    }

    func doneCount(for filter: TaskScopeFilter) -> Int {
        rootTasks(for: filter).filter(\.isDone).count
    }

    func totalCount(for filter: TaskScopeFilter) -> Int {
        rootTasks(for: filter).count
    }

    func rootTasks(forProjectURL url: URL) -> [TaskItem] {
        rootTasks(for: .project(rootURL: url))
    }

    func taskGroup(id: UUID) -> TaskGroup? {
        taskGroups.first { $0.id == id }
    }
}
