import SwiftUI

struct TaskSectionView: View {
    @Environment(AppState.self) private var appState
    let scopeFilter: TaskScopeFilter
    let onAddTask: (TaskScope?) -> Void
    let onSelectTask: (TaskItem) -> Void

    @State private var collapsedTaskIDs: Set<UUID> = []
    @State private var collapsedGroupKeys: Set<String> = []

    // Sentinel used to store root-level group ordering in TaskStore (no real parent task)
    private static let rootGroupOrderID = UUID(uuid: (0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,1))

    private var taskStore: TaskStore { appState.taskStore }

    var body: some View {
        let rootTasks = taskStore.rootTasks(for: scopeFilter)
        let doneCount = rootTasks.filter(\.isDone).count

        VStack(spacing: 0) {
            sectionHeader(doneCount: doneCount, total: rootTasks.count)
            Divider()
            if rootTasks.isEmpty {
                emptyState
            } else {
                groupedTaskList(rootTasks: rootTasks)
            }
        }
    }

    // MARK: - Header

    private func sectionHeader(doneCount: Int, total: Int) -> some View {
        HStack {
            Text("TASKS")
                .font(.caption)
                .fontWeight(.bold)
                .foregroundStyle(.secondary)
                .kerning(0.5)

            Spacer()

            if total > 0 {
                Text("\(doneCount) / \(total)")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .monospacedDigit()
            }

            Button {
                let defaultScope: TaskScope? = {
                    if case .project(let url) = scopeFilter { return .project(rootURL: url) }
                    if case .group(let id) = scopeFilter { return .group(groupID: id) }
                    return nil
                }()
                onAddTask(defaultScope)
            } label: {
                Image(systemName: "plus")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Add task")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: - Root group model

    private struct RootTaskGroup: Identifiable {
        let key: String
        let displayName: String
        let tasks: [TaskItem]
        let progress: Int
        var id: String { key }
    }

    private func groupDisplayName(for scope: TaskScope) -> String {
        switch scope {
        case .project(let url): return url.lastPathComponent
        case .group(let id):    return taskStore.taskGroup(id: id)?.name ?? "Group"
        case .global:           return "Global"
        }
    }

    private func makeRootGroups(_ tasks: [TaskItem]) -> [RootTaskGroup] {
        var keyOrder: [String] = []
        var dictTasks: [String: [TaskItem]] = [:]
        var dictName: [String: String] = [:]
        for task in tasks {
            let key = task.scope.groupKey
            if dictTasks[key] == nil {
                keyOrder.append(key)
                dictName[key] = groupDisplayName(for: task.scope)
                dictTasks[key] = []
            }
            dictTasks[key]!.append(task)
        }

        let storedOrder = taskStore.childGroupOrders[Self.rootGroupOrderID] ?? []
        var orderedKeys = storedOrder.filter { dictTasks[$0] != nil }
        for key in keyOrder where !orderedKeys.contains(key) { orderedKeys.append(key) }

        return orderedKeys.compactMap { key -> RootTaskGroup? in
            guard let groupTasks = dictTasks[key] else { return nil }
            let avg = groupTasks.isEmpty ? 0 : groupTasks.map(\.progress).reduce(0, +) / groupTasks.count
            return RootTaskGroup(key: key, displayName: dictName[key] ?? key, tasks: groupTasks, progress: avg)
        }
    }

    // MARK: - Grouped task list

    private func groupedTaskList(rootTasks: [TaskItem]) -> some View {
        let groups = makeRootGroups(rootTasks)
        return LazyVStack(spacing: 0) {
            ForEach(groups) { group in
                groupSection(group: group)
                    .draggable(group.key) {
                        Text(group.displayName)
                            .font(.caption)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(.regularMaterial)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                    .dropDestination(for: String.self) { droppedKeys, _ in
                        guard let from = droppedKeys.first, from != group.key else { return false }
                        reorderRootGroups(moving: from, before: group.key, in: rootTasks)
                        return true
                    }
            }
        }
    }

    private func groupSection(group: RootTaskGroup) -> some View {
        let isCollapsed = collapsedGroupKeys.contains(group.key)
        return VStack(spacing: 0) {
            groupHeader(group: group, isCollapsed: isCollapsed)
            if !isCollapsed {
                let lastTask = group.tasks.last
                ForEach(group.tasks) { task in
                    TaskRowView(
                        task: task,
                        taskStore: taskStore,
                        isExpanded: !collapsedTaskIDs.contains(task.id),
                        onToggleExpand: {
                            if collapsedTaskIDs.contains(task.id) {
                                collapsedTaskIDs.remove(task.id)
                            } else {
                                collapsedTaskIDs.insert(task.id)
                            }
                        },
                        onSelect: onSelectTask
                    )
                    if task.id != lastTask?.id {
                        Divider().padding(.leading, 36)
                    }
                }
            }
            Divider()
        }
    }

    private func groupHeader(group: RootTaskGroup, isCollapsed: Bool) -> some View {
        HStack(spacing: 6) {
            Button {
                if collapsedGroupKeys.contains(group.key) {
                    collapsedGroupKeys.remove(group.key)
                } else {
                    collapsedGroupKeys.insert(group.key)
                }
            } label: {
                Image(systemName: isCollapsed ? "chevron.right" : "chevron.down")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 16, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Text(group.displayName)
                .font(.callout)
                .fontWeight(.semibold)

            Text("(\(group.tasks.count))")
                .font(.caption)
                .foregroundStyle(.tertiary)

            Spacer()

            Text("\(group.progress)%")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 32, alignment: .trailing)

            Image(systemName: "line.3.horizontal")
                .font(.system(size: 10))
                .foregroundStyle(.quaternary)
                .padding(.trailing, 4)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Color.secondary.opacity(0.06))
        .contentShape(Rectangle())
    }

    private func reorderRootGroups(moving fromKey: String, before targetKey: String, in tasks: [TaskItem]) {
        var keys = makeRootGroups(tasks).map(\.key)
        guard let fromIdx = keys.firstIndex(of: fromKey),
              keys.contains(targetKey) else { return }
        keys.remove(at: fromIdx)
        let insertIdx = keys.firstIndex(of: targetKey) ?? keys.endIndex
        keys.insert(fromKey, at: insertIdx)
        taskStore.setChildGroupOrder(parentID: Self.rootGroupOrderID, order: keys)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        HStack {
            Spacer()
            Text("No tasks")
                .font(.callout)
                .foregroundStyle(.tertiary)
            Spacer()
        }
        .padding(.vertical, 12)
    }
}
