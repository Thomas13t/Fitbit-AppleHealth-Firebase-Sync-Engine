import SwiftUI
import FirebaseCore
import GoogleSignIn
import BackgroundTasks

class AppDelegate: NSObject, UIApplicationDelegate {
    var syncManager: SyncManager?
    
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: "com.febus.healthsync.refresh", using: nil) { task in
            self.handleAppRefresh(task: task as! BGAppRefreshTask)
        }
        return true
    }
    
    func scheduleAppRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: "com.febus.healthsync.refresh")
        // Earliest begin date: 4 hours from now
        request.earliestBeginDate = Date(timeIntervalSinceNow: 4 * 60 * 60)
        
        do {
            try BGTaskScheduler.shared.submit(request)
            print("[AppDelegate] Background Task Scheduled.")
        } catch {
            print("[AppDelegate] Failed to schedule Background Task: \(error.localizedDescription)")
        }
    }
    
    private func handleAppRefresh(task: BGAppRefreshTask) {
        scheduleAppRefresh()
        
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
        
        task.expirationHandler = {
            queue.cancelAllOperations()
        }
        
        let operation = BlockOperation {
            let semaphore = DispatchSemaphore(value: 0)
            
            Task { @MainActor in
                if let syncManager = self.syncManager {
                    await syncManager.performBackgroundTasksSync()
                }
                semaphore.signal()
            }
            
            semaphore.wait()
        }
        
        operation.completionBlock = {
            task.setTaskCompleted(success: !operation.isCancelled)
        }
        
        queue.addOperation(operation)
    }
}

struct AppContainerView: View {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var authService: AuthService
    @StateObject private var syncManager: SyncManager
    
    init() {
        let auth = AuthService()
        auth.setupStateListener()
        let firestore = FirestoreService()
        let healthKit = HealthKitService()
        
        _authService = StateObject(wrappedValue: auth)
        _syncManager = StateObject(wrappedValue: SyncManager(healthKitService: healthKit, firestoreService: firestore, authService: auth))
    }
    
    var body: some View {
        Group {
            if authService.isAuthenticated {
                MainTabView()
                    .environmentObject(authService)
                    .environmentObject(syncManager)
                    .task {
                        appDelegate.syncManager = syncManager
                        do {
                            try await syncManager.healthKitService.requestAuthorization()
                            syncManager.setupBackgroundSync()
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

@main
struct FebusHealthSyncApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @Environment(\.scenePhase) private var scenePhase
    
    #if UNIVERSAL_BUILD
    @State private var isConfigured: Bool = FirebaseConfigManager.shared.hasConfig
    #else
    @StateObject private var authService: AuthService
    @StateObject private var syncManager: SyncManager
    #endif
    
    init() {
        #if UNIVERSAL_BUILD
        if FirebaseConfigManager.shared.hasConfig {
            _ = FirebaseConfigManager.shared.configureFirebase()
        }
        #else
        FirebaseApp.configure()
        
        let auth = AuthService()
        auth.setupStateListener()
        let firestore = FirestoreService()
        let healthKit = HealthKitService()
        
        _authService = StateObject(wrappedValue: auth)
        _syncManager = StateObject(wrappedValue: SyncManager(healthKitService: healthKit, firestoreService: firestore, authService: auth))
        #endif
    }
    
    var body: some Scene {
        WindowGroup {
            #if UNIVERSAL_BUILD
            Group {
                if isConfigured {
                    AppContainerView()
                } else {
                    FirebaseConfigView(onConfigured: {
                        withAnimation {
                            isConfigured = true
                        }
                    })
                }
            }
            .onOpenURL { url in
                GIDSignIn.sharedInstance.handle(url)
            }
            .onChange(of: scenePhase) { newPhase in
                if newPhase == .background {
                    appDelegate.scheduleAppRefresh()
                }
            }
            #else
            Group {
                if authService.isAuthenticated {
                    MainTabView()
                        .environmentObject(authService)
                        .environmentObject(syncManager)
                        .task {
                            appDelegate.syncManager = syncManager
                            do {
                                try await syncManager.healthKitService.requestAuthorization()
                                syncManager.setupBackgroundSync()
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
            .onChange(of: scenePhase) { newPhase in
                if newPhase == .background {
                    appDelegate.scheduleAppRefresh()
                }
            }
            #endif
        }
    }
}

struct MainTabView: View {
    @EnvironmentObject var authService: AuthService
    @EnvironmentObject var syncManager: SyncManager
    
    var body: some View {
        TabView {
            NavigationView {
                HomeDashboardView()
            }
            .tabItem {
                Label("Dashboard", systemImage: "square.grid.2x2.fill")
            }
            
            WorkoutListView()
                .tabItem {
                    Label("Workouts", systemImage: "figure.run.circle.fill")
                }
        }
        .tint(.cyan)
        .preferredColorScheme(.dark)
    }
}
