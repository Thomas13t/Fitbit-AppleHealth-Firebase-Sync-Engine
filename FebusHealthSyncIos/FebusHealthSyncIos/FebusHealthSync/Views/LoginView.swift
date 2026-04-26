import SwiftUI
import GoogleSignInSwift

struct LoginView: View {
    @EnvironmentObject var authService: AuthService
    
    var body: some View {
        VStack(spacing: 30) {
            Image(systemName: "heart.text.square.fill")
                .resizable()
                .scaledToFit()
                .frame(width: 100, height: 100)
                .foregroundColor(.red)
            
            Text("Febus Health Sync")
                .font(.largeTitle)
                .fontWeight(.bold)
            
            Text("Private Apple Health to Firebase sync for AI agents.")
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
                .padding(.horizontal)
            
            Spacer()
            
            if authService.isAuthenticating {
                ProgressView("Signing in...")
            } else {
                // Using standard GoogleSignIn Button
                GoogleSignInButton(scheme: .dark, style: .wide, state: .normal) {
                    Task {
                        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                              let window = windowScene.windows.first,
                              let rootViewController = window.rootViewController else {
                            return
                        }
                        
                        do {
                            try await authService.signInWithGoogle(presentingViewController: rootViewController)
                        } catch {
                            print("Sign-in error: \(error.localizedDescription)")
                        }
                    }
                }
                .frame(height: 50)
                .padding(.horizontal, 40)
            }
            
            Spacer()
        }
        .padding()
    }
}
