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
    ///
    /// Swift.Hasher はプロセス起動ごとにシードがランダム化されるため使用不可。
    /// 代わりに FNV-1a 64-bit を 2 パスで走らせ 128-bit に拡張して UUID 全体を埋める。
    static func projectID(for rootURL: URL) -> UUID {
        let input = "ai-control-center.project:" + rootURL.standardizedFileURL.path
        let prime: UInt64 = 1099511628211
        var h0: UInt64 = 14695981039346656037          // FNV offset basis
        var h1: UInt64 = 14695981039346656037 ^ 0x5555_5555_5555_5555  // independent seed
        for byte in input.utf8 {
            h0 ^= UInt64(byte); h0 &*= prime
            h1 ^= UInt64(byte); h1 &*= prime
        }
        func b(_ v: UInt64, _ s: Int) -> UInt8 { UInt8((v >> s) & 0xFF) }
        return UUID(uuid: (
            b(h0,56), b(h0,48), b(h0,40), b(h0,32),
            b(h0,24), b(h0,16), b(h0, 8), b(h0, 0),
            b(h1,56), b(h1,48), b(h1,40), b(h1,32),
            b(h1,24), b(h1,16), b(h1, 8), b(h1, 0)
        ))
    }
}
