import SwiftUI

// MARK: - TaskRowView

struct TaskRowView: View {
    let task: TaskItem
    let taskStore: TaskStore
    let onEdit: (TaskItem) -> Void

    private var category: TaskCategory? {
        task.categoryID.flatMap { taskStore.category(id: $0) }
    }

    var body: some View {
        VStack(spacing: 0) {
            rowContent(task, isSubtask: false)
            subtaskRows
        }
    }

    private var subtaskRows: some View {
        let children = taskStore.subtasks(of: task.id)
        return ForEach(children) { child in
            HStack(spacing: 0) {
                VStack(spacing: 0) {
                    Rectangle()
                        .fill(Color.secondary.opacity(0.2))
                        .frame(width: 1)
                }
                .frame(width: 16)
                .padding(.leading, 20)

                rowContent(child, isSubtask: true)
            }
        }
    }

    @ViewBuilder
    private func rowContent(_ item: TaskItem, isSubtask: Bool) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Button { taskStore.toggleDone(id: item.id) } label: {
                TaskStatusIndicatorView(
                    status: item.status,
                    size: isSubtask ? 13 : 15,
                    isSubtask: isSubtask
                )
            }
            .buttonStyle(.plain)
            .padding(.top, 1)

            VStack(alignment: .leading, spacing: 3) {
                Text(item.title)
                    .font(isSubtask ? .caption : .callout)
                    .foregroundStyle(item.isDone ? .tertiary : .primary)
                    .strikethrough(item.isDone, color: Color.secondary)
                    .lineLimit(2)

                if !isSubtask {
                    HStack(spacing: 4) {
                        scopeBadge(item.scope)
                        if let cat = category {
                            badge(cat.name, color: Color(hex: cat.colorHex))
                        }
                        if item.priority != .medium {
                            badge(item.priority.displayName, color: item.priority.color)
                        }
                    }
                }
            }

            Spacer(minLength: 0)

            if !isSubtask && (item.priority == .high || item.priority == .urgent) {
                Text(item.priority.displayName)
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .foregroundStyle(item.priority.color)
                    .frame(width: 36, alignment: .trailing)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, isSubtask ? 4 : 6)
        .contentShape(Rectangle())
        .contextMenu {
            Button("Edit") { onEdit(item) }
            Divider()
            Button("Delete", role: .destructive) {
                taskStore.deleteTask(id: item.id)
            }
        }
    }

    @ViewBuilder
    private func scopeBadge(_ scope: TaskScope) -> some View {
        switch scope {
        case .project(let url):
            badge(url.lastPathComponent, color: .accentColor)
        case .group:
            badge("Group", color: .purple)
        case .global:
            Text("Global")
                .font(.caption2)
                .fontWeight(.medium)
                .padding(.horizontal, 5)
                .padding(.vertical, 1)
                .background(Color.secondary.opacity(0.1))
                .foregroundStyle(.secondary)
                .clipShape(RoundedRectangle(cornerRadius: 3))
        }
    }

    private func badge(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.caption2)
            .fontWeight(.medium)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(color.opacity(0.15))
            .foregroundStyle(color)
            .clipShape(RoundedRectangle(cornerRadius: 3))
    }
}
