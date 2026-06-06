# HealthSync: Fitbit & Apple Health to Firebase Sync Engine (BYODB)

**HealthSync** is a privacy-first, universal client-side iOS application built to synchronize **Apple HealthKit** metrics and **Fitbit / Google Health** data directly into your private **Firebase Firestore** database.

This project is designed specifically under the **"Bring Your Own Database" (BYODB)** architectural model. You host your own free Firebase project, meaning **your sensitive health data remains 100% private, secure, and under your control**, while hosting infrastructure costs remain at exactly **$0**.

This repository serves as a turnkey data pipeline for developers feeding personal metrics into custom **AI Agents** (e.g., OpenClaw, Antigravity, or personal LLM pipelines).

---

## 🌟 Key Features

- **Authentication**: The personal build uses Google Sign-In. The universal BYODB build uses Firebase anonymous auth so a single App Store binary can work with a user-provided Firebase project.
- **Dynamic Firebase Config (BYODB)**: Configure your private database inside the app by simply copy-pasting your raw `GoogleService-Info.plist` XML. 
- **Granular HealthKit Syncing**: Reads workouts, step count, active calories, heart rate, respiratory rate, HRV, SpO2, temperature, exercise minutes, floors, sleep, and distance directly from Apple Health.
- **Google Health / Fitbit Import**: Secure Google OAuth 2.0 flow that fetches sleep sessions, steps, heart rate, resting heart rate, respiratory rate, HRV, SpO2, sleep temperature, active minutes, Active Zone Minutes, calories, distance, floors, and workouts from the Google Health API and writes supported values directly to Apple Health.
  - *Note on Sleep Vitals*: To ensure imported metrics (HRV, SpO2, Respiratory Rate, Wrist Temperature) correctly appear under the "Sleep" section in Apple Health, they are assigned a timestamp of 03:00 AM. 
  - *Note on Temperature*: The app utilizes `.appleSleepingWristTemperature` (requires iOS 16+) for more accurate sleep temperature tracking, falling back to general `.bodyTemperature` on older OS versions.
- **Background Delivery**: Leverages `BGTaskScheduler` and HealthKit workout observers to synchronize Apple Health summaries in the background. Google Health imports currently run from the in-app sync action.
- **Multi-Target Architecture**: The Xcode project includes two schemes:
  1. `FebusHealthSyncIos` (Personal hardcoded build).
  2. `FebusHealthSyncUniversal` (White-label dynamic onboarding build).

---

## 🛠️ Step-by-Step Setup Guide

This repository contains a fully configured, out-of-the-box Xcode project. You do not need to scaffold anything from scratch.

### Prerequisites
- A Mac running **macOS 15+** with **Xcode 16+** installed.
- A free **Google Cloud / Firebase Console** account.
- A **physical iPhone** (HealthKit data reading and background delivery require a physical device; they are restricted on the Simulator).

---

