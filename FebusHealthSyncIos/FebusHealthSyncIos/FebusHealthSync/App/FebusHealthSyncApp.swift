import SwiftUI
import FirebaseCore
import GoogleSignIn



@main
struct FebusHealthSyncApp: App {
    @StateObject private var authService: AuthService
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
            Group {
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
            .onOpenURL { url in
                GIDSignIn.sharedInstance.handle(url)
            }
        }
    }
}
