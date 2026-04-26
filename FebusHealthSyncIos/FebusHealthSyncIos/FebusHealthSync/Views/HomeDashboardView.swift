import SwiftUI
import FirebaseAuth

struct HomeDashboardView: View {
    @EnvironmentObject var authService: AuthService
    @EnvironmentObject var syncManager: SyncManager
    
    @State private var showingWorkouts = false
    @State private var showingLogs = false
    
    var body: some View {
        NavigationView {
            List {
                Section("User Profile") {
                    if let user = authService.currentUser {
                        HStack {
                            Text("Email:")
                            Spacer()
                            Text(user.email ?? "Unknown")
                                .foregroundColor(.secondary)
                        }
                    }
                }
                
                Section("Sync Status") {
                    HStack {
                        Text("Status:")
                        Spacer()
                        Text(syncManager.syncStatusMessage)
                            .foregroundColor(syncManager.isSyncing ? .blue : .secondary)
                    }
                    
                    if let lastSync = syncManager.lastSyncTime {
                        HStack {
                            Text("Last Sync:")
                            Spacer()
                            Text(lastSync, style: .time)
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    HStack {
                        Text("Synced Workouts:")
                        Spacer()
                        Text("\(syncManager.syncedWorkoutsCount)")
                            .foregroundColor(.secondary)
                    }
                }
                
                Section("Actions") {
                    Button(action: {
                        Task {
                            await syncManager.performManualSync()
                        }
                    }) {
                        HStack {
                            Text("Manual Sync (Last 30 Days)")
                            Spacer()
                            if syncManager.isSyncing {
                                ProgressView()
                            } else {
                                Image(systemName: "arrow.triangle.2.circlepath")
                            }
                        }
                    }
                    .disabled(syncManager.isSyncing)
                    
                    NavigationLink(destination: WorkoutListView()) {
                        Text("View Recent Workouts")
                    }
                    
                    NavigationLink(destination: DebugLogView()) {
                        Text("View Sync Logs")
                    }
                }
            }
            .navigationTitle("Dashboard")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Sign Out") {
                        authService.signOut()
                    }
                }
            }
        }
        .onAppear {
            syncManager.setupBackgroundSync()
        }
    }
}
