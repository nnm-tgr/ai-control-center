import SwiftUI

struct BannerOverlayView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        VStack(spacing: 6) {
            ForEach(appState.pendingBanners) { banner in
                BannerItemView(banner: banner)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.spring(duration: 0.3), value: appState.pendingBanners.map(\.id))
        .padding(.top, 8)
        .padding(.horizontal, 12)
        .frame(maxWidth: 560)
    }
}

private struct BannerItemView: View {
    @Environment(AppState.self) private var appState
    let banner: BannerMessage

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(tint)
                .font(.callout)

            Text(banner.message)
                .font(.callout)
                .foregroundStyle(.primary)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)

            Button {
                appState.dismissBanner(banner.id)
            } label: {
                Image(systemName: "xmark")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(tint.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(tint.opacity(0.3), lineWidth: 1)
        )
        .task(id: banner.id) {
            guard let seconds = banner.autoDismissAfter else { return }
            try? await Task.sleep(for: .seconds(seconds))
            appState.dismissBanner(banner.id)
        }
    }

    private var icon: String {
        switch banner.level {
        case .info:    "info.circle.fill"
        case .warning: "exclamationmark.triangle.fill"
        case .error:   "xmark.circle.fill"
        }
    }

    private var tint: Color {
        switch banner.level {
        case .info:    .blue
        case .warning: .orange
        case .error:   .red
        }
    }
}
