import Foundation
import HealthKit

class HealthKitService {
    let healthStore = HKHealthStore()
    
    // Define the types we want to read
    private let typesToRead: Set<HKObjectType> = [
        HKObjectType.workoutType(),
        HKObjectType.quantityType(forIdentifier: .heartRate)!,
        HKObjectType.quantityType(forIdentifier: .restingHeartRate)!,
        HKObjectType.quantityType(forIdentifier: .stepCount)!,
        HKObjectType.quantityType(forIdentifier: .distanceWalkingRunning)!,
        HKObjectType.quantityType(forIdentifier: .activeEnergyBurned)!,
        HKObjectType.quantityType(forIdentifier: .vo2Max)!
    ]
    
    func requestAuthorization() async throws {
        guard HKHealthStore.isHealthDataAvailable() else {
            throw NSError(domain: "HealthKitService", code: 0, userInfo: [NSLocalizedDescriptionKey: "HealthKit is not available on this device."])
        }
        try await healthStore.requestAuthorization(toShare: [], read: typesToRead)
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
        let query = HKObserverQuery(sampleType: workoutType, predicate: nil) { [weak self] query, completionHandler, error in
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
}
