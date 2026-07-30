import SwiftUI

struct DashboardView: View {
    @Environment(AppState.self) private var appState
    @State private var viewModel = DashboardViewModel()
    @FocusState private var isSearchFocused: Bool

    var body: some View {
        ZStack(alignment: .bottom) {
            NavigationSplitView {
                listContent
                    .navigationSplitViewColumnWidth(min: 600, ideal: 780)
            } detail: {
                detailContent
            }
            .navigationTitle("AI Control Center")
            .toolbar { toolbarItems }
            .onAppear { syncProjects() }
            .onChange(of: appState.projects) { _, _ in syncProjects() }
            .onChange(of: appState.settings.watchedRootURLs) { _, _ in syncProjects() }

            ApprovalOverlayView()
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

            if viewModel.flatRows.isEmpty {
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
            Text("").frame(width: 18)
            Text("PROJECT").frame(width: 160, alignment: .leading)
            Text("AGENT").frame(width: 110, alignment: .leading)
            Text("STATUS").frame(width: 90, alignment: .leading)
            Text("ELAPSED").frame(width: 70, alignment: .leading)
            Text("BRANCH").frame(width: 110, alignment: .leading)
            Text("CURRENT TASK").frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: - Project List (Drag & Drop)

    private var projectList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                // Drop zone before first item
                DropInsertZone { id in viewModel.moveEntryToFront(id: id) }

                ForEach(viewModel.flatRows) { row in
                    rowView(for: row)
                    Divider()
                    // Insert zone appears only at top-level boundaries
                    if let afterID = insertZoneAfterID(for: row) {
                        DropInsertZone { id in viewModel.moveEntry(id: id, after: afterID) }
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
    }

    // MARK: - Row View (1 FlatRow = 1 View)

    @ViewBuilder
    private func rowView(for row: DashboardViewModel.FlatRow) -> some View {
        switch row {
        case .solo(let project):
            soloRow(project)

        case .groupHeader(let id, let name, let projects, let isExpanded):
            ProjectGroupRowView(
                id: id,
                name: name,
                projects: projects,
                isExpanded: isExpanded,
                onToggle: { viewModel.toggleGroupExpanded(id: id) },
                onRename: { viewModel.renameGroup(id: id, name: $0) },
                onDissolve: { viewModel.dissolveGroup(id: id) }
            )
            .draggable(id.uuidString) {
                groupDragPreview(name: name, count: projects.count)
            }
            .modifier(GroupDropTarget(itemID: id) { draggedID in
                viewModel.groupWith(draggingID: draggedID, targetID: id)
            })

        case .grouped(let project, let groupID, _):
            soloRow(project, indent: 20, groupID: groupID)

        case .memoArea(let projectID, _, _, let isExpanded):
            MemoAreaView(
                text: Binding(
                    get: { viewModel.memos[projectID] ?? "" },
                    set: { viewModel.setMemo(id: projectID, text: $0) }
                ),
                isExpanded: isExpanded
            )
        }
    }

    // .memoArea is always present for every project row, so it is the sole provider of insert zones
    // for solo and grouped rows. .solo and .grouped always return nil here.
    private func insertZoneAfterID(for row: DashboardViewModel.FlatRow) -> UUID? {
        switch row {
        case .solo:
            return nil
        case .groupHeader(let id, _, _, let isExpanded):
            return isExpanded ? nil : id
        case .grouped:
            return nil
        case .memoArea(let projectID, let groupID, let isLastInGroup, _):
            if let gid = groupID { return isLastInGroup ? gid : nil }
            return projectID
        }
    }

    // MARK: - Solo Row

    private func soloRow(_ project: Project, indent: CGFloat = 0, groupID: UUID? = nil) -> some View {
        AgentRowView(
            project: project,
            isSelected: viewModel.selectedProjectID == project.id,
            indent: indent,
            hasMemo: !(viewModel.memos[project.id]?.isEmpty ?? true),
            isMemoOpen: viewModel.expandedMemoIDs.contains(project.id),
            onMemoToggle: { viewModel.toggleMemo(id: project.id) }
        )
            .draggable(project.id.uuidString) {
                dragPreview(name: project.name, status: project.aggregatedStatus)
            }
            .modifier(GroupDropTarget(itemID: project.id) { draggedID in
                viewModel.groupWith(draggingID: draggedID, targetID: project.id)
            })
            .onTapGesture { viewModel.selectProject(project) }
            .contextMenu { soloContextMenu(project: project, groupID: groupID) }
    }

    private func groupDragPreview(name: String, count: Int) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "folder").foregroundStyle(.secondary).font(.callout)
            Text(name).font(.body)
            Text("(\(count))").foregroundStyle(.secondary).font(.callout)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 6))
    }

