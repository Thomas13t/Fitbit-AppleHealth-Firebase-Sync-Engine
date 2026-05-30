import SwiftUI
import FirebaseAuth

struct HomeDashboardView: View {
    @EnvironmentObject var authService: AuthService
    @EnvironmentObject var syncManager: SyncManager
    
    @State private var showingWorkouts = false
    @State private var showingLogs = false
    @StateObject private var fitbitService = FitbitService()
    
    var body: some View {
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
                    if let sleepSec = summary.sleepDurationSeconds, sleepSec > 0 {
                        HStack {
                            Image(systemName: "bed.double.fill")
                                .foregroundColor(.purple)
                            Text("Sleep Duration")
                            Spacer()
                            Text("\(Int(sleepSec / 3600))h \(Int((sleepSec.truncatingRemainder(dividingBy: 3600)) / 60))m")
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
            
            Section("Fitbit Integration") {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Image(systemName: "waveform.path.ecg")
                            .foregroundColor(.cyan)
                            .font(.title3)
                        Text("Fitbit Connection")
                            .font(.headline)
                        Spacer()
                        
                        // Premium status badge
                        HStack(spacing: 4) {
                            Circle()
                                .fill(fitbitService.isLinked ? Color.green : Color.gray)
                                .frame(width: 8, height: 8)
                            Text(fitbitService.isLinked ? "Linked" : "Not Linked")
                                .font(.caption)
                                .fontWeight(.bold)
                                .foregroundColor(fitbitService.isLinked ? .green : .gray)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(
                            Capsule()
                                .stroke(fitbitService.isLinked ? Color.green.opacity(0.3) : Color.gray.opacity(0.3), lineWidth: 1)
                        )
                    }
                    
                    Text(fitbitService.isLinked 
                         ? "Your Fitbit account is successfully connected. Sleep phases (deep, REM, light, awake) will sync directly to Apple Health."
                         : "Link your Fitbit account to automatically sync your sleep logs and habits into Apple Health.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    
                    if !fitbitService.isLinked {
                        Button(action: {
                            fitbitService.authorize()
                        }) {
                            HStack {
                                Spacer()
                                Text("Link Fitbit Account")
                                    .fontWeight(.semibold)
                                Spacer()
                            }
                            .padding()
                            .background(Color.cyan)
                            .foregroundColor(.black)
                            .cornerRadius(12)
                        }
                    } else {
                        VStack(spacing: 8) {
                            Button(action: {
                                Task {
                                    syncManager.syncStatusMessage = "Syncing Fitbit Sleep & Metrics..."
                                    let calendar = Calendar.current
                                    
                                    for i in 0..<7 {
                                        if let date = calendar.date(byAdding: .day, value: -i, to: Date()) {
                                            _ = await fitbitService.syncSleep(for: date)
                                            _ = await fitbitService.syncActivityAndHeart(for: date)
                                        }
                                    }
                                    
                                    syncManager.syncStatusMessage = "Pushing metrics to Firestore..."
                                    await syncManager.performManualSync()
                                    syncManager.syncStatusMessage = "Fitbit Sync Completed!"
                                }
                            }) {
                                HStack {
                                    Image(systemName: "arrow.triangle.2.circlepath")
                                    Text("Sync Fitbit Sleep (Last 7 Days)")
                                        .fontWeight(.semibold)
                                    Spacer()
                                    Image(systemName: "bed.double.fill")
                                }
                                .padding()
                                .frame(maxWidth: .infinity)
                                .background(Color(white: 0.15))
                                .foregroundColor(.white)
                                .cornerRadius(12)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(Color.white.opacity(0.1), lineWidth: 1)
                                )
                            }
                            
                            Button("Unlink Account") {
                                fitbitService.unlink()
                            }
                            .font(.caption)
                            .foregroundColor(.red.opacity(0.8))
                            .padding(.top, 4)
                        }
                    }
                }
                .padding(.vertical, 4)
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
        .onAppear {
            syncManager.setupBackgroundSync()
        }
    }
}
