import Foundation
import Observation

// MARK: - Display Item

enum DashboardItem: Identifiable, Sendable {
    case solo(Project)
    case group(id: UUID, name: String, projects: [Project], isExpanded: Bool)

    var id: UUID {
        switch self {
        case .solo(let p): p.id
        case .group(let id, _, _, _): id
        }
    }
}

// MARK: - Layout Model

struct DashboardLayout: Codable, Sendable, Equatable {
    var entries: [Entry] = []

    var allProjectIDs: Set<UUID> {
        Set(entries.flatMap(\.projectIDs))
    }

    mutating func appendNewProjects(_ ids: [UUID]) {
        let known = allProjectIDs
        for id in ids where !known.contains(id) {
            entries.append(.solo(id))
        }
    }

    enum Entry: Sendable, Equatable, Identifiable {
        case solo(UUID)
        case group(GroupData)

        var id: UUID {
            switch self {
            case .solo(let id): id
            case .group(let g): g.id
            }
        }

        var projectIDs: [UUID] {
            switch self {
            case .solo(let id): [id]
            case .group(let g): g.projectIDs
            }
        }

        var isGroup: Bool {
            if case .group = self { return true }
            return false
        }
    }

    struct GroupData: Codable, Sendable, Equatable, Identifiable {
        let id: UUID
        var name: String
        var projectIDs: [UUID]
        var isExpanded: Bool = true
    }
}

extension DashboardLayout.Entry: Codable {
    private enum CodingKeys: String, CodingKey { case type, id, group }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let type = (try? c.decode(String.self, forKey: .type)) ?? "solo"
        if type == "group" {
            self = .group(try c.decode(DashboardLayout.GroupData.self, forKey: .group))
        } else {
            self = .solo(try c.decode(UUID.self, forKey: .id))
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .solo(let id):
            try c.encode("solo", forKey: .type)
            try c.encode(id, forKey: .id)
        case .group(let g):
            try c.encode("group", forKey: .type)
            try c.encode(g, forKey: .group)
        }
    }
}

// MARK: - Memo Persistence

enum MemoStore {
    private static let key = "projectMemos_v1"

    static func load() -> [UUID: String] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let raw = try? JSONDecoder().decode([String: String].self, from: data)
        else { return [:] }
        return Dictionary(uniqueKeysWithValues: raw.compactMap { k, v in
            UUID(uuidString: k).map { ($0, v) }
        })
    }

    static func save(_ memos: [UUID: String]) {
        let raw = Dictionary(uniqueKeysWithValues: memos.map { ($0.key.uuidString, $0.value) })
        if let data = try? JSONEncoder().encode(raw) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}

// MARK: - Layout Persistence

enum DashboardLayoutStore {
    private static let key = "dashboardLayout_v1"

    static func load() -> DashboardLayout {
        guard let data = UserDefaults.standard.data(forKey: key),
              let layout = try? JSONDecoder().decode(DashboardLayout.self, from: data)
        else { return DashboardLayout() }
        return layout
    }

    static func save(_ layout: DashboardLayout) {
        if let data = try? JSONEncoder().encode(layout) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}

// MARK: - ViewModel

@Observable
@MainActor
final class DashboardViewModel {

    // MARK: - State

    var projects: [Project] = []
    var sortOrder: SortOrder
    var filterGroup: StatusGroup = .all
    var searchText: String = ""
    var selectedProjectID: UUID?
    var layout: DashboardLayout
    var memos: [UUID: String]
    var expandedMemoIDs: Set<UUID> = []
    var tasksVisible: Bool = true
    var taskScopeFilter: TaskScopeFilter = .all
    var isAddTaskPresented: Bool = false
    var addTaskDefaultScope: TaskScope? = nil

    init() {
        let savedLayout = DashboardLayoutStore.load()
        self.layout = savedLayout
        self.memos = MemoStore.load()
        // Restore custom sort when the saved layout has user-arranged groups.
        // Without this, sortOrder resets to .statusPriority on every relaunch
        // and groups become invisible even though they're still on disk.
        let hasGroups = savedLayout.entries.contains(where: \.isGroup)
        self.sortOrder = hasGroups ? .custom : .statusPriority
    }

    // MARK: - Layout Sync

    func syncLayout() {
        layout.appendNewProjects(projects.map(\.id))
        DashboardLayoutStore.save(layout)
    }

    // MARK: - Computed

    private var filteredProjects: [Project] {
        guard filterGroup != .all else { return projects }
        return projects.filter { filterGroup.statuses.contains($0.aggregatedStatus) }
    }

    private var sortedProjects: [Project] {
        filteredProjects.sorted(by: sortOrder.comparator)
    }

    private var flatDisplayedProjects: [Project] {
        guard !searchText.isEmpty else { return sortedProjects }
        let q = searchText.lowercased()
        return sortedProjects.filter { matchesSearch($0, query: q) }
    }

    private func matchesSearch(_ project: Project, query: String) -> Bool {
        project.name.lowercased().contains(query)
        || project.primaryAgent?.currentTask?.lowercased().contains(query) == true
        || project.primaryAgent?.branch?.lowercased().contains(query) == true
        || project.primaryAgent?.agentType.displayName.lowercased().contains(query) == true
    }

