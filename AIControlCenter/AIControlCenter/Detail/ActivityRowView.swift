import SwiftUI

struct ActivityRowView: View {
    let activity: Activity

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            // Timeline dot + line
            VStack(spacing: 0) {
                Circle()
                    .fill(activity.status.color)
                    .frame(width: 8, height: 8)
                    .padding(.top, 5)
                Rectangle()
                    .fill(Color.secondary.opacity(0.2))
                    .frame(width: 1)
            }

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(activity.status.displayName)
                        .font(.callout.bold())
                        .foregroundStyle(activity.status.color)

                    if let phase = activity.workflowPhase {
                        Label(phase.displayName, systemImage: phase.iconSystemName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Text(activity.formattedTimestamp)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .monospacedDigit()

                    if let duration = activity.formattedDuration {
                        Text("(\(duration))")
                            .font(.caption)
                            .foregroundStyle(.quaternary)
                    }
                }

                if let task = activity.task {
                    Text(task)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            .padding(.bottom, 10)
        }
        .padding(.leading, 12)
    }
}

#Preview("Activity Rows") {
    let agentID = UUID()
    let activities = MockData.activities(agentID: agentID)
    ScrollView {
        LazyVStack(spacing: 0) {
            ForEach(activities.reversed()) { activity in
                ActivityRowView(activity: activity)
                    .id(activity.id)
            }
        }
        .padding(.vertical, 8)
    }
    .frame(width: 440, height: 400)
}
