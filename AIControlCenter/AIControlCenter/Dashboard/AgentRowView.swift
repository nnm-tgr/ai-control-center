import SwiftUI

struct AgentRowView: View {
    let project: Project
    let isSelected: Bool
    var indent: CGFloat = 0
    var hasMemo: Bool = false
    var isMemoOpen: Bool = false
    var onMemoToggle: (() -> Void)? = nil

    @State private var isHovered = false
    @State private var isMemoButtonHovered = false

    private var agent: Agent? { project.primaryAgent }

    var body: some View {
        HStack(spacing: 0) {
            if indent > 0 {
                Color.clear.frame(width: indent)
            }
            // Status dot
            Circle()
                .fill(project.aggregatedStatus.color)
                .frame(width: 8, height: 8)
                .padding(.trailing, 10)

            // Project name
            Text(project.name)
                .font(.body)
                .frame(width: 160, alignment: .leading)
                .lineLimit(1)

            // Agent type
            HStack(spacing: 4) {
                Image(systemName: agent?.agentType.iconSystemName ?? "questionmark.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(agent?.agentType.displayName ?? "—")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .frame(width: 110, alignment: .leading)

            // Status badge
            StatusBadgeView(status: project.aggregatedStatus)
                .frame(width: 90, alignment: .leading)

            // Elapsed time
            ElapsedTimeView(since: agent?.updatedAt)
                .frame(width: 70, alignment: .leading)

            // Branch
            Text(agent?.branch ?? "—")
                .font(.caption)
                .fontDesign(.monospaced)
                .foregroundStyle(.secondary)
                .frame(width: 110, alignment: .leading)
                .lineLimit(1)

            // Current task
            Text(agent?.currentTask ?? "—")
                .font(.body)
                .foregroundStyle(agent?.currentTask != nil ? .primary : .tertiary)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 12)
        .frame(height: 40)
        .background(rowBackground)
        .onHover { isHovered = $0 }
        .overlay(alignment: .trailing) { memoButton }
    }

    @ViewBuilder
    private var memoButton: some View {
        if let toggle = onMemoToggle {
            Button(action: toggle) {
                Image(systemName: "note.text")
                    .font(.caption)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(isMemoOpen ? Color.accentColor : Color.primary)
            }
            .buttonStyle(.plain)
            .padding(.trailing, 12)
            .onHover { isMemoButtonHovered = $0 }
            .opacity(isMemoButtonHovered || isMemoOpen || hasMemo || isHovered ? 1 : 0)
            .animation(.easeOut(duration: 0.1), value: isMemoButtonHovered || isHovered)
        }
    }

    @ViewBuilder
    private var rowBackground: some View {
        if isSelected {
            Color.accentColor.opacity(0.15)
        } else if isHovered {
            Color.primary.opacity(0.05)
        } else {
            Color.clear
        }
    }
}

#Preview("Agent Rows — All Statuses") {
    VStack(spacing: 0) {
        ForEach(MockData.projects) { project in
            AgentRowView(project: project, isSelected: project.aggregatedStatus == .waitingUser)
            Divider()
        }
    }
    .frame(width: 800)
}
