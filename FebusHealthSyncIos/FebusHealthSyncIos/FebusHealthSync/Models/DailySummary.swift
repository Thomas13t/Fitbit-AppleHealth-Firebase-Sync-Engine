import Foundation

struct DailySummary: Identifiable, Codable {
    var id: String { date } // yyyy-MM-dd
    let date: String
    
    let totalWorkouts: Int
    let runningWorkouts: Int
    let runningDistanceMeters: Double
    let walkingDistanceMeters: Double
    let cyclingDistanceMeters: Double
    let totalWorkoutDurationSeconds: Double
    let totalActiveEnergyKcal: Double
    let totalSteps: Int
    let avgHeartRate: Double?
    let restingHeartRate: Double?
    let respiratoryRate: Double?
    let heartRateVariabilityMs: Double?
    let oxygenSaturationPercent: Double?
    let bodyTemperatureCelsius: Double?
    let exerciseMinutes: Double?
    let flightsClimbed: Double?
    let sleepDurationSeconds: Double?
    
    let createdAt: Date
    let updatedAt: Date
    
    // Firestore conversion
    var dictionary: [String: Any] {
        var dict: [String: Any] = [
            "date": date,
            "totalWorkouts": totalWorkouts,
            "runningWorkouts": runningWorkouts,
            "runningDistanceMeters": runningDistanceMeters,
            "walkingDistanceMeters": walkingDistanceMeters,
            "cyclingDistanceMeters": cyclingDistanceMeters,
            "totalWorkoutDurationSeconds": totalWorkoutDurationSeconds,
            "totalActiveEnergyKcal": totalActiveEnergyKcal,
            "totalSteps": totalSteps,
            "createdAt": createdAt,
            "updatedAt": updatedAt
        ]
        
        if let avgHr = avgHeartRate { dict["avgHeartRate"] = avgHr }
        if let restHr = restingHeartRate { dict["restingHeartRate"] = restHr }
        if let respRate = respiratoryRate { dict["respiratoryRate"] = respRate }
        if let hrv = heartRateVariabilityMs { dict["heartRateVariabilityMs"] = hrv }
        if let oxygen = oxygenSaturationPercent { dict["oxygenSaturationPercent"] = oxygen }
        if let temp = bodyTemperatureCelsius { dict["bodyTemperatureCelsius"] = temp }
        if let minutes = exerciseMinutes { dict["exerciseMinutes"] = minutes }
        if let floors = flightsClimbed { dict["flightsClimbed"] = floors }
        if let sleepDur = sleepDurationSeconds { dict["sleepDurationSeconds"] = sleepDur }
        
        return dict
    }
}
