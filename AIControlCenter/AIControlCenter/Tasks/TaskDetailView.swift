import SwiftUI

struct TaskDetailView: View {
    let taskID: UUID
    @Environment(AppState.self) private var appState
    @State private var showEdit = false
    @State private var newNoteText = ""
    @State private var editingNoteID: UUID? = nil
    @State private var editorRef = NoteEditorRef()

    private var taskStore: TaskStore { appState.taskStore }

    private var task: TaskItem? {
        taskStore.tasks.first(where: { $0.id == taskID })
    }

    var body: some View {
        Group {
            if let task {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        headerSection(task: task)
                            .padding(20)
                        Divider()
                        notesSection(task: task)
                            .padding(20)
                    }
                }
                .toolbar {
                    ToolbarItemGroup(placement: .primaryAction) {
                        Button("Edit") { showEdit = true }
                        Button {
                            taskStore.deleteTask(id: task.id)
                        } label: {
                            Image(systemName: "trash")
                                .foregroundStyle(.red)
                        }
                        .help("Delete task")
                    }
                }
                .sheet(isPresented: $showEdit) {
                    AddEditTaskSheet(editingTask: task)
                        .environment(appState)
                }
            } else {
                ContentUnavailableView("Task not found", systemImage: "checklist")
            }
        }
    }

    // MARK: - Header

    private func headerSection(task: TaskItem) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(task.title)
                .font(.title2)
                .fontWeight(.bold)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 6) {
                statusBadge(task.status)
                priorityBadge(task.priority)
                scopeBadge(task.scope)
                if let catID = task.categoryID,
                   let cat = taskStore.category(id: catID) {
                    colorBadge(cat.name, color: Color(hex: cat.colorHex))
                }
            }

            let isParent = taskStore.hasChildren(id: task.id)
            if isParent || task.progress > 0 || task.status == .inProgress {
                progressRow(task: task)
            }
            if isParent {
                Label("Progress and status derived from subtasks", systemImage: "arrow.triangle.merge")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func statusBadge(_ status: TaskStatus) -> some View {
        Label(status.displayName, systemImage: status.iconName)
            .font(.caption)
            .fontWeight(.medium)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(status.color.opacity(0.13))
            .foregroundStyle(status.color)
            .clipShape(Capsule())
    }

    private func priorityBadge(_ priority: TaskPriority) -> some View {
        Text(priority.displayName)
            .font(.caption)
            .fontWeight(.medium)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(priority.color.opacity(0.13))
            .foregroundStyle(priority.color)
            .clipShape(Capsule())
    }

    @ViewBuilder
    private func scopeBadge(_ scope: TaskScope) -> some View {
        switch scope {
        case .project(let url):
            colorBadge(url.lastPathComponent, color: .accentColor)
        case .group(let id):
            colorBadge(taskStore.taskGroup(id: id)?.name ?? "Group", color: .purple)
        case .global:
            Text("Global")
                .font(.caption).fontWeight(.medium)
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(Color.secondary.opacity(0.1))
                .foregroundStyle(.secondary)
                .clipShape(Capsule())
        }
    }

    private func colorBadge(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.caption)
            .fontWeight(.medium)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color.opacity(0.13))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }

    private func progressRow(task: TaskItem) -> some View {
        HStack(spacing: 10) {
            ProgressView(value: Double(task.progress) / 100.0)
                .tint(task.status.color)
            Text("\(task.progress)%")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 36, alignment: .trailing)
        }
    }

    // MARK: - Notes

    private func notesSection(task: TaskItem) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("NOTES")
                .font(.caption)
                .fontWeight(.bold)
                .foregroundStyle(.secondary)
                .kerning(0.5)

            if task.notes.isEmpty {
                Text("No notes yet.")
                    .font(.callout)
                    .foregroundStyle(.tertiary)
                    .padding(.vertical, 4)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(task.notes) { note in
                        noteRow(note: note, taskID: task.id)
                    }
                }
            }

            noteInputArea(taskID: task.id)
        }
    }

    private func noteRow(note: TaskNote, taskID: UUID) -> some View {
        let isEditing = editingNoteID == note.id
        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(note.createdAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                if isEditing {
                    Spacer()
                    Label("Editing", systemImage: "pencil.circle.fill")
                        .font(.caption2)
                        .foregroundStyle(Color.accentColor)
                }
            }

            Group {
                if let attributed = try? AttributedString(markdown: note.content) {
                    Text(attributed)
                } else {
                    Text(note.content)
                }
            }
            .font(.callout)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
            .opacity(isEditing ? 0.5 : 1)
        }
        .padding(10)
        .background(isEditing
            ? Color.accentColor.opacity(0.08)
            : Color.secondary.opacity(0.07))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay {
            if isEditing {
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(Color.accentColor.opacity(0.35), lineWidth: 1)
            }
        }
        .contextMenu {
            Button("Edit Note") { startEditing(note: note) }
            Divider()
            Button("Delete Note", role: .destructive) {
                if editingNoteID == note.id { cancelEdit() }
                taskStore.deleteNote(taskID: taskID, noteID: note.id)
            }
        }
    }

    // MARK: - Note Input Area

    private func noteInputArea(taskID: UUID) -> some View {
        VStack(spacing: 0) {
            noteToolbar(taskID: taskID)
            Divider()
            NoteEditorView(
                text: $newNoteText,
                ref: editorRef,
                onSubmit: { submitNote(taskID: taskID) }
            )
            .frame(minHeight: 64, maxHeight: 120)
            Divider()
            noteFooter(taskID: taskID)
        }
        .background(Color(nsColor: .textBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Color.secondary.opacity(0.18), lineWidth: 1)
        )
    }

    private func noteToolbar(taskID: UUID) -> some View {
        HStack(spacing: 2) {
            toolbarGroup([.bold, .italic, .strikethrough])
            toolbarSeparator()
            toolbarGroup([.inlineCode, .codeBlock])
            toolbarSeparator()
            toolbarGroup([.bullet, .numbered, .quote])
            Spacer()
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(Color.secondary.opacity(0.04))
    }

    private func toolbarGroup(_ actions: [MarkdownAction]) -> some View {
        HStack(spacing: 0) {
            ForEach(actions, id: \.self) { action in
                Button {
                    editorRef.applyMarkdown(action)
                } label: {
                    Image(systemName: action.icon)
                        .font(.system(size: 11, weight: .regular))
                        .frame(width: 26, height: 22)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help(action.label)
            }
        }
    }

    private func toolbarSeparator() -> some View {
        Rectangle()
            .fill(Color.secondary.opacity(0.25))
            .frame(width: 1, height: 14)
            .padding(.horizontal, 3)
    }

    private func noteFooter(taskID: UUID) -> some View {
        HStack(spacing: 8) {
            Text("⇧↵ newline  ·  ↵ send")
                .font(.caption2)
                .foregroundStyle(.tertiary)
            Spacer()
            if editingNoteID != nil {
                Button("Cancel") { cancelEdit() }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .font(.callout)
            }
            Button(editingNoteID != nil ? "Save" : "Add") {
                submitNote(taskID: taskID)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .disabled(newNoteText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
    }

    // MARK: - Actions

    private func startEditing(note: TaskNote) {
        editingNoteID = note.id
        newNoteText = note.content
        editorRef.focus()
    }

    private func cancelEdit() {
        editingNoteID = nil
        newNoteText = ""
    }

    private func submitNote(taskID: UUID) {
        let trimmed = newNoteText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if let noteID = editingNoteID {
            taskStore.updateNote(taskID: taskID, noteID: noteID, content: trimmed)
            editingNoteID = nil
        } else {
            taskStore.addNote(to: taskID, content: trimmed)
        }
        newNoteText = ""
    }
}
