import SwiftUI

struct TaskDetailView: View {
    let taskID: UUID
    @Environment(AppState.self) private var appState
    @State private var showEdit = false
    @State private var newNoteText = ""
    @FocusState private var isNoteFieldFocused: Bool

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

            if task.progress > 0 || task.status == .inProgress {
                progressRow(task: task)
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

            addNoteField(taskID: task.id)
        }
    }

    private func noteRow(note: TaskNote, taskID: UUID) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(note.createdAt.formatted(date: .abbreviated, time: .shortened))
                .font(.caption2)
                .foregroundStyle(.tertiary)

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
        }
        .padding(10)
        .background(Color.secondary.opacity(0.07))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .contextMenu {
            Button("Delete Note", role: .destructive) {
                taskStore.deleteNote(taskID: taskID, noteID: note.id)
            }
        }
    }

    private func addNoteField(taskID: UUID) -> some View {
        HStack(alignment: .bottom, spacing: 8) {
            TextField("Add a note…", text: $newNoteText, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(2...6)
                .focused($isNoteFieldFocused)

            Button("Add") { submitNote(taskID: taskID) }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
                .disabled(newNoteText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }

    private func submitNote(taskID: UUID) {
        let trimmed = newNoteText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        taskStore.addNote(to: taskID, content: trimmed)
        newNoteText = ""
    }
}