    var displayedItems: [DashboardItem] {
        if sortOrder != .custom {
            return flatDisplayedProjects.map { .solo($0) }
        }

        let projectMap = Dictionary(uniqueKeysWithValues: projects.map { ($0.id, $0) })
        let query = searchText.isEmpty ? nil : searchText.lowercased()

        var items: [DashboardItem] = []

        for entry in layout.entries {
            switch entry {
            case .solo(let id):
                guard let p = projectMap[id] else { continue }
                guard filterGroup == .all || filterGroup.statuses.contains(p.aggregatedStatus) else { continue }
                if let q = query, !matchesSearch(p, query: q) { continue }
                items.append(.solo(p))

            case .group(let g):
                var children = g.projectIDs.compactMap { projectMap[$0] }
                children = children.filter { filterGroup == .all || filterGroup.statuses.contains($0.aggregatedStatus) }
                if let q = query { children = children.filter { matchesSearch($0, query: q) } }
                guard !children.isEmpty else { continue }
                items.append(.group(id: g.id, name: g.name, projects: children, isExpanded: g.isExpanded))
            }
        }

        // Projects not yet in layout (newly discovered)
        let layoutIDs = layout.allProjectIDs
        for p in projects where !layoutIDs.contains(p.id) {
            guard filterGroup == .all || filterGroup.statuses.contains(p.aggregatedStatus) else { continue }
            if let q = query, !matchesSearch(p, query: q) { continue }
            items.append(.solo(p))
        }

        return items
    }

    var displayedProjects: [Project] { flatDisplayedProjects }

    var hasResults: Bool { !displayedItems.isEmpty }

    // MARK: - Sort Order

    enum SortOrder: String, CaseIterable, Sendable {
        case custom = "Custom Order"
        case statusPriority = "Status Priority"
        case name = "Project Name"
        case lastUpdated = "Last Updated"
        case elapsed = "Elapsed Time"

        var comparator: (Project, Project) -> Bool {
            switch self {
            case .custom, .statusPriority:
                { $0.aggregatedStatus.priority > $1.aggregatedStatus.priority }
            case .name:
                { $0.name.localizedCompare($1.name) == .orderedAscending }
            case .lastUpdated:
                { ($0.primaryAgent?.updatedAt ?? .distantPast) > ($1.primaryAgent?.updatedAt ?? .distantPast) }
            case .elapsed:
                { ($0.primaryAgent?.elapsedSinceLastChange ?? 0) > ($1.primaryAgent?.elapsedSinceLastChange ?? 0) }
            }
        }
    }

    // MARK: - Reorder / Group Operations

    func moveEntry(id: UUID, before targetID: UUID) {
        guard id != targetID, let entry = popEntry(id: id) else { return }
        if let idx = layout.entries.firstIndex(where: { $0.id == targetID }) {
            layout.entries.insert(entry, at: idx)
        } else {
            layout.entries.append(entry)
        }
        sortOrder = .custom
        DashboardLayoutStore.save(layout)
    }

    func moveEntry(id: UUID, after targetID: UUID) {
        guard id != targetID, let entry = popEntry(id: id) else { return }
        if let idx = layout.entries.firstIndex(where: { $0.id == targetID }) {
            layout.entries.insert(entry, at: min(idx + 1, layout.entries.count))
        } else {
            layout.entries.append(entry)
        }
        sortOrder = .custom
        DashboardLayoutStore.save(layout)
    }

    func moveEntryToFront(id: UUID) {
        guard let entry = popEntry(id: id) else { return }
        layout.entries.insert(entry, at: 0)
        sortOrder = .custom
        DashboardLayoutStore.save(layout)
    }

    func groupWith(draggingID: UUID, targetID: UUID) {
        guard draggingID != targetID else { return }
        guard let entry = popEntry(id: draggingID) else { return }
        // Groups can't be nested — if a group is dropped onto a row, treat as insert-after
        guard case .solo = entry else {
            if let idx = layout.entries.firstIndex(where: { $0.id == targetID }) {
                layout.entries.insert(entry, at: min(idx + 1, layout.entries.count))
            } else {
                layout.entries.append(entry)
            }
            sortOrder = .custom
            DashboardLayoutStore.save(layout)
            return
        }

        if let idx = layout.entries.firstIndex(where: { $0.id == targetID }) {
            // Target is a top-level entry (solo or group header)
            switch layout.entries[idx] {
            case .solo(let existingID):
                layout.entries[idx] = .group(.init(id: UUID(), name: "Group", projectIDs: [existingID, draggingID]))
            case .group(var g):
                if !g.projectIDs.contains(draggingID) { g.projectIDs.append(draggingID) }
                layout.entries[idx] = .group(g)
            }
        } else if let groupIdx = layout.entries.firstIndex(where: {
            // Target is a member inside an existing group — add draggingID to that group
            guard case .group(let g) = $0 else { return false }
            return g.projectIDs.contains(targetID)
        }) {
            if case .group(var g) = layout.entries[groupIdx] {
                if !g.projectIDs.contains(draggingID) { g.projectIDs.append(draggingID) }
                layout.entries[groupIdx] = .group(g)
            }
        } else {
            layout.entries.append(entry)
        }

        sortOrder = .custom
        DashboardLayoutStore.save(layout)
    }

