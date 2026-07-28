import Foundation
import CoreServices

/// FSEventStream を Swift の async/await に橋渡しするラッパー
///
/// フィルタリング 2段階:
///   Stage 1 — パスセグメントで除外ディレクトリを早期スキップ
///   Stage 2 — ファイル名が "agent-status.json" に完全一致するイベントのみ通過
final class FSEventStreamWrapper: @unchecked Sendable {

    // MARK: - Types

    struct Event: Sendable {
        let path: String
        let flags: FSEventStreamEventFlags
        let id: FSEventStreamEventId
    }

    // MARK: - Properties

    private let watchedPaths: [String]
    private let excludedPathSegments: Set<String>
    private let latency: CFTimeInterval
    private var stream: FSEventStreamRef?
    private var continuation: AsyncStream<Event>.Continuation?

    // MARK: - Init

    /// - Parameters:
    ///   - paths: 監視するルートディレクトリのパス群
    ///   - excludedPathSegments: このセグメントを含むパスを Stage 1 で除外（例: "node_modules"）
    ///   - latency: イベントバッチの遅延秒数（デフォルト 0.5s）
    init(
        paths: [String],
        excludedPathSegments: Set<String> = Set(Settings.defaultExcludedNames),
        latency: CFTimeInterval = 0.5
    ) {
        self.watchedPaths = paths
        self.excludedPathSegments = excludedPathSegments
        self.latency = latency
    }

    deinit {
        stop()
    }

    // MARK: - Public

    /// イベントの AsyncStream を返す。呼び出し元は for-await で受け取る。
    func start() -> AsyncStream<Event> {
        AsyncStream { continuation in
            self.continuation = continuation
            self.startStream()
            continuation.onTermination = { [weak self] _ in
                self?.stop()
            }
        }
    }

    func stop() {
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        self.stream = nil
        continuation?.finish()
        continuation = nil
    }

    // MARK: - Private

    private func startStream() {
        guard stream == nil, !watchedPaths.isEmpty else { return }

        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passRetained(self).toOpaque(),
            retain: nil,
            release: { Unmanaged<FSEventStreamWrapper>.fromOpaque($0!).release() },
            copyDescription: nil
        )

        let flags = FSEventStreamCreateFlags(
            kFSEventStreamCreateFlagUseCFTypes |
            kFSEventStreamCreateFlagFileEvents |
            kFSEventStreamCreateFlagNoDefer
        )

        guard let ref = FSEventStreamCreate(
            nil,
            fsEventCallback,
            &context,
            watchedPaths as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            latency,
            flags
        ) else { return }

        FSEventStreamScheduleWithRunLoop(ref, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        FSEventStreamStart(ref)
        self.stream = ref
    }

    // MARK: - Event Filtering

    /// Stage 1: パスセグメントに除外名が含まれるか判定
    func shouldExclude(path: String) -> Bool {
        let segments = path.split(separator: "/")
        return segments.contains { excludedPathSegments.contains(String($0)) }
    }

    /// Stage 2: パスの最終コンポーネントが "agent-status.json" に完全一致するか判定
    func isTargetFile(path: String) -> Bool {
        (path as NSString).lastPathComponent == "agent-status.json"
    }

    fileprivate func handleEvents(paths: [String], flags: [FSEventStreamEventFlags], ids: [FSEventStreamEventId]) {
        for (index, path) in paths.enumerated() {
            // Stage 1: 除外パスセグメントチェック
            guard !shouldExclude(path: path) else { continue }
            // Stage 2: ファイル名完全一致チェック
            guard isTargetFile(path: path) else { continue }

            let event = Event(path: path, flags: flags[index], id: ids[index])
            continuation?.yield(event)
        }
    }
}

// MARK: - C Callback (file-scope)

private let fsEventCallback: FSEventStreamCallback = { _, info, numEvents, eventPaths, eventFlags, eventIds in
    guard let info else { return }
    let wrapper = Unmanaged<FSEventStreamWrapper>.fromOpaque(info).takeUnretainedValue()

    let cfPaths = unsafeBitCast(eventPaths, to: CFArray.self)
    guard let paths = cfPaths as? [String] else { return }

    let flags = (0..<numEvents).map { eventFlags[$0] }
    let ids = (0..<numEvents).map { eventIds[$0] }

    wrapper.handleEvents(paths: paths, flags: flags, ids: ids)
}

