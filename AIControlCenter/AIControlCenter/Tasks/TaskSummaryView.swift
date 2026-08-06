import SwiftUI

/// Compact task summary shown in AgentDetailView for a specific project.
struct TaskSummaryView: View {
    let projectURL: URL
    let taskStore: TaskStore

    private var tasks: [TaskItem] { taskStore.rootTasks(forProjectURL: projectURL) }
    private var doneCount: Int { tasks.filter(\.isDone).count }
    private var total: Int { tasks.count }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            headerRow
            if !tasks.isEmpty {
                segmentedTrack
                taskList
            } else {
                Text("No tasks for this project")
                    .font(.callout)
                    .foregroundStyle(.tertiary)
                    .padding(.vertical, 4)
            }
        }
    }

    // MARK: - Header

    private var headerRow: some View {
        HStack {
            Label("Tasks", systemImage: "checklist")
                .font(.caption.bold())
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            Spacer()
            if total > 0 {
                Text("\(doneCount) / \(total) done")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .monospacedDigit()
            }
        }
    }

    // MARK: - Segmented Progress Track

    private var segmentedTrack: some View {
        GeometryReader { geo in
            let segCount = max(total, 1)
            let gap: CGFloat = 2
            let segWidth = (geo.size.width - gap * CGFloat(segCount - 1)) / CGFloat(segCount)
            HStack(spacing: gap) {
                ForEach(Array(tasks.enumerated()), id: \.offset) { _, task in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(segmentColor(for: task))
                        .frame(width: segWidth, height: 4)
                }
            }
        }
        .frame(height: 4)
    }

    // MARK: - Task List

    private var taskList: some View {
        VStack(spacing: 0) {
            ForEach(tasks) { task in
                summaryRow(task)
                if task.id != tasks.last?.id {
                    Divider()
                }
            }
        }
    }

    private func summaryRow(_ task: TaskItem) -> some View {
        HStack(spacing: 8) {
            // Status indicator
            ZStack {
                Circle()
                    .strokeBorder(task.isDone ? Color.green : Color.secondary.opacity(0.4), lineWidth: 1.5)
                    .frame(width: 14, height: 14)
                if task.isDone {
                    Circle().fill(Color.green).frame(width: 14, height: 14)
                    Image(systemName: "checkmark")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.white)
                } else if task.status == .inProgress {
                    Circle()
                        .strokeBorder(Color.yellow, lineWidth: 1.5)
                        .frame(width: 14, height: 14)
                }
            }

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
                    .foregroundStyle(task.priority == .urgent ? .red : .orange)
            }
        }
        .padding(.vertical, 5)
    }

    // MARK: - Helpers

    private func segmentColor(for task: TaskItem) -> Color {
        switch task.status {
        case .done:       .green
        case .inProgress: .yellow
        case .todo:       Color.secondary.opacity(0.25)
        case .cancelled:  Color.secondary.opacity(0.1)
        }
    }
}
