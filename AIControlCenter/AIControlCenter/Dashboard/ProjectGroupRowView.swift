import SwiftUI

struct ProjectGroupRowView: View {
    let id: UUID
    let name: String
    let projects: [Project]
    let isExpanded: Bool
    let onToggle: () -> Void
    let onRename: (String) -> Void
    let onDissolve: () -> Void

    @State private var isEditing = false
    @State private var editingName = ""

    var body: some View {
        HStack(spacing: 0) {
            Button(action: onToggle) {
                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 18)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isEditing {
                TextField("Group name", text: $editingName)
                    .textFieldStyle(.plain)
                    .font(.body.weight(.medium))
                    .onSubmit { commitRename() }
                    .onExitCommand { isEditing = false }
            } else {
                Text(name)
                    .font(.body.weight(.medium))
                    .onTapGesture(count: 2) { beginEditing() }
            }

            Spacer()

            HStack(spacing: 3) {
                ForEach(statusSummary, id: \.self) { status in
                    Circle()
                        .fill(status.color)
                        .frame(width: 6, height: 6)
                }
            }

            Text("\(projects.count)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .padding(.leading, 4)
                .padding(.trailing, 12)
        }
        .frame(height: 34)
        .background(Color(nsColor: .controlBackgroundColor))
        .contextMenu {
            Button("Rename") { beginEditing() }
            Divider()
            Button("Ungroup All") { onDissolve() }
        }
    }

    private var statusSummary: [AgentStatus] {
        Array(Set(projects.map(\.aggregatedStatus)))
            .sorted { $0.priority > $1.priority }
            .prefix(4)
            .map { $0 }
    }

    private func beginEditing() {
        editingName = name
        isEditing = true
    }

    private func commitRename() {
        isEditing = false
        let trimmed = editingName.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty { onRename(trimmed) }
    }
}
