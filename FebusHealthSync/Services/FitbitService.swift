import Foundation
import AuthenticationServices
import HealthKit
import UIKit
import Combine
import FirebaseCore

enum GoogleHealthSyncError: Error {
    case unauthorized
}

class FitbitService: NSObject, ObservableObject {
    @Published var isLinked: Bool = false
    @Published var statusMessage: String = "Not Connected"
    
    private let healthStore = HKHealthStore()
    
    private let userDefaultsKeyToken = "google_health_access_token"
    private let userDefaultsKeyRefreshToken = "google_health_refresh_token"
    
    private let googleHealthScopes = [
        "https://www.googleapis.com/auth/googlehealth.activity_and_fitness.readonly",
        "https://www.googleapis.com/auth/googlehealth.health_metrics_and_measurements.readonly",
        "https://www.googleapis.com/auth/googlehealth.sleep.readonly"
    ]
    
    private let writeTypes: Set<HKSampleType> = {
        var types: Set<HKSampleType> = [
            HKObjectType.categoryType(forIdentifier: .sleepAnalysis)!,
            HKObjectType.quantityType(forIdentifier: .stepCount)!,
            HKObjectType.quantityType(forIdentifier: .heartRate)!,
            HKObjectType.quantityType(forIdentifier: .restingHeartRate)!,
            HKObjectType.quantityType(forIdentifier: .respiratoryRate)!,
            HKObjectType.quantityType(forIdentifier: .heartRateVariabilitySDNN)!,
            HKObjectType.quantityType(forIdentifier: .oxygenSaturation)!,
            HKObjectType.quantityType(forIdentifier: .bodyTemperature)!,
            HKObjectType.quantityType(forIdentifier: .activeEnergyBurned)!,
            HKObjectType.quantityType(forIdentifier: .distanceWalkingRunning)!,
            HKObjectType.quantityType(forIdentifier: .flightsClimbed)!,
            HKObjectType.workoutType()
        ]
        if #available(iOS 16.0, *) {
            if let type = HKObjectType.quantityType(forIdentifier: .appleSleepingWristTemperature) {
                types.insert(type)
            }
        }
        return types
    }()
    
    private let readTypes: Set<HKObjectType> = {
        var types: Set<HKObjectType> = [
            HKObjectType.categoryType(forIdentifier: .sleepAnalysis)!,
            HKObjectType.quantityType(forIdentifier: .stepCount)!,
            HKObjectType.quantityType(forIdentifier: .heartRate)!,
            HKObjectType.quantityType(forIdentifier: .restingHeartRate)!,
            HKObjectType.quantityType(forIdentifier: .respiratoryRate)!,
            HKObjectType.quantityType(forIdentifier: .heartRateVariabilitySDNN)!,
            HKObjectType.quantityType(forIdentifier: .oxygenSaturation)!,
            HKObjectType.quantityType(forIdentifier: .bodyTemperature)!,
            HKObjectType.quantityType(forIdentifier: .appleExerciseTime)!,
            HKObjectType.quantityType(forIdentifier: .activeEnergyBurned)!,
            HKObjectType.quantityType(forIdentifier: .distanceWalkingRunning)!,
            HKObjectType.quantityType(forIdentifier: .flightsClimbed)!,
            HKObjectType.workoutType()
        ]
        if #available(iOS 16.0, *) {
            if let type = HKObjectType.quantityType(forIdentifier: .appleSleepingWristTemperature) {
                types.insert(type)
            }
        }
        return types
    }()
    
    override init() {
        super.init()
        self.isLinked = (accessToken != nil)
        self.statusMessage = isLinked ? "Connected to Google Health" : "Not Connected"
    }
    
    var accessToken: String? {
        get { UserDefaults.standard.string(forKey: userDefaultsKeyToken) }
        set { UserDefaults.standard.set(newValue, forKey: userDefaultsKeyToken) }
    }
    
    var refreshToken: String? {
        get { UserDefaults.standard.string(forKey: userDefaultsKeyRefreshToken) }
        set { UserDefaults.standard.set(newValue, forKey: userDefaultsKeyRefreshToken) }
    }
    
    func unlink() {
        UserDefaults.standard.removeObject(forKey: userDefaultsKeyToken)
        UserDefaults.standard.removeObject(forKey: userDefaultsKeyRefreshToken)
        isLinked = false
        statusMessage = "Not Connected"
    }
    
    func authorize() {
        guard let clientId = googleClientID,
              let redirectUri = googleOAuthRedirectURI,
              let callbackScheme = googleOAuthCallbackScheme else {
            statusMessage = "Missing Google Client ID. Configure Firebase first."
            return
        }
        
        // Construct the Google OAuth 2.0 URL
        var urlComponents = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")!
        urlComponents.queryItems = [
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "client_id", value: clientId),
            URLQueryItem(name: "redirect_uri", value: redirectUri),
            URLQueryItem(name: "scope", value: googleHealthScopes.joined(separator: " ")),
            URLQueryItem(name: "access_type", value: "offline"), // Offline access to get the Refresh Token
            URLQueryItem(name: "prompt", value: "consent")
        ]
        
        guard let authURL = urlComponents.url else {
            self.statusMessage = "Invalid Auth URL"
            return
        }
        
        let session = ASWebAuthenticationSession(url: authURL, callbackURLScheme: callbackScheme) { [weak self] callbackURL, error in
            guard error == nil else {
                DispatchQueue.main.async {
                    self?.statusMessage = "Authentication cancelled or failed."
                }
                return
            }
            
            if let callbackURL = callbackURL,
               let queryItems = URLComponents(string: callbackURL.absoluteString)?.queryItems,
               let code = queryItems.first(where: { $0.name == "code" })?.value {
                self?.exchangeCodeForToken(code)
            }
        }
        
        session.presentationContextProvider = self
        session.prefersEphemeralWebBrowserSession = false
        session.start()
    }
    
    private func exchangeCodeForToken(_ code: String) {
        guard let tokenURL = URL(string: "https://oauth2.googleapis.com/token"),
              let clientId = googleClientID,
              let redirectUri = googleOAuthRedirectURI else { return }
        
        var request = URLRequest(url: tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        
        let bodyComponents = [
            "client_id": clientId,
            "grant_type": "authorization_code",
            "redirect_uri": redirectUri,
            "code": code
        ]
        
        request.httpBody = formEncodedBody(bodyComponents)
        
        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            if let error = error {
                DispatchQueue.main.async { self?.statusMessage = "Exchange failed: \(error.localizedDescription)" }
                return
            }
            
            guard let data = data else { return }
            do {
                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let accessToken = json["access_token"] as? String {
                    
                    let refreshToken = json["refresh_token"] as? String // Offline access gives us this
                    
                    DispatchQueue.main.async {
                        self?.accessToken = accessToken
                        if let refresh = refreshToken {
                            self?.refreshToken = refresh
                        }
                        self?.isLinked = true
                        self?.statusMessage = "Connected to Google Health!"
                    }
                } else {
                    DispatchQueue.main.async { self?.statusMessage = "Invalid token response." }
                }
            } catch {
                DispatchQueue.main.async { self?.statusMessage = "Parsing token failed." }
            }
        }.resume()
    }
    
    func syncSleep(for date: Date) async -> (success: Bool, message: String) {
        guard let token = accessToken else {
            return (false, "Not linked.")
        }
        
        do {
            try await requestHealthWriteAuthorization()
        } catch {
            return (false, "Apple Health write permission failed: \(error.localizedDescription)")
        }
        
        return await syncGoogleHealthSleep(for: date, token: token)
    }
    
    private func syncLegacyGoogleFitSleep(for date: Date, token: String) async -> (success: Bool, message: String) {
        
        // Define a "sleep night" range: 18:00 (6 PM) of the previous day to 12:00 (12 PM) of target date
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: date)
        
        guard let sleepStart = calendar.date(byAdding: .hour, value: -6, to: startOfDay),
              let sleepEnd = calendar.date(byAdding: .hour, value: 12, to: startOfDay) else {
            return (false, "Invalid date calculations.")
        }
        
        let startTimeMillis = Int64(sleepStart.timeIntervalSince1970 * 1000)
        let endTimeMillis = Int64(sleepEnd.timeIntervalSince1970 * 1000)
        
        // 1. Try Granular Sleep Segment Aggregation first
        guard let aggregateURL = URL(string: "https://www.googleapis.com/fitness/v1/users/me/dataset:aggregate") else {
            return (false, "Invalid aggregate URL.")
        }
        
        var request = URLRequest(url: aggregateURL)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body: [String: Any] = [
            "aggregateBy": [
                ["dataTypeName": "com.google.sleep.segment"]
            ],
            "startTimeMillis": startTimeMillis,
            "endTimeMillis": endTimeMillis
        ]
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            let (data, response) = try await URLSession.shared.data(for: request)
            
            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 401 {
                let refreshed = await refreshAccessToken()
                if refreshed {
                    return await syncSleep(for: date)
                } else {
                    return (false, "Session expired. Please relink.")
                }
            }
            
            let result = try await parseAndSaveSleepAggregateData(data)
            if result.success && result.message != "No new sleep data to import." && !result.message.contains("No sleep") {
                return result
            }
            
            // If aggregate imported nothing or was empty, fall back to high-level sessions query
            return try await fallbackSyncSessions(startTimeMillis: startTimeMillis, endTimeMillis: endTimeMillis, token: token)
        } catch {
            // In case of any error, fall back to high-level sessions
            return (try? await fallbackSyncSessions(startTimeMillis: startTimeMillis, endTimeMillis: endTimeMillis, token: token)) ?? (false, "Error: \(error.localizedDescription)")
        }
    }
    
    private func refreshAccessToken() async -> Bool {
        guard let refresh = refreshToken,
              let tokenURL = URL(string: "https://oauth2.googleapis.com/token"),
              let clientId = googleClientID else { return false }
        
        var request = URLRequest(url: tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        
        let bodyComponents = [
            "client_id": clientId,
            "grant_type": "refresh_token",
            "refresh_token": refresh
        ]
        
        request.httpBody = formEncodedBody(bodyComponents)
        
        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let newAccess = json["access_token"] as? String {
                
                await MainActor.run {
                    self.accessToken = newAccess
                    if let newRefresh = json["refresh_token"] as? String {
                        self.refreshToken = newRefresh
                    }
                    self.isLinked = true
                }
                return true
            }
        } catch {}
        
        await MainActor.run {
            self.statusMessage = "Fitbit session expired. Reconnect to sync."
        }
        return false
    }
    
    private func sleepSampleExists(start: Date, end: Date, value: Int) async -> Bool {
        let sleepType = HKObjectType.categoryType(forIdentifier: .sleepAnalysis)!
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
        
        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(sampleType: sleepType, predicate: predicate, limit: 1, sortDescriptors: nil) { _, samples, _ in
                let existing = samples as? [HKCategorySample] ?? []
                let match = existing.contains { $0.startDate == start && $0.endDate == end && $0.value == value }
                continuation.resume(returning: match)
            }
            healthStore.execute(query)
        }
    }
    
    private func parseAndSaveSleepAggregateData(_ data: Data) async throws -> (success: Bool, message: String) {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let buckets = json["bucket"] as? [[String: Any]] else {
            return (false, "Could not parse Google Fit sleep aggregate.")
        }
        
        let sleepType = HKObjectType.categoryType(forIdentifier: .sleepAnalysis)!
        var samplesToSave: [HKCategorySample] = []
        var sessionStart: Date?
        var sessionEnd: Date?
        
        for bucket in buckets {
            guard let datasets = bucket["dataset"] as? [[String: Any]] else { continue }
            
            for dataset in datasets {
                guard let points = dataset["point"] as? [[String: Any]] else { continue }
                
                for point in points {
                    guard let startTimeNanosStr = point["startTimeNanos"] as? String,
                          let endTimeNanosStr = point["endTimeNanos"] as? String,
                          let startTimeNanos = Double(startTimeNanosStr),
                          let endTimeNanos = Double(endTimeNanosStr),
                          let values = point["value"] as? [[String: Any]], !values.isEmpty,
                          let fitbitSleepValue = values[0]["intVal"] as? Int else {
                        continue
                    }
                    
                    let startDate = Date(timeIntervalSince1970: startTimeNanos / 1_000_000_000.0)
                    let endDate = Date(timeIntervalSince1970: endTimeNanos / 1_000_000_000.0)
                    
                    // Map Google Fit/Fitbit sleep values to HealthKit sleep analysis values
                    let hkSleepValue: Int
                    switch fitbitSleepValue {
                    case 0: // Unspecified
                        hkSleepValue = HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue
                    case 1: // Awake
                        hkSleepValue = HKCategoryValueSleepAnalysis.awake.rawValue
                    case 2: // Sleeping (generic)
                        hkSleepValue = HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue
                    case 3: // Out of bed (user is awake)
                        hkSleepValue = HKCategoryValueSleepAnalysis.awake.rawValue
                    case 4: // Light sleep
                        hkSleepValue = HKCategoryValueSleepAnalysis.asleepCore.rawValue
                    case 5: // Deep sleep
                        hkSleepValue = HKCategoryValueSleepAnalysis.asleepDeep.rawValue
                    case 6: // REM sleep
                        hkSleepValue = HKCategoryValueSleepAnalysis.asleepREM.rawValue
                    default:
                        hkSleepValue = HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue
                    }
                    if hkSleepValue != HKCategoryValueSleepAnalysis.awake.rawValue {
                        sessionStart = minDate(sessionStart, startDate)
                        sessionEnd = maxDate(sessionEnd, endDate)
                    }
                    
                    // De-duplication check
                    let exists = await sleepSampleExists(start: startDate, end: endDate, value: hkSleepValue)
                    if !exists {
                        let sample = HKCategorySample(
                            type: sleepType,
                            value: hkSleepValue,
                            start: startDate,
                            end: endDate,
                            metadata: [HKMetadataKeyWasUserEntered: false]
                        )
                        samplesToSave.append(sample)
                    }
                }
            }
        }
        
        if let start = sessionStart, let end = sessionEnd {
            let inBedExists = await sleepSampleExists(start: start, end: end, value: HKCategoryValueSleepAnalysis.inBed.rawValue)
            if !inBedExists {
                samplesToSave.append(
                    HKCategorySample(
                        type: sleepType,
                        value: HKCategoryValueSleepAnalysis.inBed.rawValue,
                        start: start,
                        end: end,
                        metadata: fitbitImportMetadata
                    )
                )
            }
        }
        
        if !samplesToSave.isEmpty {
            try await healthStore.save(samplesToSave)
            let verification = try await verifySleepSamples(start: sessionStart ?? samplesToSave[0].startDate, end: sessionEnd ?? samplesToSave[0].endDate)
            return (true, "Saved \(samplesToSave.count) sleep records to Apple Health; verified \(verification.count) records / \(formatDuration(verification.asleepSeconds)) asleep.")
        }
        
        if let start = sessionStart, let end = sessionEnd {
            let verification = try await verifySleepSamples(start: start, end: end)
            return (true, "No new sleep data to import; HealthKit already has \(verification.count) records / \(formatDuration(verification.asleepSeconds)) asleep.")
        }
        
        return (true, "No sleep stage points returned by Google Health.")
    }
    
    private func fallbackSyncSessions(startTimeMillis: Int64, endTimeMillis: Int64, token: String) async throws -> (success: Bool, message: String) {
        let formatter = ISO8601DateFormatter()
        let startDate = Date(timeIntervalSince1970: Double(startTimeMillis) / 1000.0)
        let endDate = Date(timeIntervalSince1970: Double(endTimeMillis) / 1000.0)
        let startTimeStr = formatter.string(from: startDate)
        let endTimeStr = formatter.string(from: endDate)
        
        var components = URLComponents(string: "https://www.googleapis.com/fitness/v1/users/me/sessions")!
        components.queryItems = [
            URLQueryItem(name: "startTime", value: startTimeStr),
            URLQueryItem(name: "endTime", value: endTimeStr),
            URLQueryItem(name: "activityType", value: "72") // 72 = Sleep
        ]
        
        guard let url = components.url else {
            return (false, "Invalid fallback sessions URL.")
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 401 {
            return (false, "Unauthorized fallback session.")
        }
        
        return try await parseAndSaveSleepData(data)
    }

    private func parseAndSaveSleepData(_ data: Data) async throws -> (success: Bool, message: String) {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let sessions = json["session"] as? [[String: Any]] else {
            return (false, "Could not parse Google Fit Sessions.")
        }
        
        if sessions.isEmpty {
            return (true, "No sleep sessions found on Google Health.")
        }
        
        let sleepType = HKObjectType.categoryType(forIdentifier: .sleepAnalysis)!
        var samples: [HKCategorySample] = []
        
        for session in sessions {
            guard let startTimeMillisStr = session["startTimeMillis"] as? String,
                  let endTimeMillisStr = session["endTimeMillis"] as? String,
                  let startTimeMillis = Double(startTimeMillisStr),
                  let endTimeMillis = Double(endTimeMillisStr) else {
                continue
            }
            
            let startDate = Date(timeIntervalSince1970: startTimeMillis / 1000.0)
            let endDate = Date(timeIntervalSince1970: endTimeMillis / 1000.0)
            
            let inBedExists = await sleepSampleExists(start: startDate, end: endDate, value: HKCategoryValueSleepAnalysis.inBed.rawValue)
            if !inBedExists {
                samples.append(
                    HKCategorySample(
                        type: sleepType,
                        value: HKCategoryValueSleepAnalysis.inBed.rawValue,
                        start: startDate,
                        end: endDate,
                        metadata: fitbitImportMetadata
                    )
                )
            }
            
            let exists = await sleepSampleExists(start: startDate, end: endDate, value: HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue)
            if !exists {
                let sample = HKCategorySample(
                    type: sleepType,
                    value: HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue,
                    start: startDate,
                    end: endDate,
                    metadata: [HKMetadataKeyWasUserEntered: false]
                )
                samples.append(sample)
            }
        }
        
        if !samples.isEmpty {
            try await healthStore.save(samples)
            let start = samples.map(\.startDate).min() ?? Date()
            let end = samples.map(\.endDate).max() ?? Date()
            let verification = try await verifySleepSamples(start: start, end: end)
            return (true, "Saved \(samples.count) sleep session records to Apple Health; verified \(verification.count) records / \(formatDuration(verification.asleepSeconds)) asleep.")
        }
        
        return (true, "No new sleep sessions to import.")
    }
    
    func syncActivityAndHeart(for date: Date) async -> (success: Bool, message: String) {
        guard let token = accessToken else {
            return (false, "Not linked.")
        }
        
        do {
            try await requestHealthWriteAuthorization()
        } catch {
            return (false, "Apple Health write permission failed: \(error.localizedDescription)")
        }
        
        return await syncGoogleHealthActivityAndHeart(for: date, token: token)
    }
    
    private func syncLegacyGoogleFitActivityAndHeart(for date: Date, token: String) async -> (success: Bool, message: String) {
        
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: date)
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay)!
        
        let startTimeMillis = Int64(startOfDay.timeIntervalSince1970 * 1000)
        let endTimeMillis = Int64(endOfDay.timeIntervalSince1970 * 1000)
        
        guard let aggregateURL = URL(string: "https://www.googleapis.com/fitness/v1/users/me/dataset:aggregate") else {
            return (false, "Invalid endpoint URL.")
        }
        
        var request = URLRequest(url: aggregateURL)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body: [String: Any] = [
            "aggregateBy": [
                ["dataTypeName": "com.google.step_count.delta", "dataSourceId": "derived:com.google.step_count.delta:com.google.android.gms:estimated_steps"],
                ["dataTypeName": "com.google.heart_rate.bpm", "dataSourceId": "derived:com.google.heart_rate.bpm:com.google.android.gms:merge_heart_rate_bpm"]
            ],
            "bucketByTime": ["durationMillis": 86400000],
            "startTimeMillis": startTimeMillis,
            "endTimeMillis": endTimeMillis
        ]
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            let (data, response) = try await URLSession.shared.data(for: request)
            
            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 401 {
                let refreshed = await refreshAccessToken()
                if refreshed {
                    return await syncActivityAndHeart(for: date)
                } else {
                    return (false, "Session expired. Please relink.")
                }
            }
            
            return try await parseAndSaveActivityAndHeart(data, start: startOfDay, end: endOfDay)
        } catch {
            return (false, "Error: \(error.localizedDescription)")
        }
    }
    
    private func parseAndSaveActivityAndHeart(_ data: Data, start: Date, end: Date) async throws -> (success: Bool, message: String) {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let buckets = json["bucket"] as? [[String: Any]] else {
            return (false, "Could not parse Google Fitness aggregates.")
        }
        
        var stepsSaved = false
        var hrSaved = false
        
        for bucket in buckets {
            guard let datasets = bucket["dataset"] as? [[String: Any]] else { continue }
            
            for dataset in datasets {
                guard let dataSourceId = dataset["dataSourceId"] as? String,
                      let points = dataset["point"] as? [[String: Any]] else { continue }
                
                for point in points {
                    guard let values = point["value"] as? [[String: Any]], !values.isEmpty else { continue }
                    
                    if dataSourceId.contains("step_count") {
                        if let intVal = values[0]["intVal"] as? Int {
                            let stepType = HKObjectType.quantityType(forIdentifier: .stepCount)!
                            let exists = await quantitySampleExists(type: stepType, start: start, end: end)
                            if !exists {
                                let stepQuantity = HKQuantity(unit: HKUnit.count(), doubleValue: Double(intVal))
                                let sample = HKQuantitySample(
                                    type: stepType,
                                    quantity: stepQuantity,
                                    start: start,
                                    end: end,
                                    metadata: [HKMetadataKeyWasUserEntered: true]
                                )
                                try await healthStore.save(sample)
                                stepsSaved = true
                            }
                        }
                    } else if dataSourceId.contains("heart_rate") {
                        if let avgHeartRate = values[0]["fpVal"] as? Double {
                            let hrType = HKObjectType.quantityType(forIdentifier: .heartRate)!
                            let exists = await quantitySampleExists(type: hrType, start: start, end: end)
                            if !exists {
                                let hrQuantity = HKQuantity(unit: HKUnit(from: "count/min"), doubleValue: avgHeartRate)
                                let sample = HKQuantitySample(
                                    type: hrType,
                                    quantity: hrQuantity,
                                    start: start,
                                    end: end,
                                    metadata: [HKMetadataKeyWasUserEntered: true]
                                )
                                try await healthStore.save(sample)
                                hrSaved = true
                            }
                        }
                    }
                }
            }
        }
        
        if stepsSaved || hrSaved {
            return (true, "Imported Steps & Heart Rate aggregates from Fitbit to Apple Health!")
        }
        
        return (true, "No steps or heart rate data found on Fitbit for this day.")
    }
    
    private func syncGoogleHealthSleep(for date: Date, token: String) async -> (success: Bool, message: String) {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: date)
        guard let end = calendar.date(byAdding: .day, value: 1, to: start) else {
            return (false, "Invalid date calculations.")
        }
        
        do {
            let filter = "sleep.interval.end_time >= \"\(rfc3339(start))\" AND sleep.interval.end_time < \"\(rfc3339(end))\""
            let points = try await googleHealthDataPoints(dataType: "sleep", token: token, filter: filter, pageSize: 25)
            let result = try await saveGoogleHealthSleep(points)
            return (true, result)
        } catch {
            return await handleGoogleHealthError(error, retry: { refreshedToken in
                await self.syncGoogleHealthSleep(for: date, token: refreshedToken)
            })
        }
    }
    
    private func syncGoogleHealthActivityAndHeart(for date: Date, token: String) async -> (success: Bool, message: String) {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: date)
        guard let end = calendar.date(byAdding: .day, value: 1, to: start) else {
            return (false, "Invalid date calculations.")
        }
        
        do {
            async let stepsPoints = googleHealthDataPoints(
                dataType: "steps",
                token: token,
                filter: "steps.interval.start_time >= \"\(rfc3339(start))\" AND steps.interval.start_time < \"\(rfc3339(end))\"",
                pageSize: 10000
            )
            async let heartPoints = googleHealthDataPoints(
                dataType: "heart-rate",
                token: token,
                filter: "heart_rate.sample_time.physical_time >= \"\(rfc3339(start))\" AND heart_rate.sample_time.physical_time < \"\(rfc3339(end))\"",
                pageSize: 10000
            )
            async let restingPoints = googleHealthDataPoints(
                dataType: "daily-resting-heart-rate",
                token: token,
                filter: "daily_resting_heart_rate.date >= \"\(dateString(start))\" AND daily_resting_heart_rate.date < \"\(dateString(end))\"",
                pageSize: 10
            )
            async let dailyRespiratoryPoints = googleHealthDataPoints(
                dataType: "daily-respiratory-rate",
                token: token,
                filter: "daily_respiratory_rate.date >= \"\(dateString(start))\" AND daily_respiratory_rate.date < \"\(dateString(end))\"",
                pageSize: 10
            )
            async let sleepRespiratoryPoints = googleHealthDataPoints(
                dataType: "respiratory-rate-sleep-summary",
                token: token,
                filter: "respiratory_rate_sleep_summary.sample_time.physical_time >= \"\(rfc3339(start))\" AND respiratory_rate_sleep_summary.sample_time.physical_time < \"\(rfc3339(end))\"",
                pageSize: 100
            )
            async let dailyHrvPoints = googleHealthDataPoints(
                dataType: "daily-heart-rate-variability",
                token: token,
                filter: "daily_heart_rate_variability.date >= \"\(dateString(start))\" AND daily_heart_rate_variability.date < \"\(dateString(end))\"",
                pageSize: 10
            )
            async let hrvPoints = googleHealthDataPoints(
                dataType: "heart-rate-variability",
                token: token,
                filter: "heart_rate_variability.sample_time.physical_time >= \"\(rfc3339(start))\" AND heart_rate_variability.sample_time.physical_time < \"\(rfc3339(end))\"",
                pageSize: 10000
            )
            async let dailyOxygenPoints = googleHealthDataPoints(
                dataType: "daily-oxygen-saturation",
                token: token,
                filter: "daily_oxygen_saturation.date >= \"\(dateString(start))\" AND daily_oxygen_saturation.date < \"\(dateString(end))\"",
                pageSize: 10
            )
            async let oxygenPoints = googleHealthDataPoints(
                dataType: "oxygen-saturation",
                token: token,
                filter: "oxygen_saturation.sample_time.physical_time >= \"\(rfc3339(start))\" AND oxygen_saturation.sample_time.physical_time < \"\(rfc3339(end))\"",
                pageSize: 10000
            )
            async let sleepTemperaturePoints = googleHealthDataPoints(
                dataType: "daily-sleep-temperature-derivations",
                token: token,
                filter: "daily_sleep_temperature_derivations.date >= \"\(dateString(start))\" AND daily_sleep_temperature_derivations.date < \"\(dateString(end))\"",
                pageSize: 10
            )
            async let activeZonePoints = googleHealthDataPoints(
                dataType: "active-zone-minutes",
                token: token,
                filter: "active_zone_minutes.interval.start_time >= \"\(rfc3339(start))\" AND active_zone_minutes.interval.start_time < \"\(rfc3339(end))\"",
                pageSize: 10000
            )
            async let activeMinutesPoints = googleHealthDataPoints(
                dataType: "active-minutes",
                token: token,
                filter: "active_minutes.interval.start_time >= \"\(rfc3339(start))\" AND active_minutes.interval.start_time < \"\(rfc3339(end))\"",
                pageSize: 10000
            )
            async let totalCaloriesPoints = googleHealthDataPoints(
                dataType: "total-calories",
                token: token,
                filter: "total_calories.interval.start_time >= \"\(rfc3339(start))\" AND total_calories.interval.start_time < \"\(rfc3339(end))\"",
                pageSize: 10000
            )
            async let distancePoints = googleHealthDataPoints(
                dataType: "distance",
                token: token,
                filter: "distance.interval.start_time >= \"\(rfc3339(start))\" AND distance.interval.start_time < \"\(rfc3339(end))\"",
                pageSize: 10000
            )
            async let floorsPoints = googleHealthDataPoints(
                dataType: "floors",
                token: token,
                filter: "floors.interval.start_time >= \"\(rfc3339(start))\" AND floors.interval.start_time < \"\(rfc3339(end))\"",
                pageSize: 10000
            )
            async let exercisePoints = googleHealthDataPoints(
                dataType: "exercise",
                token: token,
                filter: "exercise.interval.start_time >= \"\(rfc3339(start))\" AND exercise.interval.start_time < \"\(rfc3339(end))\"",
                pageSize: 25
            )
            
            let (steps, heart, resting, dailyRespiratory, sleepRespiratory, dailyHrv, hrv, dailyOxygen, oxygen, sleepTemperature, activeZone, activeMinutes, totalCalories, distance, floors, exercises) = try await (
                stepsPoints,
                heartPoints,
                restingPoints,
                dailyRespiratoryPoints,
                sleepRespiratoryPoints,
                dailyHrvPoints,
                hrvPoints,
                dailyOxygenPoints,
                oxygenPoints,
                sleepTemperaturePoints,
                activeZonePoints,
                activeMinutesPoints,
                totalCaloriesPoints,
                distancePoints,
                floorsPoints,
                exercisePoints
            )
            let savedSteps = try await saveGoogleHealthSteps(steps, fallbackStart: start, fallbackEnd: end)
            let savedHeart = try await saveGoogleHealthHeartRate(heart)
            let savedResting = try await saveGoogleHealthRestingHeartRate(resting, fallbackDate: start)
            let savedRespiratory = try await saveGoogleHealthRespiratoryRate(dailyPoints: dailyRespiratory, sleepSummaryPoints: sleepRespiratory, fallbackDate: start)
            let savedHrv = try await saveGoogleHealthHeartRateVariability(dailyPoints: dailyHrv, samplePoints: hrv, fallbackDate: start)
            let savedOxygen = try await saveGoogleHealthOxygenSaturation(dailyPoints: dailyOxygen, samplePoints: oxygen, fallbackDate: start)
            let savedTemperature = try await saveGoogleHealthSleepTemperature(sleepTemperature, fallbackDate: start)
            let savedExerciseMinutes = try await saveGoogleHealthActiveMinutes(activeMinutes, activeZonePoints: activeZone, fallbackStart: start, fallbackEnd: end)
            let savedCalories = try await saveGoogleHealthTotalCalories(totalCalories, fallbackStart: start, fallbackEnd: end)
            let savedDistance = try await saveGoogleHealthDistance(distance, fallbackStart: start, fallbackEnd: end)
            let savedFloors = try await saveGoogleHealthFloors(floors, fallbackStart: start, fallbackEnd: end)
            let savedWorkouts = try await saveGoogleHealthExercises(exercises)
            
            return (true, "Saved Google Health data to Apple Health: \(savedSteps) step, \(savedHeart) heart-rate, \(savedResting) resting-HR, \(savedRespiratory) respiratory-rate, \(savedHrv) HRV, \(savedOxygen) SpO2, \(savedTemperature) temperature, \(savedExerciseMinutes) exercise-minute, \(savedCalories) calorie, \(savedDistance) distance, \(savedFloors) floors, \(savedWorkouts) workout records.")
        } catch {
            return await handleGoogleHealthError(error, retry: { refreshedToken in
                await self.syncGoogleHealthActivityAndHeart(for: date, token: refreshedToken)
            })
        }
    }
    
    private func googleHealthDataPoints(dataType: String, token: String, filter: String, pageSize: Int) async throws -> [[String: Any]] {
        var allPoints: [[String: Any]] = []
        var pageToken: String?
        
        repeat {
            var components = URLComponents(string: "https://health.googleapis.com/v4/users/me/dataTypes/\(dataType)/dataPoints")!
            var queryItems = [
                URLQueryItem(name: "filter", value: filter),
                URLQueryItem(name: "pageSize", value: String(pageSize))
            ]
            if let pageToken {
                queryItems.append(URLQueryItem(name: "pageToken", value: pageToken))
            }
            components.queryItems = queryItems
            
            guard let url = components.url else {
                throw googleHealthError("Invalid Google Health URL.")
            }
            
            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            
            let (data, response) = try await URLSession.shared.data(for: request)
            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 401 {
                throw GoogleHealthSyncError.unauthorized
            }
            if let httpResponse = response as? HTTPURLResponse, !(200...299).contains(httpResponse.statusCode) {
                let body = String(data: data, encoding: .utf8) ?? "No response body"
                throw googleHealthError("Google Health \(dataType) request failed (\(httpResponse.statusCode)): \(body)")
            }
            
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw googleHealthError("Could not parse Google Health \(dataType) response.")
            }
            
            allPoints.append(contentsOf: json["dataPoints"] as? [[String: Any]] ?? [])
            pageToken = json["nextPageToken"] as? String
        } while pageToken?.isEmpty == false
        
        return allPoints
    }
    
    private func saveGoogleHealthSleep(_ points: [[String: Any]]) async throws -> String {
        let sleepType = HKObjectType.categoryType(forIdentifier: .sleepAnalysis)!
        var samples: [HKCategorySample] = []
        var sessionRanges: [(Date, Date)] = []
        
        for point in points {
            guard let sleep = point["sleep"] as? [String: Any],
                  let interval = sleep["interval"] as? [String: Any],
                  let sessionStart = parseGoogleDate(interval["startTime"]),
                  let sessionEnd = parseGoogleDate(interval["endTime"]) else {
                continue
            }
            
            sessionRanges.append((sessionStart, sessionEnd))
            let inBedExists = await sleepSampleExists(start: sessionStart, end: sessionEnd, value: HKCategoryValueSleepAnalysis.inBed.rawValue)
            if !inBedExists {
                samples.append(HKCategorySample(type: sleepType, value: HKCategoryValueSleepAnalysis.inBed.rawValue, start: sessionStart, end: sessionEnd, metadata: fitbitImportMetadata))
            }
            
            let stages = sleep["stages"] as? [[String: Any]] ?? []
            if stages.isEmpty {
                let exists = await sleepSampleExists(start: sessionStart, end: sessionEnd, value: HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue)
                if !exists {
                    samples.append(HKCategorySample(type: sleepType, value: HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue, start: sessionStart, end: sessionEnd, metadata: fitbitImportMetadata))
                }
            }
            
            for stage in stages {
                guard let stageStart = parseGoogleDate(stage["startTime"]),
                      let stageEnd = parseGoogleDate(stage["endTime"]),
                      let stageValue = healthKitSleepStageValue(stage["type"] as? String) else {
                    continue
                }
                
                let exists = await sleepSampleExists(start: stageStart, end: stageEnd, value: stageValue)
                if !exists {
                    samples.append(HKCategorySample(type: sleepType, value: stageValue, start: stageStart, end: stageEnd, metadata: fitbitImportMetadata))
                }
            }
        }
        
        if !samples.isEmpty {
            try await healthStore.save(samples)
        }
        
        if let start = sessionRanges.map(\.0).min(), let end = sessionRanges.map(\.1).max() {
            let verification = try await verifySleepSamples(start: start, end: end)
            return "Saved \(samples.count) sleep records; verified \(verification.count) records / \(formatDuration(verification.asleepSeconds)) asleep."
        }
        
        return "No Google Health sleep records found for this day."
    }
    
    private func saveGoogleHealthSteps(_ points: [[String: Any]], fallbackStart: Date, fallbackEnd: Date) async throws -> Int {
        let stepType = HKObjectType.quantityType(forIdentifier: .stepCount)!
        var samples: [HKQuantitySample] = []
        
        for point in points {
            guard let steps = point["steps"] as? [String: Any],
                  let interval = steps["interval"] as? [String: Any],
                  let count = int64Value(steps["count"]) else {
                continue
            }
            
            let start = parseGoogleDate(interval["startTime"]) ?? fallbackStart
            let end = parseGoogleDate(interval["endTime"]) ?? fallbackEnd
            let exists = await quantitySampleExists(type: stepType, start: start, end: end)
            if !exists {
                samples.append(HKQuantitySample(type: stepType, quantity: HKQuantity(unit: .count(), doubleValue: Double(count)), start: start, end: end, metadata: fitbitImportMetadata))
            }
        }
        
        if !samples.isEmpty {
            try await healthStore.save(samples)
        }
        return samples.count
    }
    
    private func saveGoogleHealthHeartRate(_ points: [[String: Any]]) async throws -> Int {
        let hrType = HKObjectType.quantityType(forIdentifier: .heartRate)!
        var samples: [HKQuantitySample] = []
        
        for point in points {
            guard let heartRate = point["heartRate"] as? [String: Any],
                  let sampleTime = heartRate["sampleTime"] as? [String: Any],
                  let bpm = int64Value(heartRate["beatsPerMinute"]),
                  let observedAt = parseGoogleDate(sampleTime["physicalTime"]) else {
                continue
            }
            
            let end = observedAt.addingTimeInterval(1)
            let exists = await quantitySampleExists(type: hrType, start: observedAt, end: end)
            if !exists {
                samples.append(HKQuantitySample(type: hrType, quantity: HKQuantity(unit: HKUnit(from: "count/min"), doubleValue: Double(bpm)), start: observedAt, end: end, metadata: fitbitImportMetadata))
            }
        }
        
        if !samples.isEmpty {
            try await healthStore.save(samples)
        }
        return samples.count
    }
    
    private func saveGoogleHealthRestingHeartRate(_ points: [[String: Any]], fallbackDate: Date) async throws -> Int {
        let restingType = HKObjectType.quantityType(forIdentifier: .restingHeartRate)!
        var samples: [HKQuantitySample] = []
        let calendar = Calendar.current
        
        for point in points {
            guard let resting = point["dailyRestingHeartRate"] as? [String: Any],
                  let bpm = int64Value(resting["beatsPerMinute"]) else {
                continue
            }
            
            let sampleDate = parseGoogleCivilDate(resting["date"] as? [String: Any]) ?? fallbackDate
            let start = calendar.date(bySettingHour: 3, minute: 0, second: 0, of: sampleDate) ?? sampleDate
            let end = start.addingTimeInterval(1)
            let exists = await quantitySampleExists(type: restingType, start: start, end: end)
            if !exists {
                samples.append(HKQuantitySample(type: restingType, quantity: HKQuantity(unit: HKUnit(from: "count/min"), doubleValue: Double(bpm)), start: start, end: end, metadata: fitbitImportMetadata))
            }
        }
        
        if !samples.isEmpty {
            try await healthStore.save(samples)
        }
        return samples.count
    }
    
    private func saveGoogleHealthRespiratoryRate(dailyPoints: [[String: Any]], sleepSummaryPoints: [[String: Any]], fallbackDate: Date) async throws -> Int {
        let respiratoryType = HKObjectType.quantityType(forIdentifier: .respiratoryRate)!
        var samples: [HKQuantitySample] = []
        let calendar = Calendar.current
        
        for point in dailyPoints {
            guard let daily = point["dailyRespiratoryRate"] as? [String: Any],
                  let breathsPerMinute = daily["breathsPerMinute"] as? Double else {
                continue
            }
            
            let sampleDate = parseGoogleCivilDate(daily["date"] as? [String: Any]) ?? fallbackDate
            let start = calendar.date(bySettingHour: 3, minute: 0, second: 0, of: sampleDate) ?? sampleDate
            let end = start.addingTimeInterval(1)
            let exists = await quantitySampleExists(type: respiratoryType, start: start, end: end)
            if !exists {
                samples.append(HKQuantitySample(type: respiratoryType, quantity: HKQuantity(unit: HKUnit(from: "count/min"), doubleValue: breathsPerMinute), start: start, end: end, metadata: fitbitImportMetadata))
            }
        }
        
        for point in sleepSummaryPoints {
            guard let summary = point["respiratoryRateSleepSummary"] as? [String: Any],
                  let sampleTime = summary["sampleTime"] as? [String: Any],
                  let observedAt = parseGoogleDate(sampleTime["physicalTime"]),
                  let fullSleepStats = summary["fullSleepStats"] as? [String: Any],
                  let breathsPerMinute = fullSleepStats["breathsPerMinute"] as? Double else {
                continue
            }
            
            let end = observedAt.addingTimeInterval(1)
            let exists = await quantitySampleExists(type: respiratoryType, start: observedAt, end: end)
            if !exists {
                samples.append(HKQuantitySample(type: respiratoryType, quantity: HKQuantity(unit: HKUnit(from: "count/min"), doubleValue: breathsPerMinute), start: observedAt, end: end, metadata: fitbitImportMetadata))
            }
        }
        
        if !samples.isEmpty {
            try await healthStore.save(samples)
        }
        return samples.count
    }
    
    private func saveGoogleHealthHeartRateVariability(dailyPoints: [[String: Any]], samplePoints: [[String: Any]], fallbackDate: Date) async throws -> Int {
        let hrvType = HKObjectType.quantityType(forIdentifier: .heartRateVariabilitySDNN)!
        var samples: [HKQuantitySample] = []
        let calendar = Calendar.current
        
        for point in dailyPoints {
            guard let daily = point["dailyHeartRateVariability"] as? [String: Any] else { continue }
            let milliseconds = doubleValue(daily["averageHeartRateVariabilityMilliseconds"])
                ?? doubleValue(daily["deepSleepRootMeanSquareOfSuccessiveDifferencesMilliseconds"])
            guard let milliseconds else { continue }
            
            let sampleDate = parseGoogleCivilDate(daily["date"] as? [String: Any]) ?? fallbackDate
            let start = calendar.date(bySettingHour: 3, minute: 0, second: 0, of: sampleDate) ?? sampleDate
            let end = start.addingTimeInterval(1)
            let exists = await quantitySampleExists(type: hrvType, start: start, end: end)
            if !exists {
                samples.append(HKQuantitySample(type: hrvType, quantity: HKQuantity(unit: .secondUnit(with: .milli), doubleValue: milliseconds), start: start, end: end, metadata: fitbitImportMetadata))
            }
        }
        
        for point in samplePoints {
            guard let hrv = point["heartRateVariability"] as? [String: Any],
                  let sampleTime = hrv["sampleTime"] as? [String: Any],
                  let observedAt = parseGoogleDate(sampleTime["physicalTime"]) else {
                continue
            }
            let milliseconds = doubleValue(hrv["standardDeviationMilliseconds"])
                ?? doubleValue(hrv["rootMeanSquareOfSuccessiveDifferencesMilliseconds"])
            guard let milliseconds else { continue }
            
            let end = observedAt.addingTimeInterval(1)
            let exists = await quantitySampleExists(type: hrvType, start: observedAt, end: end)
            if !exists {
                samples.append(HKQuantitySample(type: hrvType, quantity: HKQuantity(unit: .secondUnit(with: .milli), doubleValue: milliseconds), start: observedAt, end: end, metadata: fitbitImportMetadata))
            }
        }
        
        if !samples.isEmpty {
            try await healthStore.save(samples)
        }
        return samples.count
    }
    
    private func saveGoogleHealthOxygenSaturation(dailyPoints: [[String: Any]], samplePoints: [[String: Any]], fallbackDate: Date) async throws -> Int {
        let oxygenType = HKObjectType.quantityType(forIdentifier: .oxygenSaturation)!
        var samples: [HKQuantitySample] = []
        let calendar = Calendar.current
        
        for point in dailyPoints {
            guard let daily = point["dailyOxygenSaturation"] as? [String: Any],
                  let percentage = doubleValue(daily["averagePercentage"]) else {
                continue
            }
            
            let sampleDate = parseGoogleCivilDate(daily["date"] as? [String: Any]) ?? fallbackDate
            let start = calendar.date(bySettingHour: 3, minute: 0, second: 0, of: sampleDate) ?? sampleDate
            let end = start.addingTimeInterval(1)
            let exists = await quantitySampleExists(type: oxygenType, start: start, end: end)
            if !exists {
                samples.append(HKQuantitySample(type: oxygenType, quantity: HKQuantity(unit: .percent(), doubleValue: percentage / 100.0), start: start, end: end, metadata: fitbitImportMetadata))
            }
        }
        
        for point in samplePoints {
            guard let oxygen = point["oxygenSaturation"] as? [String: Any],
                  let sampleTime = oxygen["sampleTime"] as? [String: Any],
                  let observedAt = parseGoogleDate(sampleTime["physicalTime"]),
                  let percentage = doubleValue(oxygen["percentage"]) else {
                continue
            }
            
            let end = observedAt.addingTimeInterval(1)
            let exists = await quantitySampleExists(type: oxygenType, start: observedAt, end: end)
            if !exists {
                samples.append(HKQuantitySample(type: oxygenType, quantity: HKQuantity(unit: .percent(), doubleValue: percentage / 100.0), start: observedAt, end: end, metadata: fitbitImportMetadata))
            }
        }
        
        if !samples.isEmpty {
            try await healthStore.save(samples)
        }
        return samples.count
    }
    private func saveGoogleHealthSleepTemperature(_ points: [[String: Any]], fallbackDate: Date) async throws -> Int {
        var temperatureType = HKObjectType.quantityType(forIdentifier: .bodyTemperature)!
        if #available(iOS 16.0, *), let sleepTemp = HKObjectType.quantityType(forIdentifier: .appleSleepingWristTemperature) {
            temperatureType = sleepTemp
        }
        var samples: [HKQuantitySample] = []
        let calendar = Calendar.current
        
        for point in points {
            guard let temp = point["dailySleepTemperatureDerivations"] as? [String: Any],
                  let celsius = doubleValue(temp["nightlyTemperatureCelsius"]) else {
                continue
            }
            
            let sampleDate = parseGoogleCivilDate(temp["date"] as? [String: Any]) ?? fallbackDate
            let start = calendar.date(bySettingHour: 3, minute: 0, second: 0, of: sampleDate) ?? sampleDate
            let end = start.addingTimeInterval(1)
            let exists = await quantitySampleExists(type: temperatureType, start: start, end: end)
            if !exists {
                var metadata = fitbitImportMetadata
                metadata["FebusTemperatureKind"] = "SleepSkinTemperature"
                if let baseline = doubleValue(temp["baselineTemperatureCelsius"]) {
                    metadata["FebusBaselineTemperatureCelsius"] = baseline
                }
                samples.append(HKQuantitySample(type: temperatureType, quantity: HKQuantity(unit: .degreeCelsius(), doubleValue: celsius), start: start, end: end, metadata: metadata))
            }
        }
        
        if !samples.isEmpty {
            try await healthStore.save(samples)
        }
        return samples.count
    }
    
    private func saveGoogleHealthActiveMinutes(_ activeMinutePoints: [[String: Any]], activeZonePoints: [[String: Any]], fallbackStart: Date, fallbackEnd: Date) async throws -> Int {
        // Apple does not allow third-party apps to write Apple Exercise Time.
        // Active Zone Minutes are preserved on imported workouts when Google includes
        // them in exercise metrics; standalone daily AZM points are fetched but not
        // written as a fake HealthKit quantity.
        _ = (activeMinutePoints, activeZonePoints, fallbackStart, fallbackEnd)
        return 0
    }
    
    private func saveGoogleHealthTotalCalories(_ points: [[String: Any]], fallbackStart: Date, fallbackEnd: Date) async throws -> Int {
        let calorieType = HKObjectType.quantityType(forIdentifier: .activeEnergyBurned)!
        var samples: [HKQuantitySample] = []
        
        for point in points {
            guard let calories = point["totalCalories"] as? [String: Any],
                  let interval = calories["interval"] as? [String: Any],
                  let kcal = doubleValue(calories["kcal"]) else {
                continue
            }
            
            let start = parseGoogleDate(interval["startTime"]) ?? fallbackStart
            let end = parseGoogleDate(interval["endTime"]) ?? fallbackEnd
            let exists = await quantitySampleExists(type: calorieType, start: start, end: end)
            if !exists {
                var metadata = fitbitImportMetadata
                metadata["FebusMetricKind"] = "GoogleHealthTotalCalories"
                samples.append(HKQuantitySample(type: calorieType, quantity: HKQuantity(unit: .kilocalorie(), doubleValue: kcal), start: start, end: end, metadata: metadata))
            }
        }
        
        if !samples.isEmpty {
            try await healthStore.save(samples)
        }
        return samples.count
    }
    
    private func saveGoogleHealthDistance(_ points: [[String: Any]], fallbackStart: Date, fallbackEnd: Date) async throws -> Int {
        let distanceType = HKObjectType.quantityType(forIdentifier: .distanceWalkingRunning)!
        var samples: [HKQuantitySample] = []
        
        for point in points {
            guard let distance = point["distance"] as? [String: Any],
                  let interval = distance["interval"] as? [String: Any],
                  let millimeters = doubleValue(distance["millimeters"]) else {
                continue
            }
            
            let start = parseGoogleDate(interval["startTime"]) ?? fallbackStart
            let end = parseGoogleDate(interval["endTime"]) ?? fallbackEnd
            let exists = await quantitySampleExists(type: distanceType, start: start, end: end)
            if !exists {
                samples.append(HKQuantitySample(type: distanceType, quantity: HKQuantity(unit: .meter(), doubleValue: millimeters / 1000.0), start: start, end: end, metadata: fitbitImportMetadata))
            }
        }
        
        if !samples.isEmpty {
            try await healthStore.save(samples)
        }
        return samples.count
    }
    
    private func saveGoogleHealthFloors(_ points: [[String: Any]], fallbackStart: Date, fallbackEnd: Date) async throws -> Int {
        let floorsType = HKObjectType.quantityType(forIdentifier: .flightsClimbed)!
        var samples: [HKQuantitySample] = []
        
        for point in points {
            guard let floors = point["floors"] as? [String: Any],
                  let interval = floors["interval"] as? [String: Any],
                  let count = int64Value(floors["count"]) else {
                continue
            }
            
            let start = parseGoogleDate(interval["startTime"]) ?? fallbackStart
            let end = parseGoogleDate(interval["endTime"]) ?? fallbackEnd
            let exists = await quantitySampleExists(type: floorsType, start: start, end: end)
            if !exists {
                samples.append(HKQuantitySample(type: floorsType, quantity: HKQuantity(unit: .count(), doubleValue: Double(count)), start: start, end: end, metadata: fitbitImportMetadata))
            }
        }
        
        if !samples.isEmpty {
            try await healthStore.save(samples)
        }
        return samples.count
    }
    
    private func saveGoogleHealthExercises(_ points: [[String: Any]]) async throws -> Int {
        var workouts: [HKWorkout] = []
        
        for point in points {
            guard let exercise = point["exercise"] as? [String: Any],
                  let interval = exercise["interval"] as? [String: Any],
                  let start = parseGoogleDate(interval["startTime"]),
                  let end = parseGoogleDate(interval["endTime"]) else {
                continue
            }
            
            let exists = await workoutExists(start: start, end: end)
            if exists { continue }
            
            let metrics = exercise["metricsSummary"] as? [String: Any]
            let energy = doubleValue(metrics?["caloriesKcal"]).map {
                HKQuantity(unit: .kilocalorie(), doubleValue: $0)
            }
            let distance = doubleValue(metrics?["distanceMillimeters"]).map {
                HKQuantity(unit: .meter(), doubleValue: $0 / 1000.0)
            }
            
            var metadata = fitbitImportMetadata
            metadata[HKMetadataKeyWorkoutBrandName] = "Google Health"
            metadata["FebusExerciseType"] = exercise["exerciseType"] as? String
            metadata["FebusExerciseDisplayName"] = exercise["displayName"] as? String
            if let activeZoneMinutes = int64Value(metrics?["activeZoneMinutes"]) {
                metadata["FebusActiveZoneMinutes"] = activeZoneMinutes
            }
            if let elevationGainMillimeters = doubleValue(metrics?["elevationGainMillimeters"]) {
                metadata["FebusElevationGainMeters"] = elevationGainMillimeters / 1000.0
            }
            if let averageHeartRate = int64Value(metrics?["averageHeartRateBeatsPerMinute"]) {
                metadata["FebusAverageHeartRate"] = averageHeartRate
            }
            
            workouts.append(HKWorkout(
                activityType: healthKitWorkoutActivityType(exercise["exerciseType"] as? String),
                start: start,
                end: end,
                duration: end.timeIntervalSince(start),
                totalEnergyBurned: energy,
                totalDistance: distance,
                metadata: metadata
            ))
        }
        
        if !workouts.isEmpty {
            try await healthStore.save(workouts)
        }
        return workouts.count
    }
    
    private var googleClientID: String? {
        #if UNIVERSAL_BUILD
        Bundle.main.object(forInfoDictionaryKey: "FebusGoogleOAuthClientID") as? String
        #else
        FirebaseApp.app()?.options.clientID
        #endif
    }
    
    private var googleOAuthCallbackScheme: String? {
        #if UNIVERSAL_BUILD
        if let scheme = Bundle.main.object(forInfoDictionaryKey: "FebusGoogleOAuthCallbackScheme") as? String {
            return scheme
        }
        #endif
        
        guard let clientID = googleClientID else { return nil }
        return reversedGoogleClientID(from: clientID)
    }
    
    private var googleOAuthRedirectURI: String? {
        guard let callbackScheme = googleOAuthCallbackScheme else { return nil }
        return "\(callbackScheme):/oauth2redirect"
    }
    
    private var fitbitImportMetadata: [String: Any] {
        [
            HKMetadataKeyWasUserEntered: false,
            "FebusImportSource": "GoogleHealth"
        ]
    }
    
    private func handleGoogleHealthError(_ error: Error, retry: (String) async -> (success: Bool, message: String)) async -> (success: Bool, message: String) {
        if case GoogleHealthSyncError.unauthorized = error {
            let refreshed = await refreshAccessToken()
            if refreshed, let token = accessToken {
                return await retry(token)
            }
            return (false, "Google Health session expired. Reconnect to sync.")
        }
        
        return (false, "Google Health sync error: \(error.localizedDescription)")
    }
    
    private func googleHealthError(_ message: String) -> NSError {
        NSError(domain: "GoogleHealthSync", code: 0, userInfo: [NSLocalizedDescriptionKey: message])
    }
    
    private func parseGoogleDate(_ value: Any?) -> Date? {
        guard let string = value as? String else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: string) {
            return date
        }
        
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: string)
    }
    
    private func parseGoogleCivilDate(_ value: [String: Any]?) -> Date? {
        guard let year = value?["year"] as? Int,
              let month = value?["month"] as? Int,
              let day = value?["day"] as? Int else {
            return nil
        }
        
        return Calendar.current.date(from: DateComponents(year: year, month: month, day: day))
    }
    
    private func int64Value(_ value: Any?) -> Int64? {
        if let int = value as? Int { return Int64(int) }
        if let int64 = value as? Int64 { return int64 }
        if let double = value as? Double { return Int64(double) }
        if let string = value as? String { return Int64(string) }
        return nil
    }
    
    private func doubleValue(_ value: Any?) -> Double? {
        if let double = value as? Double { return double }
        if let int = value as? Int { return Double(int) }
        if let int64 = value as? Int64 { return Double(int64) }
        if let string = value as? String { return Double(string) }
        return nil
    }
    
    private func healthKitWorkoutActivityType(_ value: String?) -> HKWorkoutActivityType {
        switch value {
        case "RUNNING":
            return .running
        case "WALKING":
            return .walking
        case "BIKING":
            return .cycling
        case "SWIMMING":
            return .swimming
        case "HIKING":
            return .hiking
        case "YOGA":
            return .yoga
        case "PILATES":
            return .pilates
        case "HIIT":
            return .highIntensityIntervalTraining
        case "WEIGHTLIFTING", "STRENGTH_TRAINING":
            return .traditionalStrengthTraining
        default:
            return .other
        }
    }
    
    private func healthKitSleepStageValue(_ value: String?) -> Int? {
        switch value {
        case "AWAKE":
            return HKCategoryValueSleepAnalysis.awake.rawValue
        case "LIGHT":
            return HKCategoryValueSleepAnalysis.asleepCore.rawValue
        case "DEEP":
            return HKCategoryValueSleepAnalysis.asleepDeep.rawValue
        case "REM":
            return HKCategoryValueSleepAnalysis.asleepREM.rawValue
        case "ASLEEP", "RESTLESS", "SLEEP_STAGE_TYPE_UNSPECIFIED":
            return HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue
        default:
            return nil
        }
    }
    
    private func rfc3339(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: date)
    }
    
    private func dateString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
    
    private func reversedGoogleClientID(from clientID: String) -> String? {
        let suffix = ".apps.googleusercontent.com"
        guard clientID.hasSuffix(suffix) else { return nil }
        let appID = clientID.dropLast(suffix.count)
        return "com.googleusercontent.apps.\(appID)"
    }
    
    private func minDate(_ current: Date?, _ candidate: Date) -> Date {
        guard let current else { return candidate }
        return min(current, candidate)
    }
    
    private func maxDate(_ current: Date?, _ candidate: Date) -> Date {
        guard let current else { return candidate }
        return max(current, candidate)
    }
    
    private func verifySleepSamples(start: Date, end: Date) async throws -> (count: Int, asleepSeconds: Double) {
        let sleepType = HKObjectType.categoryType(forIdentifier: .sleepAnalysis)!
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
        
        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(sampleType: sleepType, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, samples, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }
                
                let sleepSamples = samples as? [HKCategorySample] ?? []
                let asleepSeconds = sleepSamples
                    .filter { sample in
                        sample.value != HKCategoryValueSleepAnalysis.inBed.rawValue
                            && sample.value != HKCategoryValueSleepAnalysis.awake.rawValue
                    }
                    .reduce(0.0) { total, sample in
                        total + sample.endDate.timeIntervalSince(sample.startDate)
                    }
                
                continuation.resume(returning: (sleepSamples.count, asleepSeconds))
            }
            healthStore.execute(query)
        }
    }
    
    private func formatDuration(_ seconds: Double) -> String {
        let totalMinutes = Int(seconds / 60)
        return "\(totalMinutes / 60)h \(totalMinutes % 60)m"
    }
    
    private func requestHealthWriteAuthorization() async throws {
        guard HKHealthStore.isHealthDataAvailable() else {
            throw NSError(domain: "FitbitService", code: 0, userInfo: [NSLocalizedDescriptionKey: "Apple Health is not available on this device."])
        }
        
        try await healthStore.requestAuthorization(toShare: writeTypes, read: readTypes)
    }
    
    private func quantitySampleExists(type: HKQuantityType, start: Date, end: Date) async -> Bool {
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: [.strictStartDate, .strictEndDate])
        
        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(sampleType: type, predicate: predicate, limit: 1, sortDescriptors: nil) { _, samples, _ in
                continuation.resume(returning: !(samples ?? []).isEmpty)
            }
            healthStore.execute(query)
        }
    }
    
    private func workoutExists(start: Date, end: Date) async -> Bool {
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: [.strictStartDate, .strictEndDate])
        
        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(sampleType: HKObjectType.workoutType(), predicate: predicate, limit: 1, sortDescriptors: nil) { _, samples, _ in
                continuation.resume(returning: !(samples ?? []).isEmpty)
            }
            healthStore.execute(query)
        }
    }
    
    private func formEncodedBody(_ bodyComponents: [String: String]) -> Data? {
        var components = URLComponents()
        components.queryItems = bodyComponents.map { URLQueryItem(name: $0.key, value: $0.value) }
        return components.percentEncodedQuery?.data(using: .utf8)
    }
}

extension FitbitService: ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene else {
            fatalError("No active UIWindowScene found")
        }
        return windowScene.windows.first { $0.isKeyWindow } ?? windowScene.windows.first ?? UIWindow(windowScene: windowScene)
    }
}
