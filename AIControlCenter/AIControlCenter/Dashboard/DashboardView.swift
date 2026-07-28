import SwiftUI

struct DashboardView: View {
    @Environment(AppState.self) private var appState
    @State private var viewModel = DashboardViewModel()
    @FocusState private var isSearchFocused: Bool

    var body: some View {
        NavigationSplitView {
            listContent
                .navigationSplitViewColumnWidth(min: 600, ideal: 780)
        } detail: {
            detailContent
        }
        .navigationTitle("AI Control Center")
        .toolbar { toolbarItems }
        .onAppear {
            syncProjects()
        }
        .onChange(of: appState.projects) { _, newProjects in
            viewModel.projects = newProjects
        }
    }

    // MARK: - List

    @ViewBuilder
    private var listContent: some View {
        VStack(spacing: 0) {
            searchBar
            Divider()
            columnHeader
            Divider()

            if viewModel.displayedProjects.isEmpty {
                emptyState
            } else {
                projectList
            }
        }
    }

    private var searchBar: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .font(.callout)
            TextField("Search projects and tasks...", text: $viewModel.searchText)
                .textFieldStyle(.plain)
                .font(.body)
                .focused($isSearchFocused)
                .onSubmit { isSearchFocused = false }
            if !viewModel.searchText.isEmpty {
                Button {
                    viewModel.searchText = ""
                    isSearchFocused = false
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var columnHeader: some View {
        HStack(spacing: 0) {
            Text("")
                .frame(width: 18)   // status dot
            Text("PROJECT")
                .frame(width: 160, alignment: .leading)
            Text("AGENT")
                .frame(width: 110, alignment: .leading)
            Text("STATUS")
                .frame(width: 90, alignment: .leading)
            Text("ELAPSED")
                .frame(width: 70, alignment: .leading)
            Text("BRANCH")
                .frame(width: 110, alignment: .leading)
            Text("CURRENT TASK")
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var projectList: some View {
        List(viewModel.displayedProjects, selection: $viewModel.selectedProjectID) { project in
            AgentRowView(project: project, isSelected: viewModel.selectedProjectID == project.id)
                .listRowInsets(EdgeInsets())
                .listRowSeparator(.visible)
                .tag(project.id)
                .onTapGesture { viewModel.selectProject(project) }
                .contextMenu { contextMenu(for: project) }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }

    // MARK: - Empty States

    @ViewBuilder
    private var emptyState: some View {
        if viewModel.projects.isEmpty {
            noProjectsView
        } else {
            noSearchResultsView
        }
    }

    private var noProjectsView: some View {
        ContentUnavailableView {
            Label("No Projects Found", systemImage: "folder.badge.questionmark")
        } description: {
            Text("Add a root directory in Settings to get started.")
        } actions: {
            Button("Open Settings") {
                NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private var noSearchResultsView: some View {
        ContentUnavailableView.search(text: viewModel.searchText)
    }

    // MARK: - Detail

    @ViewBuilder
    private var detailContent: some View {
        if let project = viewModel.selectedProject {
            AgentDetailView(project: project)
        } else {
            ContentUnavailableView(
                "Select a Project",
                systemImage: "sidebar.right",
                description: Text("Choose a project from the list to see details.")
            )
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarItems: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            Text("AI Control Center")
                .font(.headline)
        }

        ToolbarItem(placement: .primaryAction) {
            filterMenu
        }

        ToolbarItem(placement: .primaryAction) {
            sortMenu
        }

        ToolbarItem(placement: .primaryAction) {
            Button {
                Task { await appState.refresh() }
            } label: {
                if appState.isScanning {
                    ProgressView().scaleEffect(0.7)
                } else {
                    Image(systemName: "arrow.clockwise")
                }
            }
            .help("Refresh (⌘R)")
            .keyboardShortcut("r", modifiers: .command)
            .disabled(appState.isScanning)
        }

        ToolbarItem(placement: .primaryAction) {
            Button {
                NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
            } label: {
                Image(systemName: "gear")
            }
            .help("Settings (⌘,)")
        }
    }

    private var filterMenu: some View {
        Menu {
            Picker("Filter", selection: $viewModel.filterGroup) {
                ForEach(StatusGroup.allCases, id: \.self) { group in
                    Text(group.rawValue).tag(group)
                }
            }
            .pickerStyle(.inline)
        } label: {
            Label("Filter", systemImage: "line.3.horizontal.decrease.circle")
        }
        .help("Filter by status")
    }

    private var sortMenu: some View {
        Menu {
            Picker("Sort", selection: $viewModel.sortOrder) {
                ForEach(DashboardViewModel.SortOrder.allCases, id: \.self) { order in
                    Text(order.rawValue).tag(order)
                }
            }
            .pickerStyle(.inline)
        } label: {
            Label("Sort", systemImage: "arrow.up.arrow.down")
        }
        .help("Sort order")
    }

    // MARK: - Data Sync

    private func syncProjects() {
        if appState.projects.isEmpty && appState.settings.watchedRootURLs.isEmpty {
            // 初回起動 / 未設定時は MockData でプレビュー
            viewModel.loadMockData()
        } else {
            viewModel.projects = appState.projects
        }
    }

    // MARK: - Context Menu

    @ViewBuilder
    private func contextMenu(for project: Project) -> some View {
        Button("Show Detail") { viewModel.selectProject(project) }
        Divider()
        Button("Copy Project Path") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(project.rootURL.path, forType: .string)
        }
        Button("Open in Finder") {
            NSWorkspace.shared.open(project.rootURL)
        }
        Button("Open .ai/ Folder") {
            NSWorkspace.shared.open(project.rootURL.appending(component: ".ai"))
        }
    }
}

#Preview("Dashboard — Mock Data") {
    DashboardView()
        .environment(AppState())
        .frame(width: 1000, height: 600)
}

#Preview("Dashboard — Dark Mode") {
    DashboardView()
        .environment(AppState())
        .frame(width: 1000, height: 600)
        .preferredColorScheme(.dark)
}
