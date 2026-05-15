import Foundation
import HealthKit
import Combine
import FirebaseAuth
@MainActor
class SyncManager: ObservableObject {
    @Published var isSyncing: Bool = false
    @Published var lastSyncTime: Date?
    @Published var syncStatusMessage: String = "Idle"
    @Published var syncedWorkoutsCount: Int = 0
    @Published var syncLogs: [String] = []
    @Published var todaySummary: DailySummary?
    
    
    let healthKitService: HealthKitService
    private let firestoreService: FirestoreService
    private let authService: AuthService
    
    init(healthKitService: HealthKitService, firestoreService: FirestoreService, authService: AuthService) {
        self.healthKitService = healthKitService
        self.firestoreService = firestoreService
        self.authService = authService
        
        NotificationCenter.default.addObserver(self, selector: #selector(handleBackgroundSync), name: NSNotification.Name("HKWorkoutDataUpdated"), object: nil)
    }
    
    private func log(_ message: String) {
        let timestamp = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
        let logMsg = "[\(timestamp)] \(message)"
        syncLogs.insert(logMsg, at: 0)
        syncStatusMessage = message
        print(logMsg)
    }
    
    func setupBackgroundSync() {
        healthKitService.setupBackgroundDelivery { [weak self] success, error in
            DispatchQueue.main.async {
                if success {
                    self?.log("Background delivery enabled.")
                } else if let error = error {
                    self?.log("Background delivery failed: \(error.localizedDescription)")
                }
            }
        }
    }
    
    @objc private func handleBackgroundSync() {
        Task {
            log("Background sync triggered via HealthKit observer.")
            await performSync(daysBack: 1) // Just recent ones for background sync
        }
    }
    
    func performManualSync() async {
        log("Manual sync started.")
        await performSync(daysBack: 30)
    }
    
    private func performSync(daysBack: Int) async {
        guard let user = authService.currentUser else {
            log("Sync failed: No authenticated user.")
            return
        }
        
        isSyncing = true
        defer { isSyncing = false }
        
        do {
            log("Fetching workouts from HealthKit...")
            let hkWorkouts = try await healthKitService.fetchWorkouts(daysBack: daysBack)
            log("Found \(hkWorkouts.count) workouts in HealthKit.")
            
            let workoutDataArray = hkWorkouts.map { workout -> WorkoutData in
                return WorkoutData(
                    id: workout.uuid.uuidString,
                    sourceName: workout.sourceRevision.source.name,
                    workoutActivityType: workout.workoutActivityType.rawValue,
                    startDate: workout.startDate,
                    endDate: workout.endDate,
                    durationSeconds: workout.duration,
                    totalDistanceMeters: workout.totalDistance?.doubleValue(for: HKUnit.meter()),
                    totalEnergyBurnedKcal: workout.statistics(for: HKObjectType.quantityType(forIdentifier: .activeEnergyBurned)!)?.sumQuantity()?.doubleValue(for: HKUnit.kilocalorie()),
                    metadata: workout.metadata as? [String: String],
                    createdAt: Date(),
                    updatedAt: Date(),
                    syncedAt: Date()
                )
            }
            
            if !workoutDataArray.isEmpty {
                log("Uploading to Firestore...")
                try await firestoreService.upsertWorkouts(userId: user.uid, workouts: workoutDataArray)
                syncedWorkoutsCount += workoutDataArray.count
            }
            
            let calendar = Calendar.current
            log("Fetching daily summaries for the last \(daysBack) days...")
            for i in 0...daysBack {
                guard let targetDate = calendar.date(byAdding: .day, value: -i, to: Date()) else { continue }
                
                let stats = await healthKitService.fetchDailyQuantityStats(for: targetDate)
                let dateString = formatDate(targetDate)
                
                let dayWorkouts = workoutDataArray.filter { calendar.isDate($0.startDate, inSameDayAs: targetDate) }
                
                let runningWorkouts = dayWorkouts.filter { $0.workoutActivityType == 37 } // Running
                let totalWorkoutDuration = dayWorkouts.reduce(0) { $0 + $1.durationSeconds }
                let runningDistance = runningWorkouts.compactMap { $0.totalDistanceMeters }.reduce(0, +)
                let cyclingDistance = dayWorkouts.filter { $0.workoutActivityType == 13 }.compactMap { $0.totalDistanceMeters }.reduce(0, +)
                
                let summary = DailySummary(
                    date: dateString,
                    totalWorkouts: dayWorkouts.count,
                    runningWorkouts: runningWorkouts.count,
                    runningDistanceMeters: runningDistance,
                    walkingDistanceMeters: stats.walkingDistanceMeters,
                    cyclingDistanceMeters: cyclingDistance,
                    totalWorkoutDurationSeconds: totalWorkoutDuration,
                    totalActiveEnergyKcal: stats.totalActiveEnergyKcal,
                    totalSteps: stats.totalSteps,
                    avgHeartRate: stats.avgHeartRate,
                    restingHeartRate: stats.restingHeartRate,
                    createdAt: Date(),
                    updatedAt: Date()
                )
                
                try await firestoreService.upsertDailySummary(userId: user.uid, summary: summary)
                
                if i == 0 {
                    DispatchQueue.main.async {
                        self.todaySummary = summary
                    }
                }
            }
            
            lastSyncTime = Date()
            log("Sync completed successfully.")
            
        } catch {
            log("Sync Error: \(error.localizedDescription)")
        }
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}
