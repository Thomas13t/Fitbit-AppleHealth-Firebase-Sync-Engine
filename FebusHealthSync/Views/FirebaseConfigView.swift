import SwiftUI

struct FirebaseConfigView: View {
    var onConfigured: () -> Void
    
    @StateObject private var configManager = FirebaseConfigManager.shared
    @State private var plistContent: String = ""
    
    @State private var apiKey: String = ""
    @State private var projectID: String = ""
    @State private var googleAppID: String = ""
    @State private var clientID: String = ""
    @State private var senderID: String = ""
    
    @State private var errorMessage: String? = nil
    @State private var successMessage: String? = nil
    @State private var showManualConfig: Bool = false
    @State private var isValidating: Bool = false
    
    var body: some View {
        ScrollView {
            VStack(spacing: 25) {
                // Header / Welcome Section
                VStack(spacing: 12) {
                    Image(systemName: "lock.shield.fill")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 80, height: 80)
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.cyan, .purple],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .padding(.top, 40)
                    
                    Text("Febus Health Sync")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                    
                    Text("Bring Your Own Database (BYODB)")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.cyan)
                    
                    Text("Your health data remains 100% private. Sync your data directly from your iPhone to your personal Firebase database.")
                        .font(.body)
                        .multilineTextAlignment(.center)
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 30)
                }
                
                // Alert Banner
                if let errorMessage = errorMessage {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.yellow)
                        Text(errorMessage)
                            .font(.subheadline)
                            .foregroundColor(.white)
                    }
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(Color.red.opacity(0.3))
                    .cornerRadius(12)
                    .padding(.horizontal)
                    .transition(.opacity)
                }
                
                if let successMessage = successMessage {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        Text(successMessage)
                            .font(.subheadline)
                            .foregroundColor(.white)
                    }
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(Color.green.opacity(0.3))
                    .cornerRadius(12)
                    .padding(.horizontal)
                    .transition(.opacity)
                }
                
                // Copy-Paste Plist Option (Preferred)
                VStack(alignment: .leading, spacing: 12) {
                    Text("1. Paste your GoogleService-Info.plist")
                        .font(.headline)
                        .foregroundColor(.white)
                    
                    Text("Open the GoogleService-Info.plist file downloaded from your Firebase console, copy the entire XML text, and paste it below:")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                    
                    TextEditor(text: $plistContent)
                        .frame(height: 180)
                        .padding(10)
                        .background(Color(uiColor: .secondarySystemBackground))
                        .cornerRadius(12)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                        )
                        .onChange(of: plistContent) { _, newValue in
                            autoParsePlist(newValue)
                        }
                }
                .padding(.horizontal)
                
                // Manual Config Form Accordion
                VStack(alignment: .leading, spacing: 10) {
                    Button(action: {
                        withAnimation {
                            showManualConfig.toggle()
                        }
                    }) {
                        HStack {
                            Text("Advanced Manual Options")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                                .foregroundColor(.secondary)
                            Spacer()
                            Image(systemName: showManualConfig ? "chevron.up" : "chevron.down")
                                .foregroundColor(.secondary)
                        }
                        .padding(.vertical, 8)
                    }
                    
                    if showManualConfig {
                        VStack(spacing: 15) {
                            customTextField(title: "API Key", text: $apiKey, placeholder: "AIzaSy...")
                            customTextField(title: "Project ID", text: $projectID, placeholder: "my-health-sync-project")
                            customTextField(title: "Google Application ID", text: $googleAppID, placeholder: "1:215284107318:ios:0956b6c0...")
                            customTextField(title: "Sender ID", text: $senderID, placeholder: "215284107318")
                            customTextField(title: "Google Client ID (optional)", text: $clientID, placeholder: "215284107318-22qlq74hp88c8n...")
                        }
                        .transition(.slide)
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
                .background(Color(uiColor: .systemBackground).opacity(0.5))
                .cornerRadius(12)
                .padding(.horizontal)
                
                // Submit Button
                Button(action: {
                    validateAndSave()
                }) {
                    HStack {
                        if isValidating {
                            ProgressView()
                                .tint(.black)
                                .padding(.trailing, 8)
                        }
                        Text(isValidating ? "Validating..." : "Configure Database")
                            .font(.headline)
                            .foregroundColor(.black)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(Color.cyan)
                    .cornerRadius(12)
                    .shadow(color: Color.cyan.opacity(0.3), radius: 8, x: 0, y: 4)
                }
                .disabled(isValidating || (apiKey.isEmpty || projectID.isEmpty || googleAppID.isEmpty))
                .padding(.horizontal, 30)
                .padding(.top, 10)
                
                Spacer(minLength: 30)
            }
        }
        .background(Color(uiColor: .systemBackground))
        .preferredColorScheme(.dark)
    }
    
    // MARK: - Helper Methods
    
    private func customTextField(title: String, text: Binding<String>, placeholder: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
            
            TextField(placeholder, text: text)
                .padding()
                .background(Color(uiColor: .secondarySystemBackground))
                .cornerRadius(10)
                .textInputAutocapitalization(.none)
                .autocorrectionDisabled()
        }
    }
    
    private func autoParsePlist(_ xml: String) {
        guard let parsed = configManager.parsePlistXML(xml) else { return }
        
        withAnimation {
            self.apiKey = parsed["API_KEY"] ?? ""
            self.projectID = parsed["PROJECT_ID"] ?? ""
            self.googleAppID = parsed["GOOGLE_APP_ID"] ?? ""
            self.clientID = parsed["CLIENT_ID"] ?? ""
            self.senderID = parsed["GCM_SENDER_ID"] ?? ""
            self.successMessage = "XML plist successfully detected and parsed!"
            self.errorMessage = nil
        }
    }
    
    private func validateAndSave() {
        self.isValidating = true
        self.errorMessage = nil
        self.successMessage = nil
        
        // Defer execution slightly to show loader and trigger validation
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            configManager.saveConfig(
                apiKey: self.apiKey,
                projectID: self.projectID,
                googleAppID: self.googleAppID,
                clientID: self.clientID.isEmpty ? nil : self.clientID,
                senderID: self.senderID.isEmpty ? nil : self.senderID
            )
            
            let success = configManager.configureFirebase()
            
            self.isValidating = false
            if success {
                withAnimation {
                    self.successMessage = "Firebase database successfully configured and activated!"
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                    onConfigured()
                }
            } else {
                withAnimation {
                    self.errorMessage = "Error initializing FirebaseOptions. Please verify your parameters."
                }
            }
        }
    }
}

#Preview {
    FirebaseConfigView(onConfigured: {})
}
