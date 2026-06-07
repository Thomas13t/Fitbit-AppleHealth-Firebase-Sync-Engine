import Foundation
import FirebaseCore
import Combine

class FirebaseConfigManager: ObservableObject {
    static let shared = FirebaseConfigManager()
    
    @Published var isConfigured: Bool = false
    
    private let userDefaultsKeyApiKey = "byodb_firebase_api_key"
    private let userDefaultsKeyProjectId = "byodb_firebase_project_id"
    private let userDefaultsKeyGoogleAppId = "byodb_firebase_google_app_id"
    private let userDefaultsKeyClientId = "byodb_firebase_client_id"
    private let userDefaultsKeySenderId = "byodb_firebase_sender_id"
    
    init() {
        self.isConfigured = hasConfig
    }
    
    var hasConfig: Bool {
        return apiKey != nil && projectID != nil && googleAppID != nil
    }
    
    var apiKey: String? {
        get { UserDefaults.standard.string(forKey: userDefaultsKeyApiKey) }
        set { UserDefaults.standard.set(newValue, forKey: userDefaultsKeyApiKey) }
    }
    
    var projectID: String? {
        get { UserDefaults.standard.string(forKey: userDefaultsKeyProjectId) }
        set { UserDefaults.standard.set(newValue, forKey: userDefaultsKeyProjectId) }
    }
    
    var googleAppID: String? {
        get { UserDefaults.standard.string(forKey: userDefaultsKeyGoogleAppId) }
        set { UserDefaults.standard.set(newValue, forKey: userDefaultsKeyGoogleAppId) }
    }
    
    var clientID: String? {
        get { UserDefaults.standard.string(forKey: userDefaultsKeyClientId) }
        set { UserDefaults.standard.set(newValue, forKey: userDefaultsKeyClientId) }
    }
    
    var senderID: String? {
        get { UserDefaults.standard.string(forKey: userDefaultsKeySenderId) }
        set { UserDefaults.standard.set(newValue, forKey: userDefaultsKeySenderId) }
    }
    
    func saveConfig(apiKey: String, projectID: String, googleAppID: String, clientID: String? = nil, senderID: String? = nil) {
        self.apiKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        self.projectID = projectID.trimmingCharacters(in: .whitespacesAndNewlines)
        self.googleAppID = googleAppID.trimmingCharacters(in: .whitespacesAndNewlines)
        self.clientID = clientID?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.senderID = senderID?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.isConfigured = true
    }
    
    func resetConfig() {
        UserDefaults.standard.removeObject(forKey: userDefaultsKeyApiKey)
        UserDefaults.standard.removeObject(forKey: userDefaultsKeyProjectId)
        UserDefaults.standard.removeObject(forKey: userDefaultsKeyGoogleAppId)
        UserDefaults.standard.removeObject(forKey: userDefaultsKeyClientId)
        UserDefaults.standard.removeObject(forKey: userDefaultsKeySenderId)
        isConfigured = false
    }
    
    func parsePlistXML(_ rawXML: String) -> [String: String]? {
        var config: [String: String] = [:]
        let keys = ["API_KEY", "PROJECT_ID", "GOOGLE_APP_ID", "CLIENT_ID", "GCM_SENDER_ID"]
        
        for key in keys {
            let pattern = "<key>\(key)</key>\\s*<string>([^<]+)</string>"
            if let regex = try? NSRegularExpression(pattern: pattern, options: []),
               let match = regex.firstMatch(in: rawXML, options: [], range: NSRange(rawXML.startIndex..., in: rawXML)) {
                if let range = Range(match.range(at: 1), in: rawXML) {
                    config[key] = String(rawXML[range]).trimmingCharacters(in: .whitespacesAndNewlines)
                }
            }
        }
        
        // Return only if we have parsed the runtime Firebase keys the universal app needs.
        guard config["API_KEY"] != nil,
              config["PROJECT_ID"] != nil,
              config["GOOGLE_APP_ID"] != nil else {
            return nil
        }
        
        return config
    }
    
    func configureFirebase() -> Bool {
        guard let apiKey = apiKey,
              let projectID = projectID,
              let googleAppID = googleAppID else {
            return false
        }
        
        // Skip if Firebase is already configured to prevent crashes
        if FirebaseApp.app() != nil {
            return true
        }
        
        let options = FirebaseOptions(googleAppID: googleAppID, gcmSenderID: senderID ?? "")
        options.apiKey = apiKey
        options.projectID = projectID
        options.clientID = clientID
        
        FirebaseApp.configure(options: options)
        print("[FirebaseConfigManager] Firebase configured dynamically with private BYODB keys successfully.")
        return true
    }
}
