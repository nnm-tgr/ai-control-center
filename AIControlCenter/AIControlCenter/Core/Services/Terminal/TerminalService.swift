import Foundation

/// TerminalProvider を選択・実行し、権限拒否時はフォールバックへ切り替えるサービス
@MainActor
final class TerminalService {

    // MARK: - Public

    /// 指定プロジェクトのルートディレクトリでターミナルを開く
    /// - Returns: フォールバックを使用した場合は BannerMessage を返す
    func open(workingDirectory: URL, providerType: TerminalProviderType) async throws -> BannerMessage? {
        let provider = makeProvider(for: providerType)

        do {
            try await provider.open(workingDirectory: workingDirectory)
            return nil
        } catch AppError.terminal(.automationPermissionDenied(let name)) {
            guard provider.supportsFallback else {
                throw AppError.terminal(.automationPermissionDenied(terminalName: name))
            }
            try FallbackTerminalJump.execute(
                workingDirectory: workingDirectory,
                terminalBundleID: providerType.bundleIdentifier
            )
            return BannerMessage(
                message: "cd command copied to clipboard — paste it in the terminal manually.",
                level: .warning,
                autoDismissAfter: 10
            )
        }
    }

    /// 指定プロジェクトのディレクトリにいる既存のターミナルセッションにフォーカスする。
    /// 見つからない場合は AppError.terminal(.sessionNotFound) を throw する。
    func jump(to workingDirectory: URL, providerType: TerminalProviderType) async throws {
        switch providerType {
        case .terminal, .iTerm2:
            let provider = AppleScriptTerminalProvider(providerType: providerType)
            let found = try await provider.jumpToExisting(workingDirectory: workingDirectory)
            if !found {
                throw AppError.terminal(.sessionNotFound(path: workingDirectory.path))
            }
        case .warp, .ghostty:
            // URL scheme providers don't support jumping to existing windows
            throw AppError.terminal(.sessionNotFound(path: workingDirectory.path))
        }
    }

    // MARK: - Provider Factory

    private func makeProvider(for type: TerminalProviderType) -> any TerminalProvider {
        switch type {
        case .terminal, .iTerm2:
            return AppleScriptTerminalProvider(providerType: type)
        case .warp, .ghostty:
            return URLSchemeTerminalProvider(providerType: type)
        }
    }
}
