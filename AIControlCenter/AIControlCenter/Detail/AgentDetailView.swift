import SwiftUI

struct AgentDetailView: View {
    let project: Project

    @Environment(AppState.self) private var appState
    @State private var viewModel: AgentDetailViewModel
    @State private var terminalService = TerminalService()

    init(project: Project) {
        self.project = project
        self._viewModel = State(initialValue: AgentDetailViewModel(project: project))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                headerSection
                Divider().padding(.vertical, 12)
                progressSection
                Divider().padding(.vertical, 12)
                activitySection
            }
            .padding(16)
        }
        .onChange(of: project) { _, newProject in
            viewModel.update(with: newProject)
        }
        .navigationTitle(project.name)
        .navigationSubtitle(viewModel.agent?.agentType.displayName ?? "")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    Task { await openInTerminal() }
                } label: {
                    Label("Open in Terminal", systemImage: "terminal")
                }
                .help("Open project directory in terminal")
            }
        }
    }

    private func openInTerminal() async {
        do {
            let banner = try await terminalService.open(
                workingDirectory: project.rootURL,
                providerType: appState.settings.preferredTerminal
            )
            if let banner {
                appState.pendingBanners.append(banner)
            }
        } catch {
            let banner = BannerMessage(
                message: "Could not open terminal: \(error.localizedDescription)",
                level: .error,
                autoDismissAfter: 8
            )
            appState.pendingBanners.append(banner)
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        HStack(alignment: .top, spacing: 12) {
            if let agent = viewModel.agent {
                Image(systemName: agent.agentType.iconSystemName)
                    .font(.system(size: 32))
                    .foregroundStyle(viewModel.aggregatedStatus.color)
                    .frame(width: 44, height: 44)
                    .background(viewModel.aggregatedStatus.color.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(project.name)
                    .font(.title2.bold())
                    .lineLimit(1)

                HStack(spacing: 8) {
                    StatusBadgeView(status: viewModel.aggregatedStatus)
                    if let branch = viewModel.branch {
                        Label(branch, systemImage: "arrow.branch")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fontDesign(.monospaced)
                    }
                }

                if let task = viewModel.currentTask {
                    Text(task)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .padding(.top, 2)
                }
            }

            Spacer()

            if let updatedAt = viewModel.updatedAt {
                VStack(alignment: .trailing, spacing: 2) {
                    Text("Last updated")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    ElapsedTimeView(since: updatedAt)
                        .font(.caption)
                }
            }
        }
    }

    // MARK: - Progress

    @ViewBuilder
    private var progressSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Progress", systemImage: "chart.bar.fill")
                .font(.caption.bold())
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            HStack(spacing: 16) {
                if let phase = viewModel.workflowPhase {
                    phaseIndicator(phase)
                }

                if let progress = viewModel.progress {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Completion")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text("\(Int(progress * 100))%")
                                .font(.caption.bold())
                                .monospacedDigit()
                        }
                        ProgressView(value: progress)
                            .tint(viewModel.aggregatedStatus.color)
                    }
                    .frame(maxWidth: .infinity)
                }
            }

            if viewModel.workflowPhase == nil && viewModel.progress == nil {
                Text("No progress data available")
                    .font(.callout)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private func phaseIndicator(_ phase: WorkflowPhase) -> some View {
        HStack(spacing: 6) {
            ForEach(WorkflowPhase.allCases, id: \.self) { p in
                VStack(spacing: 4) {
                    Circle()
                        .fill(p.ordinal <= phase.ordinal
                              ? viewModel.aggregatedStatus.color
                              : Color.secondary.opacity(0.2))
                        .frame(width: 8, height: 8)
                    if p == phase {
                        Image(systemName: p.iconSystemName)
                            .font(.system(size: 9))
                            .foregroundStyle(viewModel.aggregatedStatus.color)
                    }
                }
            }
        }
    }

    // MARK: - Activity History

    private var activitySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Activity History", systemImage: "clock.arrow.circlepath")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                Spacer()
                Text("\(viewModel.agent?.activities.count ?? 0) events")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            if viewModel.hasActivities {
                LazyVStack(spacing: 0) {
                    ForEach(viewModel.reversedActivities) { activity in
                        ActivityRowView(activity: activity)
                            .id(activity.id)
                    }
                }
            } else {
                Text("No activity recorded yet")
                    .font(.callout)
                    .foregroundStyle(.tertiary)
                    .padding(.vertical, 8)
            }
        }
    }
}

#Preview("Agent Detail — Waiting") {
    let project = MockData.project(
        name: "Clinic System",
        agentType: .claudeCode,
        status: .waitingUser,
        task: "Approve database schema changes before migration",
        branch: "feat/patient-records",
        workflowPhase: .review,
        progress: 0.65,
        minutesAgo: 5
    )
    NavigationStack {
        AgentDetailView(project: project)
    }
    .environment(AppState())
    .frame(width: 480, height: 600)
}

#Preview("Agent Detail — Running") {
    let project = MockData.project(
        name: "AWS Infrastructure",
        agentType: .claudeCode,
        status: .runningCommand,
        task: "terraform apply --target=module.vpc",
        branch: "infra/vpc-update",
        workflowPhase: .deploying,
        progress: 0.82,
        minutesAgo: 12
    )
    NavigationStack {
        AgentDetailView(project: project)
    }
    .environment(AppState())
    .frame(width: 480, height: 600)
}

#Preview("Agent Detail — Error") {
    let project = MockData.project(status: .error)
    NavigationStack {
        AgentDetailView(project: project)
    }
    .environment(AppState())
    .frame(width: 480, height: 600)
}

#Preview("Agent Detail — Dark") {
    let project = MockData.projects[0]
    NavigationStack {
        AgentDetailView(project: project)
    }
    .frame(width: 480, height: 600)
    .preferredColorScheme(.dark)
}
