import SwiftUI
import FirebaseCore
import GoogleSignIn

// App Delegate to handle Firebase setup and Google Sign in URL handling
class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {
        
        // FirebaseApp.configure() moved to App init
        return true
    }
    
    // Handle the redirect URL for Google Sign-In
    func application(_ app: UIApplication,
                     open url: URL,
                     options: [UIApplication.OpenURLOptionsKey: Any] = [:]) -> Bool {
      return GIDSignIn.sharedInstance.handle(url)
    }
}

@main
struct FebusHealthSyncApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate
    
    @StateObject private var authService = AuthService()
    @StateObject private var syncManager: SyncManager
    
    init() {
        FirebaseApp.configure()
        
        let auth = AuthService()
        let firestore = FirestoreService()
        let healthKit = HealthKitService()
        
        _authService = StateObject(wrappedValue: auth)
        _syncManager = StateObject(wrappedValue: SyncManager(healthKitService: healthKit, firestoreService: firestore, authService: auth))
    }
    
    var body: some Scene {
        WindowGroup {
            if authService.isAuthenticated {
                WorkoutListView()
                    .environmentObject(authService)
                    .environmentObject(syncManager)
                    .task {
                        // Request HealthKit auth when landing on home screen
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
