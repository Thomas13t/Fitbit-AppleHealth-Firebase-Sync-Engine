import Foundation
import HealthKit


// Clean up cached warnings
class HealthKitService {
    let healthStore = HKHealthStore()
    
    // Define the types we want to share (write)
    private let typesToShare: Set<HKSampleType> = [
        HKObjectType.categoryType(forIdentifier: .sleepAnalysis)!
    ]
    
    // Define the types we want to read
    private let typesToRead: Set<HKObjectType> = [
        HKObjectType.workoutType(),
        HKObjectType.quantityType(forIdentifier: .heartRate)!,
        HKObjectType.quantityType(forIdentifier: .restingHeartRate)!,
        HKObjectType.quantityType(forIdentifier: .stepCount)!,
        HKObjectType.quantityType(forIdentifier: .distanceWalkingRunning)!,
        HKObjectType.quantityType(forIdentifier: .activeEnergyBurned)!,
        HKObjectType.quantityType(forIdentifier: .vo2Max)!,
        HKObjectType.categoryType(forIdentifier: .sleepAnalysis)!
    ]
    
    func requestAuthorization() async throws {
        guard HKHealthStore.isHealthDataAvailable() else {
            throw NSError(domain: "HealthKitService", code: 0, userInfo: [NSLocalizedDescriptionKey: "HealthKit is not available on this device."])
        }
        try await healthStore.requestAuthorization(toShare: typesToShare, read: typesToRead)
    }
    
    func fetchWorkouts(daysBack: Int) async throws -> [HKWorkout] {
        let calendar = Calendar.current
        let endDate = Date()
        guard let startDate = calendar.date(byAdding: .day, value: -daysBack, to: endDate) else {
            return []
        }
        
        let predicate = HKQuery.predicateForSamples(withStart: startDate, end: endDate, options: .strictStartDate)
        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)
        
        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(sampleType: HKObjectType.workoutType(), predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: [sortDescriptor]) { _, samples, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }
                
                let workouts = samples as? [HKWorkout] ?? []
                continuation.resume(returning: workouts)
            }
            healthStore.execute(query)
        }
    }
    
    func setupBackgroundDelivery(completion: @escaping (Bool, Error?) -> Void) {
        let workoutType = HKObjectType.workoutType()
        
        // Register observer query
        let query = HKObserverQuery(sampleType: workoutType, predicate: nil) { _, completionHandler, error in
            guard error == nil else {
                print("Observer query failed: \(error!.localizedDescription)")
                return
            }
            // Trigger sync manager to fetch new workouts
            NotificationCenter.default.post(name: NSNotification.Name("HKWorkoutDataUpdated"), object: nil)
            
            // Must call completion handler
            completionHandler()
        }
        
        healthStore.execute(query)
        
        // Enable background delivery
        healthStore.enableBackgroundDelivery(for: workoutType, frequency: .immediate) { success, error in
            completion(success, error)
        }
    }
    
    // MARK: - Daily Quantity Fetching
    
    func fetchDailyQuantity(type: HKQuantityType, start: Date, end: Date, options: HKStatisticsOptions) async throws -> HKStatistics? {
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
        return try await withCheckedThrowingContinuation { continuation in
            let query = HKStatisticsQuery(quantityType: type, quantitySamplePredicate: predicate, options: options) { _, statistics, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }
                continuation.resume(returning: statistics)
            }
            healthStore.execute(query)
        }
    }
    
    func fetchDailyQuantityStats(for date: Date) async -> DailyQuantityStats {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: date)
        guard let end = calendar.date(byAdding: .day, value: 1, to: start) else { return DailyQuantityStats() }
        
        var stats = DailyQuantityStats()
        
        // Steps
        if let stepType = HKObjectType.quantityType(forIdentifier: .stepCount),
           let result = try? await fetchDailyQuantity(type: stepType, start: start, end: end, options: .cumulativeSum),
           let sum = result.sumQuantity() {
            stats.totalSteps = Int(sum.doubleValue(for: HKUnit.count()))
        }
        
        // Active Energy
        if let energyType = HKObjectType.quantityType(forIdentifier: .activeEnergyBurned),
           let result = try? await fetchDailyQuantity(type: energyType, start: start, end: end, options: .cumulativeSum),
           let sum = result.sumQuantity() {
            stats.totalActiveEnergyKcal = sum.doubleValue(for: HKUnit.kilocalorie())
        }
        
        // Walking Distance
        if let distType = HKObjectType.quantityType(forIdentifier: .distanceWalkingRunning),
           let result = try? await fetchDailyQuantity(type: distType, start: start, end: end, options: .cumulativeSum),
           let sum = result.sumQuantity() {
            stats.walkingDistanceMeters = sum.doubleValue(for: HKUnit.meter())
        }
        
        // Avg HR
        if let hrType = HKObjectType.quantityType(forIdentifier: .heartRate),
           let result = try? await fetchDailyQuantity(type: hrType, start: start, end: end, options: .discreteAverage),
           let avg = result.averageQuantity() {
            stats.avgHeartRate = avg.doubleValue(for: HKUnit(from: "count/min"))
        }
        
        // Resting HR
        if let restHrType = HKObjectType.quantityType(forIdentifier: .restingHeartRate),
           let result = try? await fetchDailyQuantity(type: restHrType, start: start, end: end, options: .discreteAverage),
           let avg = result.averageQuantity() {
            stats.restingHeartRate = avg.doubleValue(for: HKUnit(from: "count/min"))
        }
        
        // Sleep Duration
        if let sleepDuration = try? await fetchSleepDuration(start: start, end: end) {
            stats.totalSleepDurationSeconds = sleepDuration
        }
        
        return stats
    }
    
    func fetchSleepDuration(start: Date, end: Date) async throws -> Double {
        let sleepType = HKObjectType.categoryType(forIdentifier: .sleepAnalysis)!
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
        
        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(sampleType: sleepType, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, samples, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }
                
                let sleepSamples = samples as? [HKCategorySample] ?? []
                let totalDuration = sleepSamples
                    .filter { sample in
                        let val = sample.value
                        return val != HKCategoryValueSleepAnalysis.inBed.rawValue && val != HKCategoryValueSleepAnalysis.awake.rawValue
                    }
                    .reduce(0.0) { $0 + $1.endDate.timeIntervalSince($1.startDate) }
                
                continuation.resume(returning: totalDuration)
            }
            healthStore.execute(query)
        }
    }
}

struct DailyQuantityStats {
    var totalSteps: Int = 0
    var totalActiveEnergyKcal: Double = 0
    var walkingDistanceMeters: Double = 0
    var avgHeartRate: Double? = nil
    var restingHeartRate: Double? = nil
    var totalSleepDurationSeconds: Double? = nil
}

