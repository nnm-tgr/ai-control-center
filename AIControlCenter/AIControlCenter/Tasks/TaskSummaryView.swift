import SwiftUI

/// Compact task summary shown in AgentDetailView for a specific project.
struct TaskSummaryView: View {
    let projectURL: URL
    let taskStore: TaskStore

    var body: some View {
        let tasks = taskStore.rootTasks(forProjectURL: projectURL)
        let doneCount = tasks.filter(\.isDone).count

        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Tasks", systemImage: "checklist")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                Spacer()
                if !tasks.isEmpty {
                    Text("\(doneCount) / \(tasks.count) done")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .monospacedDigit()
                }
            }

            if tasks.isEmpty {
                Text("No tasks for this project")
                    .font(.callout)
                    .foregroundStyle(.tertiary)
                    .padding(.vertical, 4)
            } else {
                segmentedTrack(tasks: tasks)
                taskList(tasks: tasks)
            }
        }
    }

    // MARK: - Segmented Progress Track

    private func segmentedTrack(tasks: [TaskItem]) -> some View {
        GeometryReader { geo in
            let gap: CGFloat = 2
            let segWidth = (geo.size.width - gap * CGFloat(tasks.count - 1)) / CGFloat(tasks.count)
            HStack(spacing: gap) {
                ForEach(tasks) { task in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(segmentColor(for: task))
                        .frame(width: segWidth, height: 4)
                }
            }
        }
        .frame(height: 4)
    }

    // MARK: - Task List

    private func taskList(tasks: [TaskItem]) -> some View {
        let lastID = tasks.last?.id
        return VStack(spacing: 0) {
            ForEach(tasks) { task in
                summaryRow(task)
                if task.id != lastID {
                    Divider()
                }
            }
        }
    }

    private func summaryRow(_ task: TaskItem) -> some View {
        HStack(spacing: 8) {
            TaskStatusIndicatorView(status: task.status, size: 14)

            Text(task.title)
                .font(.callout)
                .foregroundStyle(task.isDone ? .tertiary : .secondary)
                .strikethrough(task.isDone, color: Color.secondary)
                .lineLimit(1)

            Spacer()

            if task.priority == .high || task.priority == .urgent {
                Text(task.priority.displayName)
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .foregroundStyle(task.priority.color)
            }
        }
        .padding(.vertical, 5)
    }

    // MARK: - Helpers

    private func segmentColor(for task: TaskItem) -> Color {
        task.status.color.opacity(task.status == .todo ? 0.25 : 0.85)
    }
}
