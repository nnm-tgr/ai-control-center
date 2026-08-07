import SwiftUI

struct AddEditTaskSheet: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    var editingTask: TaskItem?
    var defaultScope: TaskScope?

    @State private var title: String = ""
    @State private var notes: String = ""
    @State private var status: TaskStatus = .todo
    @State private var priority: TaskPriority = .medium
    @State private var selectedScope: TaskScope = .global
    @State private var selectedParentID: UUID? = nil
    @State private var selectedCategoryID: UUID? = nil
    @State private var isCreatingCategory: Bool = false
    @State private var newCategoryName: String = ""
    @State private var newCategoryColorHex: String = TaskCategory.presetColors[0]

    private var taskStore: TaskStore { appState.taskStore }
    private var isEditing: Bool { editingTask != nil }

    var body: some View {
        VStack(spacing: 0) {
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
                    field("Title") {
                        TextField("Task title", text: $title)
                            .textFieldStyle(.roundedBorder)
                    }

                    field("Notes") {
                        TextEditor(text: $notes)
                            .font(.callout)
                            .frame(minHeight: 60)
                            .overlay(
                                RoundedRectangle(cornerRadius: 5)
                                    .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                            )
                    }

                    field("Priority") {
                        Picker("Priority", selection: $priority) {
                            ForEach(TaskPriority.allCases, id: \.self) {
                                Text($0.displayName).tag($0)
                            }
                        }
                        .pickerStyle(.segmented)
                    }

                    if isEditing {
                        field("Status") {
                            Picker("Status", selection: $status) {
                                ForEach(TaskStatus.allCases, id: \.self) {
                                    Text($0.displayName).tag($0)
                                }
                            }
                            .pickerStyle(.segmented)
                        }
                    }

                    field("Scope") { scopePicker }

                    field("Category") { categorySection }

                    field("Parent Task (optional)") { parentPicker }
                }
                .padding(16)
            }
        }
        .frame(width: 420)
        .onAppear { configure() }
    }

    // MARK: - Field wrapper

    private func field<C: View>(_ title: String, @ViewBuilder content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            content()
        }
    }

    // MARK: - Scope Picker

    private var scopePicker: some View {
        Picker("Scope", selection: $selectedScope) {
            Text("Global").tag(TaskScope.global)
            Divider()
            ForEach(appState.projects.filter(\.isReachable), id: \.id) { project in
                Text(project.name)
                    .tag(TaskScope.project(rootURL: project.rootURL))
            }
            if !taskStore.taskGroups.isEmpty {
                Divider()
                ForEach(taskStore.taskGroups) { group in
                    Text(group.name)
                        .tag(TaskScope.group(groupID: group.id))
                }
            }
        }
        .labelsHidden()
    }

    // MARK: - Category Section

    private var categorySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Existing categories
            categoryPicker

            // Inline new category form
            if isCreatingCategory {
                newCategoryForm
            } else {
                Button {
                    isCreatingCategory = true
                    newCategoryName = ""
                    newCategoryColorHex = TaskCategory.presetColors[0]
                } label: {
                    Label("New Category…", systemImage: "plus")
                        .font(.callout)
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.accentColor)
            }
        }
    }

    private var categoryPicker: some View {
        Picker("Category", selection: $selectedCategoryID) {
            Text("None").tag(UUID?(nil))
            if !taskStore.categories.isEmpty {
                Divider()
                ForEach(taskStore.categories) { cat in
                    HStack(spacing: 6) {
                        Circle()
                            .fill(Color(hex: cat.colorHex))
                            .frame(width: 8, height: 8)
                        Text(cat.name)
                    }
                    .tag(Optional(cat.id))
                }
            }
        }
        .labelsHidden()
    }

    private var newCategoryForm: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("Category name", text: $newCategoryName)
                .textFieldStyle(.roundedBorder)

            HStack(spacing: 6) {
                ForEach(TaskCategory.presetColors, id: \.self) { hex in
                    Circle()
                        .fill(Color(hex: hex))
                        .frame(width: 20, height: 20)
                        .overlay(
                            Circle()
                                .strokeBorder(.white.opacity(0.8), lineWidth: 2)
                                .opacity(newCategoryColorHex == hex ? 1 : 0)
                        )
                        .onTapGesture { newCategoryColorHex = hex }
                }
                Spacer()

                Button("Cancel") {
                    isCreatingCategory = false
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)

                Button("Create") {
                    createCategory()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(newCategoryName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(10)
        .background(Color.secondary.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8))
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

    // MARK: - Actions

    private func createCategory() {
        let name = newCategoryName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        let cat = TaskCategory(name: name, colorHex: newCategoryColorHex)
        taskStore.addCategory(cat)
        selectedCategoryID = cat.id
        isCreatingCategory = false
    }

    private func configure() {
        if let task = editingTask {
            title = task.title
            notes = task.notes
            status = task.status
            priority = task.priority
            selectedParentID = task.parentID
            selectedScope = task.scope
            selectedCategoryID = task.categoryID
        } else {
            selectedScope = defaultScope ?? .global
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
            task.scope = selectedScope
            task.parentID = selectedParentID
            task.categoryID = selectedCategoryID
            taskStore.updateTask(task)
        } else {
            taskStore.addTask(TaskItem(
                title: trimmed,
                notes: notes,
                priority: priority,
                scope: selectedScope,
                parentID: selectedParentID,
                categoryID: selectedCategoryID
            ))
        }
        dismiss()
    }
}

// MARK: - Color from hex

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let r = Double((int >> 16) & 0xFF) / 255
        let g = Double((int >> 8) & 0xFF) / 255
        let b = Double(int & 0xFF) / 255
        self.init(red: r, green: g, blue: b)
    }
}

#Preview("Add Task") {
    AddEditTaskSheet()
        .environment(AppState())
}
