import Foundation
import Observation

@Observable
@MainActor
final class TaskStore {
    private(set) var tasks: [TaskItem] = []
    private(set) var taskGroups: [TaskGroup] = []
    private(set) var categories: [TaskCategory] = []
    /// Persisted ordering of project-group keys for each parent task's expanded subtask accordion.
    private(set) var childGroupOrders: [UUID: [String]] = [:]

    init() { load() }

    // MARK: - Persistence

    private static let storeDirectory: URL? = {
        guard let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        else { return nil }
        let dir = base.appendingPathComponent("AIControlCenter", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    private static var tasksURL:           URL? { storeDirectory?.appendingPathComponent("tasks.json") }
    private static var groupsURL:          URL? { storeDirectory?.appendingPathComponent("task-groups.json") }
    private static var categoriesURL:      URL? { storeDirectory?.appendingPathComponent("task-categories.json") }
    private static var childGroupOrderURL: URL? { storeDirectory?.appendingPathComponent("child-group-orders.json") }

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
        if let url = Self.categoriesURL,
           let data = try? Data(contentsOf: url),
           let decoded = try? JSONDecoder().decode([TaskCategory].self, from: data) {
            categories = decoded
        }
        if let url = Self.childGroupOrderURL,
           let data = try? Data(contentsOf: url),
           let decoded = try? JSONDecoder().decode([String: [String]].self, from: data) {
            childGroupOrders = Dictionary(uniqueKeysWithValues: decoded.compactMap { k, v in
                guard let uuid = UUID(uuidString: k) else { return nil }
                return (uuid, v)
            })
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

    private func saveCategories() {
        guard let url = Self.categoriesURL,
              let data = try? JSONEncoder().encode(categories) else { return }
        try? data.write(to: url, options: .atomic)
    }

    private func saveChildGroupOrders() {
        let stringKeyed = Dictionary(uniqueKeysWithValues: childGroupOrders.map { ($0.key.uuidString, $0.value) })
        guard let url = Self.childGroupOrderURL,
              let data = try? JSONEncoder().encode(stringKeyed) else { return }
        try? data.write(to: url, options: .atomic)
    }

    func setChildGroupOrder(parentID: UUID, order: [String]) {
        childGroupOrders[parentID] = order
        saveChildGroupOrders()
    }

    // MARK: - Task CRUD

    func addTask(_ task: TaskItem) {
        tasks.append(task)
        saveTasks()
        if let parentID = task.parentID { syncParent(id: parentID) }
    }

    func updateTask(_ task: TaskItem) {
        guard let idx = tasks.firstIndex(where: { $0.id == task.id }) else { return }
        var updated = task
        updated.updatedAt = .now
        tasks[idx] = updated
        saveTasks()
        if let parentID = task.parentID { syncParent(id: parentID) }
    }

    func deleteTask(id: UUID) {
        let parentID = tasks.first(where: { $0.id == id })?.parentID
        tasks.removeAll { $0.id == id || $0.parentID == id }
        saveTasks()
        if let parentID { syncParent(id: parentID) }
    }

    func toggleDone(id: UUID) {
        guard let idx = tasks.firstIndex(where: { $0.id == id }) else { return }
        let parentID = tasks[idx].parentID
        if tasks[idx].isDone {
            tasks[idx].status   = .todo
            tasks[idx].progress = 0
        } else {
            tasks[idx].status   = .done
            tasks[idx].progress = 100
        }
        tasks[idx].updatedAt = .now
        saveTasks()
        if let parentID { syncParent(id: parentID) }
    }

    func setStatus(id: UUID, status: TaskStatus) {
        guard let idx = tasks.firstIndex(where: { $0.id == id }) else { return }
        tasks[idx].status = status
        if status == .done { tasks[idx].progress = 100 }
        tasks[idx].updatedAt = .now
        saveTasks()
        if let parentID = tasks[idx].parentID { syncParent(id: parentID) }
    }

    func setProgress(id: UUID, progress: Int) {
        guard let idx = tasks.firstIndex(where: { $0.id == id }) else { return }
        tasks[idx].progress = min(max(progress, 0), 100)
        tasks[idx].updatedAt = .now
        saveTasks()
        if let parentID = tasks[idx].parentID { syncParent(id: parentID) }
    }

    // MARK: - Parent sync

    func hasChildren(id: UUID) -> Bool {
        tasks.contains(where: { $0.parentID == id })
    }

    // Derives progress and status of a parent from its current children.
    // Called after any child mutation. No-op when children list is empty.
    private func syncParent(id: UUID) {
        let children = tasks.filter { $0.parentID == id }
        guard !children.isEmpty,
              let idx = tasks.firstIndex(where: { $0.id == id })
        else { return }

        let avg = children.map(\.progress).reduce(0, +) / children.count

        tasks[idx].progress = avg
        tasks[idx].status   = avg == 100 ? .done       :
                              avg >  0   ? .inProgress :
                                           .todo
        tasks[idx].updatedAt = .now
        saveTasks()
    }

    // MARK: - Note CRUD

    func addNote(to taskID: UUID, content: String) {
        guard let idx = tasks.firstIndex(where: { $0.id == taskID }) else { return }
        tasks[idx].notes.append(TaskNote(content: content))
        tasks[idx].updatedAt = .now
        saveTasks()
    }

    func updateNote(taskID: UUID, noteID: UUID, content: String) {
        guard let taskIdx = tasks.firstIndex(where: { $0.id == taskID }),
              let noteIdx = tasks[taskIdx].notes.firstIndex(where: { $0.id == noteID })
        else { return }
        tasks[taskIdx].notes[noteIdx].content = content
        tasks[taskIdx].notes[noteIdx].updatedAt = .now
        tasks[taskIdx].updatedAt = .now
        saveTasks()
    }

    func deleteNote(taskID: UUID, noteID: UUID) {
        guard let taskIdx = tasks.firstIndex(where: { $0.id == taskID }) else { return }
        tasks[taskIdx].notes.removeAll { $0.id == noteID }
        tasks[taskIdx].updatedAt = .now
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

    // MARK: - Category CRUD

    func addCategory(_ category: TaskCategory) {
        categories.append(category)
        saveCategories()
    }

    func updateCategory(_ category: TaskCategory) {
        guard let idx = categories.firstIndex(where: { $0.id == category.id }) else { return }
        categories[idx] = category
        saveCategories()
    }

    func deleteCategory(id: UUID) {
        for i in tasks.indices where tasks[i].categoryID == id {
            tasks[i].categoryID = nil
        }
        categories.removeAll { $0.id == id }
        saveCategories()
        saveTasks()
    }

    func category(id: UUID) -> TaskCategory? {
        categories.first { $0.id == id }
    }
}
