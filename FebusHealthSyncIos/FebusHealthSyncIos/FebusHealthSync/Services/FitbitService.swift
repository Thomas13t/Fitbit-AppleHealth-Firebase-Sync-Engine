import Foundation
import AuthenticationServices
import HealthKit
import UIKit
import Combine
class FitbitService: NSObject, ObservableObject {
    @Published var isLinked: Bool = false
    @Published var statusMessage: String = "Not Connected"
    
    private let healthStore = HKHealthStore()
    
    // Google OAuth 2.0 Credentials (automatically linked to your Firebase project!)
    private let clientId = "215284107318-22qlq74hp88c8npccgq6ng23aeidar65.apps.googleusercontent.com"
    private let redirectUri = "com.googleusercontent.apps.215284107318-22qlq74hp88c8npccgq6ng23aeidar65:/oauth2redirect"
    
    private let userDefaultsKeyToken = "google_health_access_token"
    private let userDefaultsKeyRefreshToken = "google_health_refresh_token"
    
    override init() {
        super.init()
        self.isLinked = (accessToken != nil)
        self.statusMessage = isLinked ? "Connected to Fitbit (via Google)" : "Not Connected"
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
        // Construct the Google OAuth 2.0 URL
        var urlComponents = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")!
        urlComponents.queryItems = [
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "client_id", value: clientId),
            URLQueryItem(name: "redirect_uri", value: redirectUri),
            URLQueryItem(name: "scope", value: "https://www.googleapis.com/auth/fitness.sleep.read https://www.googleapis.com/auth/fitness.activity.read https://www.googleapis.com/auth/fitness.heart_rate.read"),
            URLQueryItem(name: "access_type", value: "offline"), // Offline access to get the Refresh Token
            URLQueryItem(name: "prompt", value: "consent")
        ]
        
        guard let authURL = urlComponents.url else {
            self.statusMessage = "Invalid Auth URL"
            return
        }
        
        let session = ASWebAuthenticationSession(url: authURL, callbackURLScheme: "com.googleusercontent.apps.215284107318-22qlq74hp88c8npccgq6ng23aeidar65") { [weak self] callbackURL, error in
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
        guard let tokenURL = URL(string: "https://oauth2.googleapis.com/token") else { return }
        
        var request = URLRequest(url: tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        
        let bodyComponents = [
            "client_id": clientId,
            "grant_type": "authorization_code",
            "redirect_uri": redirectUri,
            "code": code
        ]
        
        request.httpBody = bodyComponents
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: "&")
            .data(using: .utf8)
        
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
                        self?.statusMessage = "Connected to Fitbit (via Google)!"
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
        guard let refresh = refreshToken, let tokenURL = URL(string: "https://oauth2.googleapis.com/token") else { return false }
        
        var request = URLRequest(url: tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        
        let bodyComponents = [
            "client_id": clientId,
            "grant_type": "refresh_token",
            "refresh_token": refresh
        ]
        
        request.httpBody = bodyComponents
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: "&")
            .data(using: .utf8)
        
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
            self.unlink()
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
        
        if !samplesToSave.isEmpty {
            try await healthStore.save(samplesToSave)
            return (true, "Imported \(samplesToSave.count) new granular sleep stages to Apple Health!")
        }
        
        return (true, "No new sleep data to import.")
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
            return (true, "Imported \(samples.count) sleep sessions to Apple Health!")
        }
        
        return (true, "No new sleep sessions to import.")
    }
    
    func syncActivityAndHeart(for date: Date) async -> (success: Bool, message: String) {
        guard let token = accessToken else {
            return (false, "Not linked.")
        }
        
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
                    } else if dataSourceId.contains("heart_rate") {
                        if let avgHeartRate = values[0]["fpVal"] as? Double {
                            let hrType = HKObjectType.quantityType(forIdentifier: .heartRate)!
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
        
        if stepsSaved || hrSaved {
            return (true, "Imported Steps & Heart Rate aggregates from Fitbit to Apple Health!")
        }
        
        return (true, "No steps or heart rate data found on Fitbit for this day.")
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
