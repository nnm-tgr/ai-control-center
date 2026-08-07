import SwiftUI

/// Shared status indicator for task rows (circle for root tasks, rounded-rect for subtasks).
struct TaskStatusIndicatorView: View {
    let status: TaskStatus
    let size: CGFloat
    var isSubtask: Bool = false

    private var borderColor: Color { status.color.opacity(status == .todo ? 0.5 : 1) }

    var body: some View {
        ZStack {
            if isSubtask {
                subtaskShape
            } else {
                rootShape
            }
        }
        .frame(width: size, height: size)
    }

    private var rootShape: some View {
        ZStack {
            Circle().strokeBorder(borderColor, lineWidth: 1.5)
            switch status {
            case .done:
                Circle().fill(Color.green)
                checkmark
            case .inProgress:
                Circle().strokeBorder(Color.blue, lineWidth: 1.5)
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: size * 0.45, weight: .medium))
                    .foregroundStyle(Color.blue)
            case .inReview:
                Circle().strokeBorder(Color.purple, lineWidth: 1.5)
                Image(systemName: "eye")
                    .font(.system(size: size * 0.4, weight: .medium))
                    .foregroundStyle(Color.purple)
            case .onHold:
                Circle().strokeBorder(Color.orange, lineWidth: 1.5)
                Image(systemName: "pause")
                    .font(.system(size: size * 0.4, weight: .semibold))
                    .foregroundStyle(Color.orange)
            case .todo:
                EmptyView()
            }
        }
    }

    private var subtaskShape: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 3).strokeBorder(borderColor, lineWidth: 1.5)
            if status.isDone {
                RoundedRectangle(cornerRadius: 3).fill(Color.green)
                checkmark
            }
        }
    }

    private var checkmark: some View {
        Image(systemName: "checkmark")
            .font(.system(size: size * 0.6, weight: .bold))
            .foregroundStyle(.white)
    }
}
