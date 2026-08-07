import SwiftUI

extension TaskStatus {
    var color: Color {
        switch self {
        case .todo:       .secondary
        case .inProgress: .blue
        case .inReview:   .purple
        case .onHold:     .orange
        case .done:       .green
        }
    }
}
