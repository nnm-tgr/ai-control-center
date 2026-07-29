import Foundation

/// .ai/pending.json を監視し、ツール実行の承認/拒否フローを管理するサービス
@Observable
@MainActor
final class ToolApprovalService {

    // MARK: - State

    private(set) var pendingApprovals: [ToolApprovalRequest] = []

    // MARK: - Private

    private var activeStream: AsyncFSEventStream?
    private var watchTask: Task<Void, Never>?

    // MARK: - Lifecycle

    func start(roots: [URL], excludedNames: Set<String> = Set(Settings.defaultExcludedNames)) {
        stop()
        let paths = roots.map(\.path)
        guard !paths.isEmpty else { return }

        let stream = AsyncFSEventStream(
            paths: paths,
            excludedPathSegments: excludedNames,
            targetFileNames: ["pending.json"]
        )
        activeStream = stream

        watchTask = Task { [weak self] in
            guard let self else { return }
            for await url in stream.urls {
                await self.handleEvent(at: url)
            }
        }
    }

    func stop() {
        watchTask?.cancel()
        watchTask = nil
        activeStream?.stop()
        activeStream = nil
    }

    // MARK: - Event Handling

    private func handleEvent(at url: URL) async {
        let projectRoot = url.deletingLastPathComponent().deletingLastPathComponent()
        let projectID = FileWatcherService.projectID(for: projectRoot)

        if FileManager.default.fileExists(atPath: url.path) {
            await loadPendingRequest(at: url, projectRoot: projectRoot, projectID: projectID)
        } else {
            // pending.json が消えた = タイムアウトによる自動クリア
            pendingApprovals.removeAll { $0.projectID == projectID }
        }
    }

    private func loadPendingRequest(at url: URL, projectRoot: URL, projectID: UUID) async {
        guard let data = try? Data(contentsOf: url) else { return }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let file = try? decoder.decode(ToolApprovalFile.self, from: data) else { return }

        // 同じセッション・同じプロジェクトの重複は無視
        if pendingApprovals.contains(where: { $0.sessionID == file.sessionID && $0.projectID == projectID }) {
            return
        }

        let request = ToolApprovalRequest(
            id: UUID(),
            projectID: projectID,
            projectName: projectRoot.lastPathComponent,
            sessionID: file.sessionID,
            tool: file.tool,
            input: file.input,
            requestedAt: file.requestedAt,
            timeoutSeconds: file.timeoutSeconds,
            pendingFileURL: url
        )

        // 1プロジェクトにつき最新1件（前のを置き換える）
        pendingApprovals.removeAll { $0.projectID == projectID }
        pendingApprovals.append(request)
    }

    // MARK: - Decision

    func approve(_ request: ToolApprovalRequest) {
        writeResponse(request: request, decision: .allow)
    }

    func deny(_ request: ToolApprovalRequest) {
        writeResponse(request: request, decision: .deny)
    }

    private func writeResponse(request: ToolApprovalRequest, decision: ToolApprovalResponse.Decision) {
        let response = ToolApprovalResponse(
            schemaVersion: "1.0",
            sessionID: request.sessionID,
            decision: decision,
            decidedAt: Date()
        )
        let approvalURL = request.pendingFileURL
            .deletingLastPathComponent()
            .appendingPathComponent("approval.json")

        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        encoder.dateEncodingStrategy = .iso8601

        if let data = try? encoder.encode(response) {
            try? data.write(to: approvalURL, options: .atomic)
        }
        pendingApprovals.removeAll { $0.id == request.id }
    }
}

// MARK: - JSON DTO

private struct ToolApprovalFile: Decodable {
    let sessionID: String
    let tool: String
    let input: [String: String]
    let requestedAt: Date
    let timeoutSeconds: Int

    enum CodingKeys: String, CodingKey {
        case sessionID = "session_id"
        case tool, input
        case requestedAt = "requested_at"
        case timeoutSeconds = "timeout_seconds"
    }
}