### Step 1: Firebase Project Setup
1. Go to the [Firebase Console](https://console.firebase.google.com/) and create a new project.
2. Navigate to **Build > Authentication > Sign-in Method**.
   - For the **Universal BYODB** build, enable **Anonymous** authentication.
   - For a custom/personal Google Sign-In build, enable **Google** authentication.
3. Navigate to **Build > Firestore Database** and click **Create Database**. Start in production mode.
4. Add an **iOS App** to your Firebase project. Use a custom Bundle ID of your choice (e.g., `com.yourname.HealthSync`).
5. Download your generated `GoogleService-Info.plist` file. Keep this handy.

---

### Step 2: Enable the Google Health API (For Fitbit / Google Health data)
Because new Fitbit integrations are moving through Google Health API, you must enable it on your Google Cloud project:
1. Go to the [Google Cloud Console](https://console.cloud.google.com/).
2. Select the Google Cloud project associated with your Firebase project.
3. Navigate to **APIs & Services > Library**.
4. Search for **Google Health API**, select it, and click **Enable**.
5. Navigate to **APIs & Services > OAuth Consent Screen**, set user type to **External**, and add your email to the **Test Users** list (required while your project is in Testing mode).
6. Add the required OAuth scopes:
   - `https://www.googleapis.com/auth/googlehealth.activity_and_fitness.readonly`
   - `https://www.googleapis.com/auth/googlehealth.health_metrics_and_measurements.readonly`
   - `https://www.googleapis.com/auth/googlehealth.sleep.readonly`

---

### Step 3: Clone and Open in Xcode
1. Clone this repository to your local Mac.
2. Open the Xcode workspace directory: `FebusHealthSyncIos/FebusHealthSyncIos.xcodeproj`.
3. In the top scheme dropdown menu in Xcode, select **`FebusHealthSyncUniversal`**.
4. Select your main project target, navigate to **Signing & Capabilities**:
   - Check **Automatically manage signing**.
   - Select your personal Apple Developer team account.
   - Change the **Bundle Identifier** to match the Bundle ID you registered in your Firebase Console (e.g., `com.yourname.HealthSync`).
5. Click **+ Capability** in the top left of the panel and ensure **HealthKit** (with Background Delivery checked) and **Background Modes** (with *Background Fetch* and *Background Processing* checked) are enabled.

---

### Step 4: Configure the App-Owned Google Health OAuth Client
The universal App Store build cannot dynamically register every user's Google reversed client ID after installation. Instead, it uses a fixed app-owned OAuth client for the Fitbit/Google Fitness import flow, while the user's Firebase project remains their private data destination.

Before publishing your own universal build:
1. Create an iOS OAuth client in Google Cloud for the universal app bundle identifier.
2. Enable the Google Health API for that Google Cloud project.
3. In `FebusHealthSyncIos/FebusHealthSyncIos/Info.plist`, set:
   - `FebusGoogleOAuthClientID`
   - `FebusGoogleOAuthCallbackScheme`
4. Confirm the callback scheme is also listed under `CFBundleURLTypes`.

For the personal build, the bundled `GoogleService-Info.plist` and URL scheme continue to provide this configuration.

---

### Step 5: Build, Run, and Onboard!
1. Connect your physical iPhone to your Mac.
2. Select your physical iPhone as the destination device next to the `FebusHealthSyncUniversal` scheme in Xcode.
3. Click the **Play (⌘ R)** button.
4. On your iPhone, the app will boot into the sleek **Welcome and Onboarding** screen.
5. Open your `GoogleService-Info.plist` file, copy its entire XML text, and paste it directly into the text area in the app.
6. Tap **Configure Database**. The app will automatically parse your `API Key`, `Project ID`, and `App ID`, securely configure Firebase on-the-fly, and transition to the sign-in screen.
7. Tap **Continue Privately**, authorize HealthKit permissions, optionally link Google Health / Fitbit, and you are ready to sync.

---

### Step 6: Deploy Database Security Rules
To secure your Firestore database so that only you can access your personal health data:
1. Install the Firebase Command Line Tools in your terminal: `npm install -g firebase-tools`
2. Run `firebase login` to authenticate.
3. Navigate to the `firebase/` directory in this repository.
4. Associate the directory with your Firebase project: `firebase use --add [your-project-id]`
5. Deploy the security rules:
   ```bash
   firebase deploy --only firestore:rules
   ```

---

## 🔒 Security Rules & Privacy Schema

The deployed Firestore security rules enforce strict user-level isolation. No user can read or write any document outside of their own user record:

```javascript
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    match /users/{userId} {
      allow read, write: if request.auth != null && request.auth.uid == userId;
      
      match /{subcollection=**} {
        allow read, write: if request.auth != null && request.auth.uid == userId;
      }
    }
  }
}
```

### Deployed Firestore Data Layout:
- `/users/{userId}`: General profile parameters.
- `/users/{userId}/workouts/{workoutId}`: Detailed workouts synced from Apple Health.
- `/users/{userId}/dailySummaries/{date}`: Daily step totals, active energy burn, distance, floors, exercise minutes, heart rate, resting heart rate, respiratory rate, HRV, SpO2, temperature, and sleep duration.
