import Foundation

enum MockData {

    // MARK: - Activities

    static func activities(agentID: UUID, count: Int = 8) -> [Activity] {
        let base = Date.now.addingTimeInterval(-Double(count) * 180)
        let sequence: [(AgentStatus, String?, TimeInterval)] = [
            (.thinking,       "Reading project files",          120),
            (.runningCommand, "swift build",                    180),
            (.thinking,       "Analyzing build errors",         90),
            (.runningCommand, "swift build",                    240),
            (.thinking,       "Writing fix for AuthService",    300),
            (.runningCommand, "swift test",                     210),
            (.thinking,       "Reviewing test results",         60),
            (.runningCommand, "git commit -m 'fix: auth'",      30),
        ]
        var result: [Activity] = []
        var cursor = base
        for (index, (status, task, dur)) in sequence.prefix(count).enumerated() {
            let isLast = index == sequence.prefix(count).count - 1
            let activity = Activity(
                agentID: agentID,
                status: status,
                task: task,
                workflowPhase: .coding,
                timestamp: cursor,
                duration: isLast ? nil : dur
            )
            result.append(activity)
            cursor = cursor.addingTimeInterval(dur)
        }
        return result
    }

    // MARK: - Agents

    static func agent(
        projectID: UUID,
        type: AgentType = .claudeCode,
        status: AgentStatus,
        task: String? = nil,
        branch: String? = "main",
        workflowPhase: WorkflowPhase? = .coding,
        progress: Double? = nil,
        minutesAgo: Double = 5
    ) -> Agent {
        let id = UUID()
        let updatedAt = Date.now.addingTimeInterval(-minutesAgo * 60)
        var agent = Agent(
            id: id,
            projectID: projectID,
            agentType: type,
            status: status,
            currentTask: task,
            workflowPhase: workflowPhase,
            progress: progress,
            branch: branch,
            startedAt: Date.now.addingTimeInterval(-40 * 60),
            updatedAt: updatedAt,
            activities: []
        )
        for activity in activities(agentID: id) {
            agent.appendActivity(activity)
        }
        return agent
    }

    // MARK: - Projects

    static let projects: [Project] = [
        project(
            name: "Clinic System",
            status: .waitingUser,
            task: "Permission required: write to package.json",
            branch: "feature/auth-jwt",
            workflowPhase: .coding,
            progress: 0.65,
            minutesAgo: 3.4
        ),
        project(
            name: "Flutter App",
            status: .thinking,
            task: "Refactoring AuthService to use JWT",
            branch: "feature/auth-refactor",
            workflowPhase: .coding,
            progress: 0.45,
            minutesAgo: 0.75
        ),
        project(
            name: "AWS Infrastructure",
            agentType: .cursor,
            status: .runningCommand,
            task: "terraform apply -var-file=prod.tfvars",
            branch: "infra/vpc-setup",
            workflowPhase: .deploying,
            minutesAgo: 1.2
        ),
        project(
            name: "CMS",
            status: .idle,
            task: nil,
            branch: "main",
            workflowPhase: nil,
            minutesAgo: 42
        ),
        project(
            name: "AI Framework",
            agentType: .cursor,
            status: .error,
            task: "Build failed: Cannot find type 'LLMService'",
            branch: "dev",
            workflowPhase: .coding,
            minutesAgo: 8.05
        ),
    ]

    static func project(
        name: String,
        agentType: AgentType = .claudeCode,
        status: AgentStatus,
        task: String? = nil,
        branch: String? = "main",
        workflowPhase: WorkflowPhase? = nil,
        progress: Double? = nil,
        minutesAgo: Double = 5
    ) -> Project {
        let projectID = UUID()
        let root = URL(filePath: "/Users/demo/projects/\(name.lowercased().replacingOccurrences(of: " ", with: "-"))")
        let agent = MockData.agent(
            projectID: projectID,
            type: agentType,
            status: status,
            task: task,
            branch: branch,
            workflowPhase: workflowPhase,
            progress: progress,
            minutesAgo: minutesAgo
        )
        return Project(
            id: projectID,
            name: name,
            rootURL: root,
            agents: [agent],
            gitStatus: mockGitStatus(branch: branch),
            isGitRepository: true,
            discoveredAt: Date.now.addingTimeInterval(-3600),
            lastSeenAt: Date.now.addingTimeInterval(-minutesAgo * 60),
            isReachable: true
        )
    }

    // MARK: - Convenience factory

    static func project(status: AgentStatus) -> Project {
        let name: String
        let task: String?
        switch status {
        case .idle:          name = "Idle Project";    task = nil
        case .thinking:      name = "Thinking Project"; task = "Analyzing codebase"
        case .runningCommand: name = "Running Project";  task = "swift build"
        case .waitingUser:   name = "Waiting Project";  task = "Permission required"
        case .completed:     name = "Done Project";     task = "All tests passed"
        case .error:         name = "Error Project";    task = "Compilation failed"
        }
        return project(name: name, status: status, task: task)
    }

    // MARK: - Settings

    static let settings = Settings(
        watchedRootURLs: [URL(filePath: "/Users/demo/projects")],
        scanDepth: 3
    )

    // MARK: - GitStatus

    static func mockGitStatus(branch: String?) -> GitStatus {
        GitStatus(
            branch: branch ?? "main",
            isDetachedHEAD: false,
            aheadCount: 2,
            behindCount: 0,
            stagedCount: 3,
            unstagedCount: 1,
            untrackedCount: 0,
            hasConflicts: false,
            lastFetchedAt: Date.now.addingTimeInterval(-120),
            stashCount: 0
        )
    }
}
