import SwiftUI

struct TaskSectionView: View {
    @Environment(AppState.self) private var appState
    let scopeFilter: TaskScopeFilter
    let onAddTask: (TaskScope?) -> Void
    let onEditTask: (TaskItem) -> Void

    private var taskStore: TaskStore { appState.taskStore }

    private var rootTasks: [TaskItem] { taskStore.rootTasks(for: scopeFilter) }
    private var doneCount: Int { taskStore.doneCount(for: scopeFilter) }
    private var totalCount: Int { taskStore.totalCount(for: scopeFilter) }

    var body: some View {
        VStack(spacing: 0) {
            sectionHeader
            Divider()
            if rootTasks.isEmpty {
                emptyState
            } else {
                taskList
            }
        }
    }

    // MARK: - Header

    private var sectionHeader: some View {
        HStack {
            Text("TASKS")
                .font(.caption)
                .fontWeight(.bold)
                .foregroundStyle(.secondary)
                .kerning(0.5)

            Spacer()

            if totalCount > 0 {
                Text("\(doneCount) / \(totalCount)")
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

    private var taskList: some View {
        LazyVStack(spacing: 0) {
            ForEach(rootTasks) { task in
                TaskRowView(
                    task: task,
                    taskStore: taskStore,
                    onEdit: onEditTask
                )
                if task.id != rootTasks.last?.id {
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
