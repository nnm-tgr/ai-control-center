import SwiftUI

struct TaskSectionView: View {
    @Environment(AppState.self) private var appState
    let scopeFilter: TaskScopeFilter
    let onAddTask: (TaskScope?) -> Void
    let onSelectTask: (TaskItem) -> Void

    @State private var collapsedTaskIDs: Set<UUID> = []

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
                taskList(rootTasks: rootTasks)
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

    // MARK: - Task List

    private func taskList(rootTasks: [TaskItem]) -> some View {
        let lastID = rootTasks.last?.id
        return LazyVStack(spacing: 0) {
            ForEach(rootTasks) { task in
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
                if task.id != lastID {
                    Divider().padding(.leading, 36)
                }
            }
        }
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
