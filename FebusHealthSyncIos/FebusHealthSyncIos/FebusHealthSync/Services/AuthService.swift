import Foundation
import FirebaseAuth
import GoogleSignIn
import FirebaseCore
import Combine
@MainActor
class AuthService: ObservableObject {
    @Published var currentUser: User?
    @Published var isAuthenticating: Bool = false
    
    init() {
        self.currentUser = Auth.auth().currentUser
        
        Auth.auth().addStateDidChangeListener { [weak self] _, user in
            DispatchQueue.main.async {
                self?.currentUser = user
            }
        }
    }
    
    var isAuthenticated: Bool {
        return currentUser != nil
    }
    
    func signInWithGoogle(presentingViewController: UIViewController) async throws {
        isAuthenticating = true
        defer { isAuthenticating = false }
        
        guard let clientID = FirebaseApp.app()?.options.clientID else {
            throw NSError(domain: "AuthService", code: 0, userInfo: [NSLocalizedDescriptionKey: "No Client ID found in Firebase configuration"])
        }
        
        let config = GIDConfiguration(clientID: clientID)
        GIDSignIn.sharedInstance.configuration = config
        
        let result = try await GIDSignIn.sharedInstance.signIn(withPresenting: presentingViewController)
        
        guard let idToken = result.user.idToken?.tokenString else {
            throw NSError(domain: "AuthService", code: 1, userInfo: [NSLocalizedDescriptionKey: "No ID token found"])
        }
        
        let accessToken = result.user.accessToken.tokenString
        let credential = GoogleAuthProvider.credential(withIDToken: idToken, accessToken: accessToken)
        
        // Sign in to Firebase
        let authResult = try await Auth.auth().signIn(with: credential)
        self.currentUser = authResult.user
        
        // Let the SyncManager / FirestoreService handle creating the user profile document
    }
    
    func signOut() {
        do {
            try Auth.auth().signOut()
            GIDSignIn.sharedInstance.signOut()
            self.currentUser = nil
        } catch {
            print("Error signing out: \(error.localizedDescription)")
        }
    }
}
