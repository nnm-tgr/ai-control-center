import SwiftUI

struct AddEditTaskSheet: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    // nil = add mode; non-nil = edit mode
    var editingTask: TaskItem?
    var defaultScope: TaskScope?

    @State private var title: String = ""
    @State private var notes: String = ""
    @State private var status: TaskStatus = .todo
    @State private var priority: TaskPriority = .medium
    @State private var selectedScope: ScopeSelection = .global
    @State private var selectedParentID: UUID? = nil

    private var taskStore: TaskStore { appState.taskStore }
    private var isEditing: Bool { editingTask != nil }

    // Scope picker model
    private enum ScopeSelection: Hashable {
        case global
        case project(URL)
        case group(UUID)

        var taskScope: TaskScope {
            switch self {
            case .global:         .global
            case .project(let u): .project(rootURL: u)
            case .group(let id):  .group(groupID: id)
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text(isEditing ? "Edit Task" : "New Task")
                    .font(.headline)
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(isEditing ? "Save" : "Add") { save() }
                    .buttonStyle(.borderedProminent)
                    .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
                    .keyboardShortcut(.defaultAction)
            }
            .padding(16)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Title
                    VStack(alignment: .leading, spacing: 6) {
                        label("Title")
                        TextField("Task title", text: $title)
                            .textFieldStyle(.roundedBorder)
                    }

                    // Notes
                    VStack(alignment: .leading, spacing: 6) {
                        label("Notes")
                        TextEditor(text: $notes)
                            .font(.callout)
                            .frame(minHeight: 60)
                            .overlay(
                                RoundedRectangle(cornerRadius: 5)
                                    .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                            )
                    }

                    // Priority
                    VStack(alignment: .leading, spacing: 6) {
                        label("Priority")
                        Picker("Priority", selection: $priority) {
                            ForEach(TaskPriority.allCases, id: \.self) {
                                Text($0.displayName).tag($0)
                            }
                        }
                        .pickerStyle(.segmented)
                    }

                    // Status (edit mode only)
                    if isEditing {
                        VStack(alignment: .leading, spacing: 6) {
                            label("Status")
                            Picker("Status", selection: $status) {
                                ForEach(TaskStatus.allCases, id: \.self) {
                                    Text($0.displayName).tag($0)
                                }
                            }
                            .pickerStyle(.segmented)
                        }
                    }

                    // Scope
                    VStack(alignment: .leading, spacing: 6) {
                        label("Scope")
                        scopePicker
                    }

                    // Parent task (only shown when creating a subtask)
                    if selectedParentID != nil || !isEditing {
                        VStack(alignment: .leading, spacing: 6) {
                            label("Parent Task (optional)")
                            parentPicker
                        }
                    }
                }
                .padding(16)
            }
        }
        .frame(width: 420)
        .onAppear { configure() }
    }

    // MARK: - Scope Picker

    private var scopePicker: some View {
        Picker("Scope", selection: $selectedScope) {
            Text("Global").tag(ScopeSelection.global)
            Divider()
            ForEach(appState.projects.filter(\.isReachable), id: \.id) { project in
                Text(project.name)
                    .tag(ScopeSelection.project(project.rootURL))
            }
            if !taskStore.taskGroups.isEmpty {
                Divider()
                ForEach(taskStore.taskGroups) { group in
                    Text(group.name)
                        .tag(ScopeSelection.group(group.id))
                }
            }
        }
        .labelsHidden()
    }

    // MARK: - Parent Picker

    private var parentPicker: some View {
        let rootTasks = taskStore.rootTasks(for: .all).filter { item in
            editingTask.map { item.id != $0.id } ?? true
        }
        return Picker("Parent", selection: $selectedParentID) {
            Text("None (root task)").tag(UUID?(nil))
            ForEach(rootTasks) { task in
                Text(task.title).tag(Optional(task.id))
            }
        }
        .labelsHidden()
    }

    // MARK: - Helpers

    private func label(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .fontWeight(.semibold)
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
    }

    private func configure() {
        if let task = editingTask {
            title = task.title
            notes = task.notes
            status = task.status
            priority = task.priority
            selectedParentID = task.parentID
            selectedScope = scopeSelection(from: task.scope)
        } else if let scope = defaultScope {
            selectedScope = scopeSelection(from: scope)
        }
    }

    private func scopeSelection(from scope: TaskScope) -> ScopeSelection {
        switch scope {
        case .global:          .global
        case .project(let u):  .project(u)
        case .group(let id):   .group(id)
        }
    }

    private func save() {
        let trimmed = title.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }

        if var task = editingTask {
            task.title = trimmed
            task.notes = notes
            task.status = status
            task.priority = priority
            task.scope = selectedScope.taskScope
            task.parentID = selectedParentID
            taskStore.updateTask(task)
        } else {
            let newTask = TaskItem(
                title: trimmed,
                notes: notes,
                status: .todo,
                priority: priority,
                scope: selectedScope.taskScope,
                parentID: selectedParentID
            )
            taskStore.addTask(newTask)
        }
        dismiss()
    }
}

#Preview("Add Task") {
    AddEditTaskSheet()
        .environment(AppState())
}
