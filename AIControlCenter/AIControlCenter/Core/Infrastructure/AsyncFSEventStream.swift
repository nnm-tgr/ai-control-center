import Foundation

/// FSEventStreamWrapper を Service 層に公開するための高レベル API
///
/// 使い方:
/// ```swift
/// let stream = AsyncFSEventStream(paths: ["/path/to/root"])
/// for await url in stream.urls {
///     // agent-status.json の URL が届く
/// }
/// ```
final class AsyncFSEventStream: Sendable {

    private let wrapper: FSEventStreamWrapper

    init(
        paths: [String],
        excludedPathSegments: Set<String> = Set(Settings.defaultExcludedNames),
        latency: CFTimeInterval = 0.5,
        targetFileNames: Set<String> = ["agent-status.json"]
    ) {
        self.wrapper = FSEventStreamWrapper(
            paths: paths,
            excludedPathSegments: excludedPathSegments,
            latency: latency,
            targetFileNames: targetFileNames
        )
    }

    /// フィルタ済み agent-status.json の URL を非同期に yield する
    var urls: AsyncStream<URL> {
        AsyncStream { continuation in
            Task {
                for await event in wrapper.start() {
                    let url = URL(fileURLWithPath: event.path)
                    continuation.yield(url)
                }
                continuation.finish()
            }
        }
    }

    func stop() {
        wrapper.stop()
    }
}
