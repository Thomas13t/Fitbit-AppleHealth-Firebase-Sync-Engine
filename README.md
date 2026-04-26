# Febus Health Sync

A private iOS application to sync Apple Health/Fitness data to Firebase Firestore, built specifically to act as a data pipeline for AI integration (OpenClaw / Antigravity). 

## Features
- **Google Sign-In**: Powered by Firebase Authentication.
- **HealthKit Integration**: Requests granular permissions for workouts, heart rate, step count, and active energy.
- **Background Sync**: Uses `HKObserverQuery` and `enableBackgroundDelivery` to keep your Firestore database up to date whenever a new workout is completed.
- **Manual Sync**: Pulls the last 30 days of workouts.
- **Cloud Functions Scaffold**: Ready to generate daily or weekly insight reports.

---

## 🛠 Setup Instructions

This repository contains the source files. Because Xcode project formats are proprietary, you need to scaffold the initial Xcode project yourself, then drop these files in.

### Step 1: Create the Firebase Project
1. Go to the [Firebase Console](https://console.firebase.google.com/).
2. Create a new project named **Febus Health Sync**.
3. Go to **Authentication** > **Sign-in method** and enable **Google**.
4. Go to **Firestore Database** and create a new database.
5. In the Firebase console, add an **iOS App** with the bundle identifier you plan to use (e.g., `com.febus.healthsync`).
6. Download the `GoogleService-Info.plist` file. Keep this handy.

### Step 2: Create the Xcode Project
1. Open Xcode and create a new **App** project.
2. Name the product `FebusHealthSync`.
3. Set the interface to **SwiftUI** and language to **Swift**.
4. Choose your bundle identifier (e.g., `com.febus.healthsync`).

### Step 3: Add the Code
1. Drag the `FebusHealthSync` folder from this repository directly into your Xcode project navigator (replace the default files).
2. Drag your downloaded `GoogleService-Info.plist` into the Xcode project navigator.

### Step 4: Configure Xcode Capabilities & Info.plist
1. Select your target in Xcode, go to **Signing & Capabilities**.
2. Click **+ Capability** and add:
   - **HealthKit** (Check the box for Background Delivery).
   - **Background Modes** (Check the boxes for *Background fetch* and *Background processing*).
3. Go to the **Info** tab of your target and add these Privacy keys:
   - `Privacy - Health Share Usage Description`: "Febus Health Sync needs access to your workouts to back them up to your private database."
   - `Privacy - Health Update Usage Description`: "Febus Health Sync needs access to your workouts to back them up to your private database."
4. Add the **Google Sign-In URL Scheme**:
   - In Xcode, click your project in the Project Navigator, select your target, and go to the **Info** tab.
   - Scroll down to **URL Types** and click the **+** button.
   - In the **URL Schemes** field, paste your `REVERSED_CLIENT_ID` (e.g., `com.googleusercontent.apps.215284107318-xxxxxxxxxxxxxxx`).
   - Leave the Role as `Editor` and Identifier blank.

### Step 5: Install Dependencies via Swift Package Manager
To confirm FirebaseAuth, Firestore, and GoogleSignIn are correctly installed:
1. In Xcode, go to **File** > **Add Package Dependencies...**
2. Search for `https://github.com/firebase/firebase-ios-sdk`
   - Select **Up to Next Major Version** (e.g., 10.0.0 or 11.0.0).
   - Click **Add Package**.
   - Check `FirebaseAuth`, `FirebaseFirestore`, and `FirebaseFirestoreSwift`.
3. Search for `https://github.com/google/GoogleSignIn-iOS`
   - Select **Up to Next Major Version** (e.g., 7.0.0).
   - Click **Add Package**.
   - Check `GoogleSignIn` and `GoogleSignInSwift`.

### Step 6: Deploy Firebase Backend
1. Open your terminal and navigate to the `firebase` folder in this repo.
2. Run `firebase login` (if not already logged in).
3. Run `firebase init` and select the project you created.
4. Deploy the security rules:
   ```bash
   firebase deploy --only firestore:rules
   ```
5. Deploy the Cloud Functions scaffold:
   ```bash
   cd functions
   npm install
   npm run deploy
   ```

---

## 🚀 Running the App
1. Build and run the app on a **physical iPhone** (HealthKit does not function correctly on the Xcode Simulator).
2. Tap the "Sign in with Google" button.
3. Accept the HealthKit permissions prompt.
4. Tap "Manual Sync" to back up your last 30 days of workouts!
