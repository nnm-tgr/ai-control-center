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
    @State private var collapsedGroupKeys: Set<String> = []

    private var category: TaskCategory? {
        task.categoryID.flatMap { taskStore.category(id: $0) }
    }

    var body: some View {
        let children = taskStore.subtasks(of: task.id)
        return VStack(spacing: 0) {
            rootRow(hasChildren: !children.isEmpty)
            if isExpanded && !children.isEmpty {
                groupedSubtaskRows(children)
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

            // Checkbox — disabled for parent tasks (status is derived from children)
            Button { taskStore.toggleDone(id: task.id) } label: {
                TaskStatusIndicatorView(status: task.status, size: 15)
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(hasChildren)

            // Title + inline badges as a Button so it has a well-defined,
            // non-overlapping hit area that doesn't compete with the checkbox.
            // Spacer inside the label stretches the hit area to fill remaining width.
            Button { onSelect(task) } label: {
                HStack(alignment: .center, spacing: 0) {
                    HStack(alignment: .center, spacing: 5) {
                        Text(task.title)
                            .font(.body)
                            .foregroundStyle(task.isDone ? .tertiary : .primary)
                            .strikethrough(task.isDone, color: Color.secondary)
                            .lineLimit(1)
                        if let cat = category {
                            badge(cat.name, color: Color(hex: cat.colorHex))
                        }
                        if task.priority != .medium {
                            badge(task.priority.displayName, color: task.priority.color)
                        }
                    }
                    Spacer(minLength: 0)
                }
            }
            .buttonStyle(.plain)

            // Status and progress: read-only for parent tasks (derived from children)
            if hasChildren {
                derivedStatusBadge
                derivedProgressText
            } else {
                statusMenu
                progressButton
            }
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

    // MARK: - Derived (read-only) controls for parent tasks

    private var derivedStatusBadge: some View {
        Text(task.status.displayName)
            .font(.caption)
            .fontWeight(.medium)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(task.status.color.opacity(0.13))
            .foregroundStyle(task.status.color.opacity(0.7))
            .clipShape(Capsule())
    }

    private var derivedProgressText: some View {
        Text("\(task.progress)%")
            .font(.caption.monospacedDigit())
            .fontWeight(.medium)
            .foregroundStyle(.secondary.opacity(0.6))
            .frame(width: 34, alignment: .trailing)
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

    // MARK: - Subtask group model

    private struct SubtaskGroup: Identifiable {
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

    private func makeSubtaskGroups(_ children: [TaskItem]) -> [SubtaskGroup] {
        var keyOrder: [String] = []
        var dictTasks: [String: [TaskItem]] = [:]
        var dictName: [String: String] = [:]
        for child in children {
            let key = child.scope.groupKey
            if dictTasks[key] == nil {
                keyOrder.append(key)
                dictName[key] = groupDisplayName(for: child.scope)
                dictTasks[key] = []
            }
            dictTasks[key]!.append(child)
        }

        let storedOrder = taskStore.childGroupOrders[task.id] ?? []
        var orderedKeys = storedOrder.filter { dictTasks[$0] != nil }
        for key in keyOrder where !orderedKeys.contains(key) { orderedKeys.append(key) }

        return orderedKeys.compactMap { key -> SubtaskGroup? in
            guard let tasks = dictTasks[key] else { return nil }
            let avg = tasks.isEmpty ? 0 : tasks.map(\.progress).reduce(0, +) / tasks.count
            return SubtaskGroup(key: key, displayName: dictName[key] ?? key, tasks: tasks, progress: avg)
        }
    }

    // MARK: - Grouped subtask rows

    private func groupedSubtaskRows(_ children: [TaskItem]) -> some View {
        let groups = makeSubtaskGroups(children)
        return VStack(spacing: 0) {
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
                        reorderGroups(moving: from, before: group.key, in: children)
                        return true
                    }
            }
        }
    }

    private func groupSection(group: SubtaskGroup) -> some View {
        let isCollapsed = collapsedGroupKeys.contains(group.key)
        return VStack(spacing: 0) {
            groupHeader(group: group, isCollapsed: isCollapsed)
            if !isCollapsed {
                ForEach(group.tasks) { child in
                    HStack(spacing: 0) {
                        VStack(spacing: 0) {
                            Rectangle()
                                .fill(Color.secondary.opacity(0.15))
                                .frame(width: 1)
                        }
                        .frame(width: 16)
                        .padding(.leading, 28)
                        SubtaskRowView(item: child, taskStore: taskStore, onSelect: onSelect)
                    }
                }
            }
        }
    }

    private func groupHeader(group: SubtaskGroup, isCollapsed: Bool) -> some View {
        HStack(spacing: 5) {
            Color.clear.frame(width: 20)
            Button {
                if collapsedGroupKeys.contains(group.key) {
                    collapsedGroupKeys.remove(group.key)
                } else {
                    collapsedGroupKeys.insert(group.key)
                }
            } label: {
                Image(systemName: isCollapsed ? "chevron.right" : "chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.tertiary)
                    .frame(width: 14, height: 20)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Text(group.displayName)
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)

            if !group.tasks.isEmpty {
                Text("(\(group.tasks.count))")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            Spacer()

            Text("\(group.progress)%")
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.tertiary)
                .frame(width: 30, alignment: .trailing)

            Image(systemName: "line.3.horizontal")
                .font(.system(size: 9))
                .foregroundStyle(.quaternary)
                .padding(.trailing, 4)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 3)
        .background(Color.secondary.opacity(0.05))
        .contentShape(Rectangle())
    }

    private func reorderGroups(moving fromKey: String, before targetKey: String, in children: [TaskItem]) {
        var keys = makeSubtaskGroups(children).map(\.key)
        guard let fromIdx = keys.firstIndex(of: fromKey),
              keys.contains(targetKey) else { return }
        keys.remove(at: fromIdx)
        let insertIdx = keys.firstIndex(of: targetKey) ?? keys.endIndex
        keys.insert(fromKey, at: insertIdx)
        taskStore.setChildGroupOrder(parentID: task.id, order: keys)
    }

    // MARK: - Badge

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

            // Title + inline category as Button with Spacer inside — fills remaining
            // width and keeps hit area clearly separated from checkbox.
            Button { onSelect(item) } label: {
                HStack(alignment: .center, spacing: 0) {
                    HStack(alignment: .center, spacing: 4) {
                        Text(item.title)
                            .font(.callout)
                            .foregroundStyle(item.isDone ? .tertiary : .secondary)
                            .strikethrough(item.isDone, color: Color.secondary)
                            .lineLimit(1)
                        if let catID = item.categoryID,
                           let cat = taskStore.category(id: catID) {
                            Text(cat.name)
                                .font(.caption2).fontWeight(.medium)
                                .padding(.horizontal, 4).padding(.vertical, 1)
                                .background(Color(hex: cat.colorHex).opacity(0.15))
                                .foregroundStyle(Color(hex: cat.colorHex))
                                .clipShape(RoundedRectangle(cornerRadius: 3))
                        }
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

}
