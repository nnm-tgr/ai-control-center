import SwiftUI

struct StatusBadgeView: View {
    let status: AgentStatus

    @State private var isPulsing = false

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(status.color)
                .frame(width: 8, height: 8)
                .scaleEffect(isPulsing ? 1.25 : 1.0)
                .opacity(isPulsing ? 0.6 : 1.0)
                .animation(
                    status == .thinking
                        ? .easeInOut(duration: 0.8).repeatForever(autoreverses: true)
                        : .default,
                    value: isPulsing
                )

            Text(status.displayName)
                .font(.callout)
                .foregroundStyle(status.color)
        }
        .onAppear {
            if status == .thinking { isPulsing = true }
        }
        .onChange(of: status) { _, newValue in
            isPulsing = newValue == .thinking
        }
    }
}

#Preview("All Statuses") {
    VStack(alignment: .leading, spacing: 12) {
        ForEach(AgentStatus.allCases, id: \.self) { status in
            StatusBadgeView(status: status)
        }
    }
    .padding()
    .frame(width: 160)
}
