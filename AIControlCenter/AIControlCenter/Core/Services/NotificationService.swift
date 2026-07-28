import AppKit
import UserNotifications
import Foundation

/// UNUserNotificationCenter へのラッパー
/// AppState からステータス遷移を受け取りシステム通知を発行する
@MainActor
final class NotificationService: NSObject {

    static let shared = NotificationService()

    private let center = UNUserNotificationCenter.current()

    override init() {
        super.init()
        center.delegate = self
    }

    // MARK: - Permission

    func requestAuthorization() async -> Bool {
        do {
            return try await center.requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
            return false
        }
    }

    var authorizationStatus: UNAuthorizationStatus {
        get async {
            await center.notificationSettings().authorizationStatus
        }
    }

    // MARK: - Post

    func post(_ notification: AppNotification, settings: Settings) async {
        guard settings.notificationsEnabled,
              !settings.doNotDisturbEnabled,
              notification.level >= settings.notificationLevel else { return }

        let content = UNMutableNotificationContent()
        content.title = notification.title
        content.body = notification.body.isEmpty ? notification.triggeredBy.to.displayName : notification.body
        content.sound = notification.level >= .high ? .defaultCritical : .default
        content.userInfo = [
            "projectID": notification.projectID.uuidString,
            "agentID": notification.agentID.uuidString
        ]

        let request = UNNotificationRequest(
            identifier: notification.notificationIdentifier,
            content: content,
            trigger: nil  // 即時配信
        )

        try? await center.add(request)
    }

    // MARK: - Badge

    func updateBadge(unreadCount: Int) async {
        try? await center.setBadgeCount(unreadCount)
    }

    func clearAll() {
        center.removeAllDeliveredNotifications()
        center.removeAllPendingNotificationRequests()
    }
}

// MARK: - UNUserNotificationCenterDelegate

extension NotificationService: UNUserNotificationCenterDelegate {
    /// アプリがフォアグラウンドの場合もバナーを表示する
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    /// 通知タップ時はメインウィンドウを前面に出す
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        await MainActor.run {
            NSApp.activate(ignoringOtherApps: true)
            NSApp.windows.first?.makeKeyAndOrderFront(nil)
        }
    }
}

// MARK: - Notification Rules

/// どの遷移が通知をトリガーするかを判定する
enum NotificationRule {

    /// ステータス遷移が通知対象か判定する
    static func shouldNotify(from old: AgentStatus?, to new: AgentStatus) -> Bool {
        switch new {
        case .error:
            return true  // エラーは常に通知
        case .waitingUser:
            return true  // ユーザー入力待ちは常に通知
        case .completed:
            return old == .runningCommand || old == .thinking
        case .idle:
            return false
        case .thinking, .runningCommand:
            // 非アクティブ → アクティブ の変化のみ
            return old == .idle || old == nil
        }
    }

    static func level(for status: AgentStatus) -> NotificationLevel {
        switch status {
        case .error: .critical
        case .waitingUser: .high
        case .completed: .normal
        default: .low
        }
    }
}
