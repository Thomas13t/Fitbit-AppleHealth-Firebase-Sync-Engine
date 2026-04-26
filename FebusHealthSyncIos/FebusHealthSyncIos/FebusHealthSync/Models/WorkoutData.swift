import Foundation
import HealthKit

struct WorkoutData: Identifiable, Codable {
    let id: String
    let sourceName: String
    let workoutActivityType: UInt
    let workoutActivityTypeName: String
    let startDate: Date
    let endDate: Date
    let durationSeconds: Double
    let totalDistanceMeters: Double?
    let totalEnergyBurnedKcal: Double?
    let metadata: [String: String]?

    let createdAt: Date
    let updatedAt: Date
    let syncedAt: Date

    var dictionary: [String: Any] {
        var dict: [String: Any] = [
            "id": id,
            "sourceName": sourceName,
            "workoutActivityType": workoutActivityType,
            "workoutActivityTypeName": workoutActivityTypeName,
            "startDate": startDate,
            "endDate": endDate,
            "durationSeconds": durationSeconds,
            "createdAt": createdAt,
            "updatedAt": updatedAt,
            "syncedAt": syncedAt
        ]

        if let dist = totalDistanceMeters {
            dict["totalDistanceMeters"] = dist
        }

        if let energy = totalEnergyBurnedKcal {
            dict["totalEnergyBurnedKcal"] = energy
        }

        if let meta = metadata {
            dict["metadata"] = meta
        }

        return dict
    }
}
