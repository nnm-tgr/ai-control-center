import Foundation
import AppKit

enum TerminalProviderType: String, Codable, Sendable, CaseIterable {
    case terminal = "terminal"
    case iTerm2 = "iterm2"
    case warp = "warp"
    case ghostty = "ghostty"

    var displayName: String {
        switch self {
        case .terminal: "Terminal.app"
        case .iTerm2: "iTerm2"
        case .warp: "Warp"
        case .ghostty: "Ghostty"
        }
    }

    var bundleIdentifier: String {
        switch self {
        case .terminal: "com.apple.Terminal"
        case .iTerm2: "com.googlecode.iterm2"
        case .warp: "dev.warp.Warp-Stable"
        case .ghostty: "com.mitchellh.ghostty"
        }
    }

    /// Terminal.app は macOS 標準同梱のため常に true
    var isInstalled: Bool {
        if self == .terminal { return true }
        return NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) != nil
    }
}
