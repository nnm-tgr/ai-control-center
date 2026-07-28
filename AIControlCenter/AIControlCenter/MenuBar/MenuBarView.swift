import SwiftUI

struct MenuBarView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            projectList
            Divider()
            footer
        }
        .frame(width: 320)
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Label("AI Control Center", systemImage: "waveform.path.ecg")
                .font(.headline)
            Spacer()
            if appState.isScanning {
                ProgressView()
                    .scaleEffect(0.7)
            } else if appState.unreadCount > 0 {
                Text("\(appState.unreadCount)")
                    .font(.caption.bold())
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.red)
                    .clipShape(Capsule())
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    // MARK: - Project List

    @ViewBuilder
    private var projectList: some View {
        if appState.projects.isEmpty {
            Text("No projects found")
                .font(.callout)
                .foregroundStyle(.secondary)
                .padding()
        } else {
            let active = appState.projects
                .filter { $0.aggregatedStatus != .idle && $0.isReachable }
                .prefix(8)

            if active.isEmpty {
                Text("All agents idle")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding()
            } else {
                ForEach(active) { project in
                    MenuBarProjectRow(project: project)
                }
            }
        }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            Button("Open Dashboard") {
                NSApp.activate(ignoringOtherApps: true)
                NSApp.windows.first?.makeKeyAndOrderFront(nil)
            }
            .buttonStyle(.plain)
            .font(.callout)

            Spacer()

            Button("Refresh") {
                Task { await appState.refresh() }
            }
            .buttonStyle(.plain)
            .font(.callout)

            Button("Quit") {
                NSApp.terminate(nil)
            }
            .buttonStyle(.plain)
            .font(.callout)
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}

// MARK: - Project Row

private struct MenuBarProjectRow: View {
    let project: Project

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(project.aggregatedStatus.color)
                .frame(width: 7, height: 7)

            VStack(alignment: .leading, spacing: 1) {
                Text(project.name)
                    .font(.callout)
                    .lineLimit(1)
                if let task = project.primaryAgent?.currentTask {
                    Text(task)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            Text(project.aggregatedStatus.displayName)
                .font(.caption)
                .foregroundStyle(project.aggregatedStatus.color)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .onTapGesture {
            NSApp.activate(ignoringOtherApps: true)
            NSApp.windows.first?.makeKeyAndOrderFront(nil)
        }
    }
}

// MARK: - Menu Bar Icon Label

struct MenuBarIconLabel: View {
    @Environment(AppState.self) private var appState

    private var iconName: String {
        let statuses = appState.projects.map(\.aggregatedStatus)
        if statuses.contains(.error) { return "exclamationmark.triangle.fill" }
        if statuses.contains(.waitingUser) { return "person.fill.questionmark" }
        if statuses.contains(.runningCommand) || statuses.contains(.thinking) {
            return "waveform.path.ecg"
        }
        return "waveform.path.ecg"
    }

    var body: some View {
        Image(systemName: iconName)
    }
}

#Preview("MenuBar — Mock") {
    MenuBarView()
        .environment(previewAppState())
}

@MainActor
private func previewAppState() -> AppState {
    let state = AppState()
    // Mock projects を直接差し込む（テスト用）
    return state
}
