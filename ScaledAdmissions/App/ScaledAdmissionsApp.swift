import SwiftUI

@main
struct ScaledAdmissionsApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(appState)
                .tint(Theme.accentText)
                .preferredColorScheme(.light)
                .task { await appState.start() }
        }
    }
}