    private func dragPreview(name: String, status: AgentStatus) -> some View {
        HStack(spacing: 6) {
            Circle().fill(status.color).frame(width: 8, height: 8)
            Text(name).font(.body)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 6))
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
            SettingsLink { Text("Open Settings") }
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
            Text("AI Control Center").font(.headline)
        }
        ToolbarItem(placement: .primaryAction) { filterMenu }
        ToolbarItem(placement: .primaryAction) { sortMenu }
        ToolbarItem(placement: .primaryAction) {
            SettingsLink { Image(systemName: "gear") }
                .help("Settings (⌘,)")
        }
    }

    private var filterMenu: some View {
        Menu {
            Picker("Filter", selection: $viewModel.filterGroup) {
                ForEach(StatusGroup.allCases, id: \.self) { Text($0.rawValue).tag($0) }
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
                ForEach(DashboardViewModel.SortOrder.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.inline)
        } label: {
            Label("Sort", systemImage: "arrow.up.arrow.down")
        }
        .help("Sort order")
    }

    // MARK: - Context Menus

    @ViewBuilder
    private func soloContextMenu(project: Project, groupID: UUID?) -> some View {
        Button("Show Detail") { viewModel.selectProject(project) }
        Divider()
        if let gid = groupID {
            Button("Remove from Group") { viewModel.ungroupProject(project.id, fromGroupID: gid) }
            Divider()
        }
        Button("Copy Project Path") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(project.rootURL.path, forType: .string)
        }
        Button("Open in Finder") { NSWorkspace.shared.open(project.rootURL) }
        Button("Open .ai/ Folder") {
            NSWorkspace.shared.open(project.rootURL.appending(component: ".ai"))
        }
    }

    // MARK: - Data Sync

    private func syncProjects() {
        viewModel.projects = appState.projects
        viewModel.syncLayout()
    }
}

// MARK: - Memo Area

private struct MemoAreaView: View {
    @Binding var text: String
    let isExpanded: Bool

    var body: some View {
        VStack(spacing: 0) {
            if isExpanded {
                TextField("引き継ぎメモ、残タスク、次の作業など...", text: $text, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.callout)
                    .lineLimit(3...8)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color(nsColor: .controlBackgroundColor).opacity(0.7))
                    .transition(.opacity)
            }
        }
        .clipped()
        .animation(.spring(duration: 0.25), value: isExpanded)
    }
}

// MARK: - Drop Insert Zone

private struct DropInsertZone: View {
    let onInsert: (UUID) -> Void
    @State private var isTargeted = false

    var body: some View {
        Rectangle()
            .fill(isTargeted ? Color.accentColor : Color.clear)
            .frame(height: isTargeted ? 3 : 2)
            .animation(.easeInOut(duration: 0.1), value: isTargeted)
            .dropDestination(for: String.self) { strings, _ in
                guard let id = strings.first.flatMap({ UUID(uuidString: $0) }) else { return false }
                onInsert(id)
                return true
            } isTargeted: { isTargeted = $0 }
    }
}

// MARK: - Group Drop Target Modifier

private struct GroupDropTarget: ViewModifier {
    let itemID: UUID
    let onGroup: (UUID) -> Void
    @State private var isTargeted = false

    func body(content: Content) -> some View {
        content
            .overlay {
                if isTargeted {
                    RoundedRectangle(cornerRadius: 3)
                        .stroke(Color.accentColor, lineWidth: 2)
                        .padding(1)
                }
            }
            .dropDestination(for: String.self) { strings, _ in
                guard let id = strings.first.flatMap({ UUID(uuidString: $0) }),
                      id != itemID else { return false }
                onGroup(id)
                return true
            } isTargeted: { isTargeted = $0 }
    }
}

// MARK: - Previews

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
