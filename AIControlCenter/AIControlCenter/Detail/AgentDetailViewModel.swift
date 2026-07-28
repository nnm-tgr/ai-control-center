import Foundation
import Observation

@Observable
@MainActor
final class AgentDetailViewModel {

    private(set) var project: Project

    init(project: Project) {
        self.project = project
    }

    func update(with project: Project) {
        self.project = project
    }

    // MARK: - Computed

    var agent: Agent? { project.primaryAgent }
    var aggregatedStatus: AgentStatus { project.aggregatedStatus }
    var currentTask: String? { agent?.currentTask }
    var branch: String? { agent?.branch }
    var workflowPhase: WorkflowPhase? { agent?.workflowPhase }
    var progress: Double? { agent?.progress }
    var needsAttention: Bool { agent?.needsAttention ?? false }
    var updatedAt: Date? { agent?.updatedAt }

    /// activities は oldest-first で格納。reversed() は O(1) — コピーなし
    var reversedActivities: ReversedCollection<[Activity]> {
        agent?.activities.reversed() ?? [Activity]().reversed()
    }

    var hasActivities: Bool { agent?.activities.isEmpty == false }
}
