import Foundation

/// ルートディレクトリを BFS で走査して .ai/agent-status.json を持つ
/// プロジェクトを発見し、Project モデルとして返すサービス
struct ProjectScannerService: Sendable {

    private let fileManager = FileManager.default
    private let parser = StatusParserService()

    // MARK: - Public

    /// 複数ルートを並列スキャンして Project 配列を返す
    func scan(roots: [URL], settings: Settings) async -> [Project] {
        await withTaskGroup(of: [Project].self) { group in
            for root in roots {
                group.addTask {
                    await self.scanRoot(root, settings: settings)
                }
            }
            var results: [Project] = []
            for await projects in group {
                results.append(contentsOf: projects)
            }
            return results
        }
    }

    // MARK: - BFS Scan

    private func scanRoot(_ root: URL, settings: Settings) async -> [Project] {
        let excluded = settings.excludedDirectoryNamesSet
        let maxDepth = settings.scanDepth
        var found: [Project] = []

        // BFS キュー: (URL, 現在の深さ)
        var queue: [(url: URL, depth: Int)] = [(root, 0)]
        // Visited set prevents symlink cycles from causing infinite loops.
        var visited: Set<URL> = [root.standardizedFileURL]

        while !queue.isEmpty {
            let (current, depth) = queue.removeFirst()

            // .ai/agent-status.json が存在すればプロジェクトとして登録し、子孫の探索を打ち切る
            let statusFile = current.appending(components: ".ai", "agent-status.json")
            if fileManager.fileExists(atPath: statusFile.path) {
                if let project = makeProject(root: current, statusFile: statusFile, settings: settings) {
                    found.append(project)
                }
                continue  // この配下は再帰しない
            }

            // 深さ制限に達したらこれ以上降りない
            guard depth < maxDepth else { continue }

            // サブディレクトリをキューに追加（除外リスト・隠しフォルダ・シムリンクを除く）
            let children = subdirectories(of: current, excluding: excluded)
            for child in children {
                let canonical = child.standardizedFileURL
                guard visited.insert(canonical).inserted else { continue }
                queue.append((child, depth + 1))
            }
        }

        return found
    }

    // MARK: - Helpers

    private func makeProject(root: URL, statusFile: URL, settings: Settings) -> Project? {
        let projectID = FileWatcherService.projectID(for: root)
        let isGit = fileManager.fileExists(atPath: root.appending(component: ".git").path)

        // 初回スキャン時にステータスをパースして Agent を生成
        let agent: Agent? = try? parser.loadAgent(at: statusFile, projectID: projectID)

        return Project(
            id: projectID,
            name: root.lastPathComponent,
            rootURL: root,
            agents: agent.map { [$0] } ?? [],
            isGitRepository: isGit
        )
    }

    private func subdirectories(of url: URL, excluding excluded: Set<String>) -> [URL] {
        guard let contents = try? fileManager.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey, .isHiddenKey],
            options: [.skipsPackageDescendants]
        ) else { return [] }

        return contents.filter { child in
            let name = child.lastPathComponent
            // 除外リストに含まれるもの、ドット始まりの隠しフォルダ（.git 等）は skip
            guard !excluded.contains(name), !name.hasPrefix(".") else { return false }
            let values = try? child.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            // シムリンクは BFS から除外（トラバーサル攻撃と無限ループの防止）
            guard values?.isSymbolicLink != true else { return false }
            return values?.isDirectory == true
        }
    }
}
