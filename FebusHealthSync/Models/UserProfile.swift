import Foundation

struct UserProfile: Codable {
    let email: String
    let displayName: String?
    let createdAt: Date
    let lastLoginAt: Date
    
    // Firestore conversion
    var dictionary: [String: Any] {
        return [
            "email": email,
            "displayName": displayName ?? "",
            "createdAt": createdAt,
            "lastLoginAt": lastLoginAt
        ]
    }
}
