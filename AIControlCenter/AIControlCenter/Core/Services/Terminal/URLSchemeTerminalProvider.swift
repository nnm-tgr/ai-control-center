import AppKit

/// Warp・Ghostty 向け URL スキーム実装
struct URLSchemeTerminalProvider: TerminalProvider {
    let providerType: TerminalProviderType
    var supportsFallback: Bool { true }

    func open(workingDirectory: URL) async throws {
        guard let url = openURL(for: providerType, path: workingDirectory.path) else {
            throw AppError.terminal(.providerNotAvailable(name: providerType.displayName))
        }

        let opened = await NSWorkspace.shared.open(url)
        if !opened {
            throw AppError.terminal(.activationFailed(reason: "Could not open URL: \(url)"))
        }
    }

    // MARK: - URL Schemes

    private func openURL(for type: TerminalProviderType, path: String) -> URL? {
        guard let encoded = path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) else {
            return nil
        }
        switch type {
        case .warp:
            // warp://action/new_tab?path=<encoded-path>
            return URL(string: "warp://action/new_tab?path=\(encoded)")
        case .ghostty:
            // ghostty://open?path=<encoded-path>
            return URL(string: "ghostty://open?path=\(encoded)")
        default:
            return nil
        }
    }
}
