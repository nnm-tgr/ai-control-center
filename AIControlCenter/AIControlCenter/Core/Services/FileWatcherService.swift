import Foundation

/// ルートディレクトリ群を FSEventStream で監視し、agent-status.json の変更を
/// StatusParserService 経由で Agent に変換して通知する
@Observable
@MainActor
final class FileWatcherService {

    // MARK: - Published State

    /// projectID → 最新 Agent のキャッシュ
    private(set) var agentByProjectID: [UUID: Agent] = [:]
    private(set) var lastError: AppError?

    // MARK: - Dependencies

    private let parser = StatusParserService()

    // MARK: - Private

    private var activeStream: AsyncFSEventStream?
    private var watchTask: Task<Void, Never>?

    // MARK: - Lifecycle

    /// 監視対象のルートディレクトリを設定して開始
    func start(roots: [URL], excludedNames: Set<String> = Set(Settings.defaultExcludedNames)) {
        stop()
        let paths = roots.map(\.path)
        guard !paths.isEmpty else { return }

        let stream = AsyncFSEventStream(paths: paths, excludedPathSegments: excludedNames)
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
        // agent-status.json → .ai/ → project root
        let projectRoot = url
            .deletingLastPathComponent()
            .deletingLastPathComponent()

        let projectID = Self.projectID(for: projectRoot)
        let existing = agentByProjectID[projectID]

        do {
            let agent = try parser.loadAgent(at: url, projectID: projectID, existing: existing)
            agentByProjectID[projectID] = agent
            lastError = nil
        } catch let error as AppError {
            lastError = error
        } catch {
            lastError = .statusParsing(.decodingFailed(url: url, underlying: error.localizedDescription))
        }
    }

    // MARK: - Stable Project ID

    /// プロジェクトルート URL から安定した UUID を導出する。
    /// 同じ URL は常に同じ UUID を返す（AppState での Project 紐付けに使用）。
    static func projectID(for rootURL: URL) -> UUID {
        let path = rootURL.standardizedFileURL.path
        var hasher = Hasher()
        hasher.combine("ai-control-center.project")
        hasher.combine(path)
        let h = UInt64(bitPattern: Int64(hasher.finalize()))
        // UUID の下位 48bit に埋め込む（衝突率は実用上無視できる）
        return UUID(uuid: (
            0, 0, 0, 0, 0, 0, 0, 0,
            UInt8((h >> 40) & 0xFF), UInt8((h >> 32) & 0xFF),
            UInt8((h >> 24) & 0xFF), UInt8((h >> 16) & 0xFF),
            UInt8((h >> 8)  & 0xFF), UInt8(h & 0xFF),
            0, 0
        ))
    }
}
