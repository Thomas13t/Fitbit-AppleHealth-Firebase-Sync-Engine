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
                    if let respiratoryRate = summary.respiratoryRate, respiratoryRate > 0 {
                        HStack {
                            Image(systemName: "lungs.fill")
                                .foregroundColor(.teal)
                            Text("Respiratory Rate")
                            Spacer()
                            Text("\(respiratoryRate, specifier: "%.1f") br/min")
                                .fontWeight(.bold)
                        }
                    }
                    if let hrv = summary.heartRateVariabilityMs, hrv > 0 {
                        HStack {
                            Image(systemName: "waveform.path.ecg")
                                .foregroundColor(.pink)
                            Text("HRV")
                            Spacer()
                            Text("\(hrv, specifier: "%.0f") ms")
                                .fontWeight(.bold)
                        }
                    }
                    if let oxygen = summary.oxygenSaturationPercent, oxygen > 0 {
                        HStack {
                            Image(systemName: "drop.fill")
                                .foregroundColor(.blue)
                            Text("SpO2")
                            Spacer()
                            Text("\(oxygen, specifier: "%.1f")%")
                                .fontWeight(.bold)
                        }
                    }
                    if let temp = summary.bodyTemperatureCelsius, temp > 0 {
                        HStack {
                            Image(systemName: "thermometer.medium")
                                .foregroundColor(.orange)
                            Text("Sleep Temperature")
                            Spacer()
                            Text("\(temp, specifier: "%.1f") C")
                                .fontWeight(.bold)
                        }
                    }
                    if let exerciseMinutes = summary.exerciseMinutes, exerciseMinutes > 0 {
                        HStack {
                            Image(systemName: "figure.walk.motion")
                                .foregroundColor(.green)
                            Text("Exercise Minutes")
                            Spacer()
                            Text("\(Int(exerciseMinutes)) min")
                                .fontWeight(.bold)
                        }
                    }
                    if let floors = summary.flightsClimbed, floors > 0 {
                        HStack {
                            Image(systemName: "stairs")
                                .foregroundColor(.indigo)
                            Text("Floors")
                            Spacer()
                            Text("\(Int(floors))")
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

            Section("Google Health / Fitbit Integration") {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Image(systemName: "waveform.path.ecg")
                            .foregroundColor(.cyan)
                            .font(.title3)
                        Text("Google Health Connection")
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
                         ? "Your Google Health account is connected. Fitbit sleep, steps, and heart-rate data can sync directly to Apple Health."
                         : "Link Google Health to sync Fitbit sleep, steps, and heart-rate data into Apple Health.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    if !fitbitService.isLinked {
                        Button(action: {
                            fitbitService.authorize()
                        }) {
                            HStack {
                                Spacer()
                                Text("Link Google Health")
                                    .fontWeight(.semibold)
                                Spacer()
                            }
                            .padding()
                            .background(Color.cyan)
                            .foregroundColor(.black)
                            .cornerRadius(12)
                        }
                        .buttonStyle(.plain)
                    } else {
                        VStack(spacing: 8) {
                            Button(action: {
                                guard fitbitService.accessToken != nil else {
                                    syncManager.syncStatusMessage = "Reconnect Google Health to sync data."
                                    fitbitService.statusMessage = "Reconnect Google Health to sync data."
                                    return
                                }

                                Task {
                                    await syncManager.performManualSync()
                                    fitbitService.statusMessage = "Last Google Health sync completed."
                                }
                            }) {
                                HStack {
                                    Image(systemName: "arrow.triangle.2.circlepath")
                                    Text("Sync Google Health Data (Last 7 Days)")
                                        .fontWeight(.semibold)
                                    Spacer()
                                    Image(systemName: "heart.text.square.fill")
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
                            .buttonStyle(.plain)

                            Button("Unlink Google Health") {
                                fitbitService.unlink()
                            }
                            .font(.caption)
                            .foregroundColor(.red.opacity(0.8))
                            .padding(.top, 4)
                            .buttonStyle(.plain)
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
