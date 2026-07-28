import Foundation

/// agent-status.json を読み取り、既存 Agent を更新または新規作成する
struct StatusParserService: Sendable {

    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    // MARK: - Public

    /// ファイルを読み取り AgentStatusFile にパースする
    func parseFile(at url: URL) throws -> AgentStatusFile {
        let data = try Data(contentsOf: url)
        do {
            return try decoder.decode(AgentStatusFile.self, from: data)
        } catch {
            throw AppError.statusParsing(.decodingFailed(url: url, underlying: error.localizedDescription))
        }
    }

    /// AgentStatusFile から Agent を生成（既存 Agent がある場合は Activity を引き継ぐ）
    func makeAgent(
        from file: AgentStatusFile,
        projectID: UUID,
        existing: Agent? = nil
    ) -> Agent {
        let agentType = AgentType(rawString: file.agent)
        let status = AgentStatus(rawValue: file.status) ?? .idle
        let updatedAt = file.updatedAtDate

        var agent = Agent(
            id: existing?.id ?? UUID(),
            projectID: projectID,
            agentType: agentType,
            status: status,
            currentTask: file.task,
            workflowPhase: file.workflowPhase.flatMap { WorkflowPhase(rawValue: $0) },
            progress: file.progress,
            branch: file.branch,
            worktreePath: file.worktree.map { URL(fileURLWithPath: $0) },
            startedAt: file.startedAtDate,
            updatedAt: updatedAt,
            activities: existing?.activities ?? [],
            schemaVersion: file.schemaVersion
        )

        // ステータスが変化した場合のみ Activity を追記
        if existing?.status != status {
            let activity = Activity(
                agentID: agent.id,
                status: status,
                task: file.task,
                workflowPhase: file.workflowPhase.flatMap { WorkflowPhase(rawValue: $0) },
                timestamp: updatedAt
            )
            agent.appendActivity(activity)
        }

        return agent
    }

    /// URL から直接 Agent を生成するショートカット
    func loadAgent(
        at url: URL,
        projectID: UUID,
        existing: Agent? = nil
    ) throws -> Agent {
        let file = try parseFile(at: url)
        return makeAgent(from: file, projectID: projectID, existing: existing)
    }
}
