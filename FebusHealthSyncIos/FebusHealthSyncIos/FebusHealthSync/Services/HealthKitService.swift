import Foundation
import HealthKit
import Combine

class HealthKitService {
    let healthStore = HKHealthStore()
    
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
            throw NSError(
                domain: "HealthKitService",
                code: 0,
                userInfo: [NSLocalizedDescriptionKey: "HealthKit is not available on this device."]
            )
        }
        
        try await healthStore.requestAuthorization(toShare: [], read: typesToRead)
    }
    
    func fetchWorkouts(daysBack: Int) async throws -> [HKWorkout] {
        let calendar = Calendar.current
        let endDate = Date()
        
        guard let startDate = calendar.date(byAdding: .day, value: -daysBack, to: endDate) else {
            return []
        }
        
        let predicate = HKQuery.predicateForSamples(
            withStart: startDate,
            end: endDate,
            options: .strictStartDate
        )
        
        let sortDescriptor = NSSortDescriptor(
            key: HKSampleSortIdentifierEndDate,
            ascending: false
        )
        
        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: HKObjectType.workoutType(),
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [sortDescriptor]
            ) { _, samples, error in
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
        
        let query = HKObserverQuery(sampleType: workoutType, predicate: nil) { _, completionHandler, error in
            guard error == nil else {
                print("Observer query failed: \(error!.localizedDescription)")
                completionHandler()
                return
            }
            
            NotificationCenter.default.post(
                name: NSNotification.Name("HKWorkoutDataUpdated"),
                object: nil
            )
            
            completionHandler()
        }
        
        healthStore.execute(query)
        
        healthStore.enableBackgroundDelivery(for: workoutType, frequency: .immediate) { success, error in
            completion(success, error)
        }
    }
}

extension HKWorkoutActivityType {
    var name: String {
        switch self {
        case .running: return "running"
        case .walking: return "walking"
        case .cycling: return "cycling"
        case .traditionalStrengthTraining: return "strength_training"
        case .functionalStrengthTraining: return "functional_strength_training"
        case .yoga: return "yoga"
        case .hiking: return "hiking"
        case .swimming: return "swimming"
        case .coreTraining: return "core_training"
        case .elliptical: return "elliptical"
        case .other: return "other"
        default: return "unknown_\(self.rawValue)"
        }
    }
}
