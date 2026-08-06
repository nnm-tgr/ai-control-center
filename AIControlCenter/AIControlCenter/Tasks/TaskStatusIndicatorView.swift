import SwiftUI

/// Shared status indicator for task rows (circle for root tasks, rounded-rect for subtasks).
struct TaskStatusIndicatorView: View {
    let status: TaskStatus
    let size: CGFloat
    var isSubtask: Bool = false

    private var borderColor: Color {
        status.isDone    ? .green
        : status == .inProgress ? .yellow
        : .secondary.opacity(0.5)
    }

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
            Circle()
                .strokeBorder(borderColor, lineWidth: 1.5)
            if status.isDone {
                Circle().fill(Color.green)
                checkmark
            }
        }
    }

    private var subtaskShape: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 3)
                .strokeBorder(borderColor, lineWidth: 1.5)
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
