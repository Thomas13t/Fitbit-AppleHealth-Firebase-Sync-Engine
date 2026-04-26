import SwiftUI
import FirebaseCore
import GoogleSignIn
import UIKit

class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ app: UIApplication,
                     open url: URL,
                     options: [UIApplication.OpenURLOptionsKey: Any] = [:]) -> Bool {
        return GIDSignIn.sharedInstance.handle(url)
    }
}

@main
struct FebusHealthSyncApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate

    @StateObject private var authService: AuthService
    @StateObject private var syncManager: SyncManager

    init() {
        FirebaseApp.configure()

        let auth = AuthService()
        let firestore = FirestoreService()
        let healthKit = HealthKitService()

        _authService = StateObject(wrappedValue: auth)
        _syncManager = StateObject(wrappedValue: SyncManager(
            healthKitService: healthKit,
            firestoreService: firestore,
            authService: auth
        ))
    }

    var body: some Scene {
        WindowGroup {
            if authService.isAuthenticated {
                HomeDashboardView()
                    .environmentObject(authService)
                    .environmentObject(syncManager)
                    .task {
                        do {
                            try await syncManager.healthKitService.requestAuthorization()
                        } catch {
                            print("HealthKit Authorization failed: \(error.localizedDescription)")
                        }
                    }
            } else {
                LoginView()
                    .environmentObject(authService)
            }
        }
    }
}
