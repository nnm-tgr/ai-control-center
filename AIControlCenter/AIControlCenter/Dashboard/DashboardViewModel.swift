import Foundation
import Observation

@Observable
@MainActor
final class DashboardViewModel {

    // MARK: - State

    var projects: [Project] = []
    var sortOrder: SortOrder = .statusPriority
    var filterGroup: StatusGroup = .all
    var searchText: String = ""
    var selectedProjectID: UUID?

    // MARK: - Computed: フィルター → ソート → サーチの順に適用

    var filteredProjects: [Project] {
        guard filterGroup != .all else { return projects }
        return projects.filter { filterGroup.statuses.contains($0.aggregatedStatus) }
    }

    var sortedProjects: [Project] {
        filteredProjects.sorted(by: sortOrder.comparator)
    }

    /// UI に渡す最終リスト（フィルター + ソート + サーチ）
    var displayedProjects: [Project] {
        guard !searchText.isEmpty else { return sortedProjects }
        let query = searchText.lowercased()
        return sortedProjects.filter { project in
            project.name.lowercased().contains(query)
            || project.primaryAgent?.currentTask?.lowercased().contains(query) == true
            || project.primaryAgent?.branch?.lowercased().contains(query) == true
            || project.primaryAgent?.agentType.displayName.lowercased().contains(query) == true
        }
    }

    var hasResults: Bool { !displayedProjects.isEmpty }

    // MARK: - Sort

    enum SortOrder: String, CaseIterable, Sendable {
        case statusPriority = "Status Priority"
        case name = "Project Name"
        case lastUpdated = "Last Updated"
        case elapsed = "Elapsed Time"

        var comparator: (Project, Project) -> Bool {
            switch self {
            case .statusPriority:
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

    // MARK: - Actions

    func loadMockData() {
        projects = MockData.projects
    }

    func selectProject(_ project: Project) {
        selectedProjectID = project.id
    }

    func deselectProject() {
        selectedProjectID = nil
    }

    var selectedProject: Project? {
        guard let id = selectedProjectID else { return nil }
        return projects.first { $0.id == id }
    }
}
