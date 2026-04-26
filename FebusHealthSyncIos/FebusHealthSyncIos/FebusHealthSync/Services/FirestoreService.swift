import Foundation
import FirebaseFirestore
import FirebaseAuth
import Combine

class FirestoreService {
    private let db = Firestore.firestore()
    
    // MARK: - User Profile
    
    func updateUserProfile(user: User) async throws {
        let profile = UserProfile(
            email: user.email ?? "unknown@example.com",
            displayName: user.displayName,
            createdAt: user.metadata.creationDate ?? Date(),
            lastLoginAt: user.metadata.lastSignInDate ?? Date()
        )
        
        try await db.collection("users").document(user.uid).setData(profile.dictionary, merge: true)
    }
    
    // MARK: - Workouts
    
    func upsertWorkouts(userId: String, workouts: [WorkoutData]) async throws {
        let batch = db.batch()
        
        for workout in workouts {
            let ref = db.collection("users")
                .document(userId)
                .collection("workouts")
                .document(workout.id)
            
            batch.setData(workout.dictionary, forDocument: ref, merge: true)
        }
        
        try await batch.commit()
    }
    
    // MARK: - Daily Summaries
    
    func upsertDailySummary(userId: String, summary: DailySummary) async throws {
        let ref = db.collection("users")
            .document(userId)
            .collection("dailySummaries")
            .document(summary.id)
        
        try await ref.setData(summary.dictionary, merge: true)
    }
    
    // MARK: - Fetching Data
    
    func fetchRecentWorkouts(userId: String, limit: Int = 50) async throws -> [WorkoutData] {
        let snapshot = try await db.collection("users")
            .document(userId)
            .collection("workouts")
            .order(by: "endDate", descending: true)
            .limit(to: limit)
            .getDocuments()
            
        return snapshot.documents.compactMap { doc -> WorkoutData? in
            let data = doc.data()
            
            guard let id = data["id"] as? String,
                  let sourceName = data["sourceName"] as? String,
                  let startDateTs = data["startDate"] as? Timestamp,
                  let endDateTs = data["endDate"] as? Timestamp,
                  let durationSeconds = data["durationSeconds"] as? Double,
                  let createdAtTs = data["createdAt"] as? Timestamp,
                  let updatedAtTs = data["updatedAt"] as? Timestamp,
                  let syncedAtTs = data["syncedAt"] as? Timestamp else {
                return nil
            }
            
            let workoutActivityType: UInt
            if let value = data["workoutActivityType"] as? UInt {
                workoutActivityType = value
            } else if let value = data["workoutActivityType"] as? Int {
                workoutActivityType = UInt(value)
            } else if let value = data["workoutActivityType"] as? Int64 {
                workoutActivityType = UInt(value)
            } else {
                workoutActivityType = 0
            }
            
            return WorkoutData(
                id: id,
                sourceName: sourceName,
                workoutActivityType: workoutActivityType,
                workoutActivityTypeName: data["workoutActivityTypeName"] as? String ?? "unknown_\(workoutActivityType)",
                startDate: startDateTs.dateValue(),
                endDate: endDateTs.dateValue(),
                durationSeconds: durationSeconds,
                totalDistanceMeters: data["totalDistanceMeters"] as? Double,
                totalEnergyBurnedKcal: data["totalEnergyBurnedKcal"] as? Double,
                metadata: data["metadata"] as? [String: String],
                createdAt: createdAtTs.dateValue(),
                updatedAt: updatedAtTs.dateValue(),
                syncedAt: syncedAtTs.dateValue()
            )
        }
    }
}
