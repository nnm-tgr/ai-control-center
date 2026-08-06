import SwiftUI

extension TaskPriority {
    var color: Color {
        switch self {
        case .low:    .secondary
        case .medium: .yellow
        case .high:   .orange
        case .urgent: .red
        }
    }
}
