import SwiftUI

struct ApprovalOverlayView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        if let request = appState.pendingApprovals.first {
            ApprovalCardView(request: request)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .animation(.spring(duration: 0.3), value: appState.pendingApprovals.count)
                .padding(.bottom, 12)
                .padding(.horizontal, 12)
        }
    }
}

private struct ApprovalCardView: View {
    @Environment(AppState.self) private var appState
    let request: ToolApprovalRequest

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: toolIcon)
                .font(.title2)
                .foregroundStyle(.orange)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(request.projectName)
                        .font(.headline)
                    toolBadge
                }
                if let preview = request.commandPreview {
                    Text(preview)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }

            Spacer()

            countdown

            Button("拒否") { appState.deny(request) }
                .buttonStyle(.bordered)
                .keyboardShortcut(.escape, modifiers: [])

            Button("許可") { appState.approve(request) }
                .buttonStyle(.borderedProminent)
                .tint(.green)
                .keyboardShortcut(.return, modifiers: [])
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(.orange.opacity(0.4), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.15), radius: 12, y: 4)
    }

    private var toolIcon: String {
        switch request.tool.lowercased() {
        case "bash": return "terminal.fill"
        case "edit", "write", "multiedit": return "pencil.and.scribble"
        case "read": return "doc.text.fill"
        default: return "gearshape.fill"
        }
    }

    private var toolBadge: some View {
        Text(request.tool)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(.orange.opacity(0.15))
            .foregroundStyle(.orange)
            .clipShape(Capsule())
    }

    private var countdown: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let remaining = max(0, request.timeoutSeconds - Int(context.date.timeIntervalSince(request.requestedAt)))
            Text("\(remaining)s")
                .font(.caption.monospacedDigit())
                .foregroundStyle(remaining < 10 ? .orange : .secondary)
                .frame(width: 36)
        }
    }
}

#Preview("Approval Overlay") {
    let appState = AppState()
    return ZStack(alignment: .bottom) {
        Color(nsColor: .windowBackgroundColor)
        ApprovalOverlayView()
    }
    .environment(appState)
    .frame(width: 700, height: 200)
}
