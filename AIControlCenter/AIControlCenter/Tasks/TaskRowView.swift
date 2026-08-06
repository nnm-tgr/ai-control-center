import SwiftUI

// MARK: - TaskRowView

struct TaskRowView: View {
    let task: TaskItem
    let taskStore: TaskStore
    let onEdit: (TaskItem) -> Void

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
                // Connector line
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
            // Checkbox
            Button {
                taskStore.toggleDone(id: item.id)
            } label: {
                ZStack {
                    if isSubtask {
                        RoundedRectangle(cornerRadius: 3)
                            .strokeBorder(
                                item.isDone ? Color.green : Color.secondary.opacity(0.5),
                                lineWidth: 1.5
                            )
                            .frame(width: 13, height: 13)
                        if item.isDone {
                            RoundedRectangle(cornerRadius: 3)
                                .fill(Color.green)
                                .frame(width: 13, height: 13)
                            Image(systemName: "checkmark")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundStyle(.white)
                        }
                    } else {
                        Circle()
                            .strokeBorder(
                                item.isDone ? Color.green : Color.secondary.opacity(0.5),
                                lineWidth: 1.5
                            )
                            .frame(width: 15, height: 15)
                        if item.isDone {
                            Circle()
                                .fill(Color.green)
                                .frame(width: 15, height: 15)
                            Image(systemName: "checkmark")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(.white)
                        } else if item.status == .inProgress {
                            Circle()
                                .strokeBorder(Color.yellow, lineWidth: 1.5)
                                .frame(width: 15, height: 15)
                        }
                    }
                }
            }
            .buttonStyle(.plain)
            .padding(.top, 1)

            // Title + badges
            VStack(alignment: .leading, spacing: 3) {
                Text(item.title)
                    .font(isSubtask ? .caption : .callout)
                    .foregroundStyle(item.isDone ? .tertiary : .primary)
                    .strikethrough(item.isDone, color: Color.secondary)
                    .lineLimit(2)

                if !isSubtask {
                    HStack(spacing: 4) {
                        scopeBadge(item.scope)
                        if item.priority != .medium {
                            priorityBadge(item.priority)
                        }
                    }
                }
            }

            Spacer(minLength: 0)

            if !isSubtask {
                priorityLabel(item.priority)
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
            Text(url.lastPathComponent)
                .font(.caption2)
                .fontWeight(.medium)
                .padding(.horizontal, 5)
                .padding(.vertical, 1)
                .background(Color.accentColor.opacity(0.15))
                .foregroundStyle(Color.accentColor)
                .clipShape(RoundedRectangle(cornerRadius: 3))
        case .group:
            Text("Group")
                .font(.caption2)
                .fontWeight(.medium)
                .padding(.horizontal, 5)
                .padding(.vertical, 1)
                .background(Color.purple.opacity(0.15))
                .foregroundStyle(Color.purple)
                .clipShape(RoundedRectangle(cornerRadius: 3))
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

    @ViewBuilder
    private func priorityBadge(_ priority: TaskPriority) -> some View {
        Text(priority.displayName)
            .font(.caption2)
            .fontWeight(.medium)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(priorityColor(priority).opacity(0.15))
            .foregroundStyle(priorityColor(priority))
            .clipShape(RoundedRectangle(cornerRadius: 3))
    }

    @ViewBuilder
    private func priorityLabel(_ priority: TaskPriority) -> some View {
        if priority == .high || priority == .urgent {
            Text(priority.displayName)
                .font(.caption2)
                .fontWeight(.semibold)
                .foregroundStyle(priorityColor(priority))
                .frame(width: 36, alignment: .trailing)
        }
    }

    private func priorityColor(_ priority: TaskPriority) -> Color {
        switch priority {
        case .low:    .secondary
        case .medium: .yellow
        case .high:   .orange
        case .urgent: .red
        }
    }
}
