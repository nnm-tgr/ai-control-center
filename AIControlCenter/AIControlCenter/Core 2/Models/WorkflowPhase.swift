import Foundation

enum WorkflowPhase: String, Codable, Sendable, CaseIterable {
    case spec = "spec"
    case planning = "planning"
    case coding = "coding"
    case review = "review"
    case testing = "testing"
    case debugging = "debugging"
    case deploying = "deploying"

    var displayName: String {
        switch self {
        case .spec: "Spec"
        case .planning: "Plan"
        case .coding: "Coding"
        case .review: "Review"
        case .testing: "Testing"
        case .debugging: "Debug"
        case .deploying: "Deploy"
        }
    }

    var iconSystemName: String {
        switch self {
        case .spec: "doc.text"
        case .planning: "list.bullet.clipboard"
        case .coding: "chevron.left.forwardslash.chevron.right"
        case .review: "eye"
        case .testing: "checkmark.seal"
        case .debugging: "ant"
        case .deploying: "arrow.up.to.line"
        }
    }

    /// Workflow バーでの表示順序
    var ordinal: Int {
        switch self {
        case .spec: 0
        case .planning: 1
        case .coding: 2
        case .review: 3
        case .testing: 4
        case .debugging: 5
        case .deploying: 6
        }
    }
}
