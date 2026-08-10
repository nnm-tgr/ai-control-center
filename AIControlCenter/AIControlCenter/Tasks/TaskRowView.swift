import SwiftUI

// MARK: - TaskRowView

struct TaskRowView: View {
    let task: TaskItem
    let taskStore: TaskStore
    let isExpanded: Bool
    let onToggleExpand: () -> Void
    let onSelect: (TaskItem) -> Void

    @State private var showProgressPopover = false
    @State private var draftProgress: Double = 0

    private var category: TaskCategory? {
        task.categoryID.flatMap { taskStore.category(id: $0) }
    }

    var body: some View {
        let children = taskStore.subtasks(of: task.id)
        return VStack(spacing: 0) {
            rootRow(hasChildren: !children.isEmpty)
            if isExpanded && !children.isEmpty {
                subtaskRows(children)
            }
        }
    }

    // MARK: - Root row

    private func rootRow(hasChildren: Bool) -> some View {
        HStack(alignment: .center, spacing: 8) {
            // Disclosure chevron — 16×24 hit area for reliable clicking
            if hasChildren {
                Button { onToggleExpand() } label: {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .foregroundStyle(.secondary)
                        .animation(.easeInOut(duration: 0.15), value: isExpanded)
                        .frame(width: 16, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }

            // Checkbox — 24×24 hit area prevents misses on the 15 pt indicator
            Button { taskStore.toggleDone(id: task.id) } label: {
                TaskStatusIndicatorView(status: task.status, size: 15)
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // Title + badges as a Button so it has a well-defined,
            // non-overlapping hit area that doesn't compete with the checkbox.
            // Spacer inside the label stretches the hit area to fill remaining width.
            Button { onSelect(task) } label: {
                HStack(alignment: .center, spacing: 0) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(task.title)
                            .font(.body)
                            .foregroundStyle(task.isDone ? .tertiary : .primary)
                            .strikethrough(task.isDone, color: Color.secondary)
                            .lineLimit(1)

                        HStack(spacing: 4) {
                            scopeBadge(task.scope)
                            if let cat = category {
                                badge(cat.name, color: Color(hex: cat.colorHex))
                            }
                            if task.priority != .medium {
                                badge(task.priority.displayName, color: task.priority.color)
                            }
                        }
                    }
                    Spacer(minLength: 0)
                }
            }
            .buttonStyle(.plain)

            // Status menu
            statusMenu

            // Progress
            progressButton
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .contextMenu {
            Button("Show Detail") { onSelect(task) }
            Divider()
            Button("Delete", role: .destructive) { taskStore.deleteTask(id: task.id) }
        }
    }

    // MARK: - Status menu

    private var statusMenu: some View {
        Menu {
            ForEach(TaskStatus.allCases, id: \.self) { status in
                Button {
                    taskStore.setStatus(id: task.id, status: status)
                } label: {
                    Label(status.displayName, systemImage: status.iconName)
                }
            }
        } label: {
            Text(task.status.displayName)
                .font(.caption)
                .fontWeight(.medium)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(task.status.color.opacity(0.13))
                .foregroundStyle(task.status.color)
                .clipShape(Capsule())
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    // MARK: - Progress button + popover

    private var progressButton: some View {
        Button {
            draftProgress = Double(task.progress)
            showProgressPopover = true
        } label: {
            Text("\(task.progress)%")
                .font(.caption.monospacedDigit())
                .fontWeight(.medium)
                .foregroundStyle(.secondary)
                .frame(width: 34, alignment: .trailing)
        }
        .buttonStyle(.plain)
        .popover(isPresented: $showProgressPopover, arrowEdge: .bottom) {
            progressPopover
        }
    }

    private var progressPopover: some View {
        VStack(spacing: 12) {
            HStack {
                Text("Progress")
                    .font(.callout.bold())
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(Int(draftProgress))%")
                    .font(.body.monospacedDigit().bold())
            }

            Slider(value: $draftProgress, in: 0...100, step: 5)
                .tint(task.status.color)
                .frame(width: 180)

            HStack(spacing: 8) {
                ForEach([0, 25, 50, 75, 100], id: \.self) { pct in
                    Button("\(pct)") {
                        draftProgress = Double(pct)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
                    .tint(pct == Int(draftProgress) ? task.status.color : nil)
                }
            }

            HStack {
                Button("Cancel") { showProgressPopover = false }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Set") {
                    taskStore.setProgress(id: task.id, progress: Int(draftProgress))
                    showProgressPopover = false
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
        }
        .padding(14)
        .frame(width: 220)
    }

    // MARK: - Subtask rows

    private func subtaskRows(_ children: [TaskItem]) -> some View {
        ForEach(children) { child in
            HStack(spacing: 0) {
                VStack(spacing: 0) {
                    Rectangle()
                        .fill(Color.secondary.opacity(0.2))
                        .frame(width: 1)
                }
                .frame(width: 16)
                .padding(.leading, 20)

                SubtaskRowView(item: child, taskStore: taskStore, onSelect: onSelect)
            }
        }
    }

    // MARK: - Badges

    @ViewBuilder
    private func scopeBadge(_ scope: TaskScope) -> some View {
        switch scope {
        case .project(let url): badge(url.lastPathComponent, color: .accentColor)
        case .group:            badge("Group", color: .purple)
        case .global:
            Text("Global")
                .font(.caption).fontWeight(.medium)
                .padding(.horizontal, 5).padding(.vertical, 1)
                .background(Color.secondary.opacity(0.1))
                .foregroundStyle(.secondary)
                .clipShape(RoundedRectangle(cornerRadius: 3))
        }
    }

    private func badge(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.caption).fontWeight(.medium)
            .padding(.horizontal, 5).padding(.vertical, 1)
            .background(color.opacity(0.15))
            .foregroundStyle(color)
            .clipShape(RoundedRectangle(cornerRadius: 3))
    }
}

// MARK: - SubtaskRowView

private struct SubtaskRowView: View {
    let item: TaskItem
    let taskStore: TaskStore
    let onSelect: (TaskItem) -> Void

    @State private var showProgressPopover = false
    @State private var draftProgress: Double = 0

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            // Checkbox — 22×22 hit area (indicator is 13 pt)
            Button { taskStore.toggleDone(id: item.id) } label: {
                TaskStatusIndicatorView(status: item.status, size: 13, isSubtask: true)
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // Title + scope as Button with Spacer inside — fills remaining
            // width and keeps hit area clearly separated from checkbox.
            Button { onSelect(item) } label: {
                HStack(alignment: .center, spacing: 0) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.title)
                            .font(.callout)
                            .foregroundStyle(item.isDone ? .tertiary : .secondary)
                            .strikethrough(item.isDone, color: Color.secondary)
                            .lineLimit(1)

                        scopeBadge(item.scope)
                    }
                    Spacer(minLength: 0)
                }
            }
            .buttonStyle(.plain)

            statusMenu
            progressButton
        }
        .padding(.vertical, 5)
        .padding(.horizontal, 8)
        .contentShape(Rectangle())
        .contextMenu {
            Button("Show Detail") { onSelect(item) }
            Divider()
            Button("Delete", role: .destructive) { taskStore.deleteTask(id: item.id) }
        }
    }

    // MARK: - Status menu

    private var statusMenu: some View {
        Menu {
            ForEach(TaskStatus.allCases, id: \.self) { status in
                Button {
                    taskStore.setStatus(id: item.id, status: status)
                } label: {
                    Label(status.displayName, systemImage: status.iconName)
                }
            }
        } label: {
            Text(item.status.displayName)
                .font(.caption)
                .fontWeight(.medium)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(item.status.color.opacity(0.13))
                .foregroundStyle(item.status.color)
                .clipShape(Capsule())
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    // MARK: - Progress button + popover

    private var progressButton: some View {
        Button {
            draftProgress = Double(item.progress)
            showProgressPopover = true
        } label: {
            Text("\(item.progress)%")
                .font(.caption.monospacedDigit())
                .fontWeight(.medium)
                .foregroundStyle(.secondary)
                .frame(width: 34, alignment: .trailing)
        }
        .buttonStyle(.plain)
        .popover(isPresented: $showProgressPopover, arrowEdge: .bottom) {
            progressPopover
        }
    }

    private var progressPopover: some View {
        VStack(spacing: 12) {
            HStack {
                Text("Progress")
                    .font(.callout.bold())
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(Int(draftProgress))%")
                    .font(.body.monospacedDigit().bold())
            }

            Slider(value: $draftProgress, in: 0...100, step: 5)
                .tint(item.status.color)
                .frame(width: 180)

            HStack(spacing: 8) {
                ForEach([0, 25, 50, 75, 100], id: \.self) { pct in
                    Button("\(pct)") {
                        draftProgress = Double(pct)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
                    .tint(pct == Int(draftProgress) ? item.status.color : nil)
                }
            }

            HStack {
                Button("Cancel") { showProgressPopover = false }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Set") {
                    taskStore.setProgress(id: item.id, progress: Int(draftProgress))
                    showProgressPopover = false
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
        }
        .padding(14)
        .frame(width: 220)
    }

    // MARK: - Scope badge

    @ViewBuilder
    private func scopeBadge(_ scope: TaskScope) -> some View {
        switch scope {
        case .project(let url):
            badge(url.lastPathComponent, color: .accentColor)
        case .group:
            badge("Group", color: .purple)
        case .global:
            Text("Global")
                .font(.caption).fontWeight(.medium)
                .padding(.horizontal, 5).padding(.vertical, 1)
                .background(Color.secondary.opacity(0.1))
                .foregroundStyle(.secondary)
                .clipShape(RoundedRectangle(cornerRadius: 3))
        }
    }

    private func badge(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.caption).fontWeight(.medium)
            .padding(.horizontal, 5).padding(.vertical, 1)
            .background(color.opacity(0.15))
            .foregroundStyle(color)
            .clipShape(RoundedRectangle(cornerRadius: 3))
    }
}
