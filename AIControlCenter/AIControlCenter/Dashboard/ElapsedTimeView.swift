import SwiftUI

struct ElapsedTimeView: View {
    let since: Date?

    var body: some View {
        Group {
            if let since {
                TimelineView(.periodic(from: since, by: 1)) { _ in
                    Text(formatElapsed(from: since))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            } else {
                Text("—")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private func formatElapsed(from date: Date) -> String {
        let elapsed = max(0, Date.now.timeIntervalSince(date))
        let totalSeconds = Int(elapsed)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60

        if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else if minutes > 0 {
            return "\(minutes)m \(seconds)s"
        } else {
            return "\(seconds)s"
        }
    }
}

#Preview("Elapsed Times") {
    VStack(alignment: .leading, spacing: 12) {
        ElapsedTimeView(since: Date.now.addingTimeInterval(-5))
        ElapsedTimeView(since: Date.now.addingTimeInterval(-75))
        ElapsedTimeView(since: Date.now.addingTimeInterval(-202))
        ElapsedTimeView(since: Date.now.addingTimeInterval(-3700))
        ElapsedTimeView(since: nil)
    }
    .padding()
}
