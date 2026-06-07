import Foundation
import HealthKit


// Clean up cached warnings
class HealthKitService {
    let healthStore = HKHealthStore()

    // Define the types we want to share (write)
    private let typesToShare: Set<HKSampleType> = {
        let categoryIdentifiers: [HKCategoryTypeIdentifier] = [.sleepAnalysis]
        let quantityIdentifiers: [HKQuantityTypeIdentifier] = [
            .stepCount, .heartRate, .restingHeartRate, .respiratoryRate,
            .heartRateVariabilitySDNN, .oxygenSaturation, .bodyTemperature,
            .activeEnergyBurned, .distanceWalkingRunning, .flightsClimbed
        ]
        var types = Set<HKSampleType>()
        categoryIdentifiers.compactMap { HKObjectType.categoryType(forIdentifier: $0) }.forEach { types.insert($0) }
        quantityIdentifiers.compactMap { HKObjectType.quantityType(forIdentifier: $0) }.forEach { types.insert($0) }
        types.insert(HKObjectType.workoutType())

        // Wrist temperature can only be read, not shared.
        return types
    }()

    // Define the types we want to read
    private let typesToRead: Set<HKObjectType> = {
        let categoryIdentifiers: [HKCategoryTypeIdentifier] = [.sleepAnalysis]
        let quantityIdentifiers: [HKQuantityTypeIdentifier] = [
            .stepCount, .heartRate, .restingHeartRate, .respiratoryRate,
            .heartRateVariabilitySDNN, .oxygenSaturation, .bodyTemperature,
            .appleExerciseTime, .flightsClimbed, .distanceWalkingRunning,
            .activeEnergyBurned, .vo2Max
        ]
        var types = Set<HKObjectType>()
        categoryIdentifiers.compactMap { HKObjectType.categoryType(forIdentifier: $0) }.forEach { types.insert($0) }
        quantityIdentifiers.compactMap { HKObjectType.quantityType(forIdentifier: $0) }.forEach { types.insert($0) }
        types.insert(HKObjectType.workoutType())

        if #available(iOS 16.0, *) {
            if let type = HKObjectType.quantityType(forIdentifier: .appleSleepingWristTemperature) {
                types.insert(type)
            }
        }
        return types
    }()

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

        // Respiratory Rate
        if let respiratoryType = HKObjectType.quantityType(forIdentifier: .respiratoryRate),
           let result = try? await fetchDailyQuantity(type: respiratoryType, start: start, end: end, options: .discreteAverage),
           let avg = result.averageQuantity() {
            stats.respiratoryRate = avg.doubleValue(for: HKUnit(from: "count/min"))
        }

        // HRV
        if let hrvType = HKObjectType.quantityType(forIdentifier: .heartRateVariabilitySDNN),
           let result = try? await fetchDailyQuantity(type: hrvType, start: start, end: end, options: .discreteAverage),
           let avg = result.averageQuantity() {
            stats.heartRateVariabilityMs = avg.doubleValue(for: .secondUnit(with: .milli))
        }

        // Oxygen Saturation
        if let oxygenType = HKObjectType.quantityType(forIdentifier: .oxygenSaturation),
           let result = try? await fetchDailyQuantity(type: oxygenType, start: start, end: end, options: .discreteAverage),
           let avg = result.averageQuantity() {
            stats.oxygenSaturationPercent = avg.doubleValue(for: .percent()) * 100.0
        }

        // Sleep/Skin Temperature imported as body temperature or sleeping wrist temperature
        if #available(iOS 16.0, *),
           let sleepTempType = HKObjectType.quantityType(forIdentifier: .appleSleepingWristTemperature),
           let result = try? await fetchDailyQuantity(type: sleepTempType, start: start, end: end, options: .discreteAverage),
           let avg = result.averageQuantity() {
            stats.bodyTemperatureCelsius = avg.doubleValue(for: .degreeCelsius())
        } else if let temperatureType = HKObjectType.quantityType(forIdentifier: .bodyTemperature),
           let result = try? await fetchDailyQuantity(type: temperatureType, start: start, end: end, options: .discreteAverage),
           let avg = result.averageQuantity() {
            stats.bodyTemperatureCelsius = avg.doubleValue(for: .degreeCelsius())
        }

        // Exercise minutes
        if let exerciseType = HKObjectType.quantityType(forIdentifier: .appleExerciseTime),
           let result = try? await fetchDailyQuantity(type: exerciseType, start: start, end: end, options: .cumulativeSum),
           let sum = result.sumQuantity() {
            stats.exerciseMinutes = sum.doubleValue(for: .minute())
        }

        // Flights climbed / floors
        if let floorsType = HKObjectType.quantityType(forIdentifier: .flightsClimbed),
           let result = try? await fetchDailyQuantity(type: floorsType, start: start, end: end, options: .cumulativeSum),
           let sum = result.sumQuantity() {
            stats.flightsClimbed = sum.doubleValue(for: .count())
        }

        // Sleep Duration
        if let sleepDuration = try? await fetchSleepDuration(start: start, end: end) {
            stats.totalSleepDurationSeconds = sleepDuration
        }

        return stats
    }

    func fetchSleepDuration(start: Date, end: Date) async throws -> Double {
        guard let sleepType = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) else { return 0.0 }
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
    var respiratoryRate: Double? = nil
    var heartRateVariabilityMs: Double? = nil
    var oxygenSaturationPercent: Double? = nil
    var bodyTemperatureCelsius: Double? = nil
    var exerciseMinutes: Double? = nil
    var flightsClimbed: Double? = nil
    var totalSleepDurationSeconds: Double? = nil
}
