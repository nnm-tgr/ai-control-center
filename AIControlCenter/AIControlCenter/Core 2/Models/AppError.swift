import Foundation

enum AppError: Error, Sendable {
    case fileWatcher(FileWatcherError)
    case statusParsing(StatusParsingError)
    case projectDiscovery(ProjectDiscoveryError)
    case terminal(TerminalError)
    case git(GitError)

    enum FileWatcherError: Sendable {
        case watchFailed(url: URL, reason: String)
        case streamCreationFailed
    }

    enum StatusParsingError: Sendable {
        case fileNotFound(url: URL)
        case decodingFailed(url: URL, underlying: String)
        case unsupportedSchemaVersion(version: String)
    }

    enum ProjectDiscoveryError: Sendable {
        case rootNotAccessible(url: URL)
        case permissionDenied(url: URL)
    }

    enum TerminalError: Sendable {
        case providerNotAvailable(name: String)
        case activationFailed(reason: String)
        case automationPermissionDenied(terminalName: String)
        case automationFallbackUsed(terminalName: String, copiedPath: String)
    }

    enum GitError: Sendable {
        case notARepository(url: URL)
        case commandFailed(exitCode: Int32, stderr: String)
    }

    var localizedDescription: String {
        switch self {
        case .fileWatcher(.watchFailed(let url, let reason)):
            "Failed to watch \(url.lastPathComponent): \(reason)"
        case .fileWatcher(.streamCreationFailed):
            "Failed to create file system event stream."
        case .statusParsing(.fileNotFound(let url)):
            "Status file not found: \(url.path)"
        case .statusParsing(.decodingFailed(let url, let underlying)):
            "Failed to parse \(url.lastPathComponent): \(underlying)"
        case .statusParsing(.unsupportedSchemaVersion(let version)):
            "Unsupported schema version: \(version)"
        case .projectDiscovery(.rootNotAccessible(let url)):
            "Cannot access directory: \(url.path)"
        case .projectDiscovery(.permissionDenied(let url)):
            "Permission denied: \(url.path)"
        case .terminal(.providerNotAvailable(let name)):
            "\(name) is not installed."
        case .terminal(.activationFailed(let reason)):
            "Failed to open terminal: \(reason)"
        case .terminal(.automationPermissionDenied(let name)):
            "Automation permission denied for \(name)."
        case .terminal(.automationFallbackUsed(let name, _)):
            "Automation denied for \(name). cd command copied to clipboard."
        case .git(.notARepository(let url)):
            "\(url.lastPathComponent) is not a git repository."
        case .git(.commandFailed(let code, let stderr)):
            "git exited with code \(code): \(stderr)"
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .projectDiscovery(.permissionDenied):
            "Change the root directory in Settings."
        case .terminal(.automationPermissionDenied):
            "Open System Settings > Privacy & Security > Automation to grant access."
        case .terminal(.automationFallbackUsed(_, let path)):
            "Paste in terminal: cd '\(path)'"
        default:
            nil
        }
    }
}
