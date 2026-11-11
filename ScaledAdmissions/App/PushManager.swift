import UIKit
import UserNotifications

/// Push notifications, as in Care Assist: asks once after sign-in, sends the
/// phone's token to the server (app/api/mobile/devices), and opens the chat a
/// tapped notification is about.
@MainActor
final class PushManager: NSObject, UNUserNotificationCenterDelegate {
    static let shared = PushManager()

    /// Set by AppState; called with a conversation id when a notification is tapped.
    var openConversation: ((String) -> Void)? {
        didSet { flush() }
    }
    /// A tap that arrived before anyone was listening (the app launched from it).
    private var waitingConversationID: String?

    private func flush() {
        guard let id = waitingConversationID, let openConversation else { return }
        waitingConversationID = nil
        openConversation(id)
    }

    private static let tokenKey = "apnsDeviceToken"
    private var token: String? {
        get { UserDefaults.standard.string(forKey: Self.tokenKey) }
        set { UserDefaults.standard.set(newValue, forKey: Self.tokenKey) }
    }

    /// Xcode builds get tokens for Apple's sandbox; TestFlight and the App Store, production.
    private var environment: String {
        #if DEBUG
        "sandbox"
        #else
        "production"
        #endif
    }

    func configure() {
        UNUserNotificationCenter.current().delegate = self
    }

    /// Asks the first time; after that, re-registers so a changed token reaches the server.
    func enable() async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .notDetermined:
            let granted = (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
            if granted { UIApplication.shared.registerForRemoteNotifications() }
        case .authorized, .provisional, .ephemeral:
            UIApplication.shared.registerForRemoteNotifications()
        default:
            break
        }
    }

    func didRegister(deviceToken: Data) {
        let hex = deviceToken.map { String(format: "%02x", $0) }.joined()
        token = hex
        Task { try? await MobileAPI.registerDevice(token: hex, environment: environment) }
    }

    /// On sign-out, so the next person on this phone does not get the last one's alerts.
    func disable() async {
        guard let token else { return }
        try? await MobileAPI.unregisterDevice(token: token)
    }

    // Banners show even while the app is open.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound, .list]
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let id = response.notification.request.content.userInfo["conversation_id"] as? String
        guard let id else { return }
        await MainActor.run {
            waitingConversationID = id
            flush()
        }
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        // Set before launch finishes, so a tap that launched the app is not missed.
        MainActor.assumeIsolated { PushManager.shared.configure() }
        return true
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        MainActor.assumeIsolated { PushManager.shared.didRegister(deviceToken: deviceToken) }
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        // Simulators without a push setup, or no network: the app works without push.
    }
}
