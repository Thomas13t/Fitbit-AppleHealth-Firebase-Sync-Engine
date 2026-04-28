import SwiftUI

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
                
                Section("Today's Overview") {
                    if let summary = syncManager.todaySummary {
                        HStack {
                            Image(systemName: "shoeprints.fill")
                                .foregroundColor(.orange)
                            Text("Steps")
                            Spacer()
                            Text("\(summary.totalSteps)")
                                .fontWeight(.bold)
                        }
                        HStack {
                            Image(systemName: "flame.fill")
                                .foregroundColor(.red)
                            Text("Active Energy")
                            Spacer()
                            Text("\(Int(summary.totalActiveEnergyKcal)) kcal")
                                .fontWeight(.bold)
                        }
                        if let rhr = summary.restingHeartRate, rhr > 0 {
                            HStack {
                                Image(systemName: "heart.fill")
                                    .foregroundColor(.pink)
                                Text("Resting HR")
                                Spacer()
                                Text("\(Int(rhr)) bpm")
                                    .fontWeight(.bold)
                            }
                        }
                        HStack {
                            Image(systemName: "figure.run")
                                .foregroundColor(.cyan)
                            Text("Workouts")
                            Spacer()
                            Text("\(summary.totalWorkouts)")
                                .fontWeight(.bold)
                        }
                    } else {
                        Text("No data for today yet. Try manual sync.")
                            .foregroundColor(.secondary)
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