    func toggleGroupExpanded(id: UUID) {
        guard let idx = layout.entries.firstIndex(where: { $0.id == id }),
              case .group(var g) = layout.entries[idx]
        else { return }
        g.isExpanded.toggle()
        layout.entries[idx] = .group(g)
        DashboardLayoutStore.save(layout)
    }

    func renameGroup(id: UUID, name: String) {
        guard let idx = layout.entries.firstIndex(where: { $0.id == id }),
              case .group(var g) = layout.entries[idx]
        else { return }
        g.name = name
        layout.entries[idx] = .group(g)
        DashboardLayoutStore.save(layout)
    }

    func ungroupProject(_ projectID: UUID, fromGroupID: UUID) {
        guard let groupIdx = layout.entries.firstIndex(where: { $0.id == fromGroupID }),
              case .group(var g) = layout.entries[groupIdx]
        else { return }
        g.projectIDs.removeAll { $0 == projectID }
        if g.projectIDs.isEmpty {
            layout.entries.remove(at: groupIdx)
        } else {
            layout.entries[groupIdx] = .group(g)
        }
        layout.entries.insert(.solo(projectID), at: min(groupIdx + 1, layout.entries.count))
        DashboardLayoutStore.save(layout)
    }

    // MARK: - Memo Operations

    func toggleMemo(id: UUID) {
        if expandedMemoIDs.contains(id) {
            expandedMemoIDs.remove(id)
        } else {
            expandedMemoIDs.insert(id)
        }
    }

    func setMemo(id: UUID, text: String) {
        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            memos.removeValue(forKey: id)
        } else {
            memos[id] = text
        }
        MemoStore.save(memos)
    }

    func dissolveGroup(id: UUID) {
        guard let idx = layout.entries.firstIndex(where: { $0.id == id }),
              case .group(let g) = layout.entries[idx]
        else { return }
        layout.entries.remove(at: idx)
        layout.entries.insert(contentsOf: g.projectIDs.map { .solo($0) }, at: idx)
        DashboardLayoutStore.save(layout)
    }

    // Removes and returns the entry for the given ID (from top-level or inside a group)
    @discardableResult
    private func popEntry(id: UUID) -> DashboardLayout.Entry? {
        if let idx = layout.entries.firstIndex(where: { $0.id == id }) {
            defer { layout.entries.remove(at: idx) }
            return layout.entries[idx]
        }
        for idx in layout.entries.indices {
            if case .group(var g) = layout.entries[idx], g.projectIDs.contains(id) {
                g.projectIDs.removeAll { $0 == id }
                if g.projectIDs.isEmpty {
                    layout.entries.remove(at: idx)
                } else {
                    layout.entries[idx] = .group(g)
                }
                return .solo(id)
            }
        }
        return nil
    }

    // MARK: - Selection

    func selectProject(_ project: Project) {
        selectedProjectID = project.id
    }

    var selectedProject: Project? {
        guard let id = selectedProjectID else { return nil }
        return projects.first { $0.id == id }
    }

    // MARK: - Flat Rows (LazyVStack rendering)

    enum FlatRow: Identifiable, Sendable {
        case solo(Project)
        case groupHeader(id: UUID, name: String, projects: [Project], isExpanded: Bool)
        case grouped(Project, groupID: UUID, isLast: Bool)
        // Always present for every visible project; isExpanded drives the height animation.
        case memoArea(projectID: UUID, groupID: UUID?, isLastInGroup: Bool, isExpanded: Bool)

        var id: String {
            switch self {
            case .solo(let p): p.id.uuidString
            case .groupHeader(let id, _, _, _): "gh_\(id)"
            case .grouped(let p, _, _): "gc_\(p.id)"
            case .memoArea(let projectID, _, _, _): "memo_\(projectID)"
            }
        }
    }

    var flatRows: [FlatRow] {
        var rows: [FlatRow] = []
        for item in displayedItems {
            switch item {
            case .solo(let p):
                rows.append(.solo(p))
                rows.append(.memoArea(projectID: p.id, groupID: nil, isLastInGroup: false, isExpanded: expandedMemoIDs.contains(p.id)))
            case .group(let id, let name, let projects, let isExpanded):
                rows.append(.groupHeader(id: id, name: name, projects: projects, isExpanded: isExpanded))
                if isExpanded {
                    for (i, p) in projects.enumerated() {
                        let isLast = i == projects.count - 1
                        rows.append(.grouped(p, groupID: id, isLast: isLast))
                        rows.append(.memoArea(projectID: p.id, groupID: id, isLastInGroup: isLast, isExpanded: expandedMemoIDs.contains(p.id)))
                    }
                }
            }
        }
        return rows
    }

    // MARK: - Mock (preview only)

    func loadMockData() {
        projects = MockData.projects
    }
}
