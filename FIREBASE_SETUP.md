# Firebase Authentication Setup Guide

## 🔥 NutriBuddy Firebase Integration

Firebase authentication has been integrated into NutriBuddy with support for:

- **Google Sign-In** - Primary authentication method
- **Anonymous Sign-In** - Guest access with optional account upgrade
- **Cloud Firestore** - Real-time data sync across devices

---

## 📋 Setup Steps

### 1. Create Firebase Project

1. Go to [Firebase Console](https://console.firebase.google.com/)
2. Click **"Add Project"**
3. Project name: `nutribuddy-app` (or your preferred name)
4. Enable Google Analytics (optional)
5. Click **"Create Project"**

### 2. Add Web App to Firebase Project

1. In Firebase Console, click the **Web icon (</>)**
2. App nickname: `NutriBuddy Web`
3. Check **"Also set up Firebase Hosting"** (optional)
4. Click **"Register app"**
5. **Copy the Firebase configuration** - you'll need this below

### 3. Enable Authentication Methods

1. In Firebase Console, go to **"Authentication"** → **"Sign-in method"**
2. Enable **"Google"**:
   - Click "Google" provider
   - Toggle **"Enable"**
   - Enter support email
   - Save
3. Enable **"Anonymous"**:
   - Click "Anonymous" provider
   - Toggle **"Enable"**
   - Save

### 4. Set up Cloud Firestore

1. Go to **"Firestore Database"** in Firebase Console
2. Click **"Create database"**
3. Select **"Start in test mode"** (for development)
4. Choose your region (closest to your users)
5. Click **"Enable"**

**Production Rules (Update later):**

```javascript
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    // Users can only read/write their own data
    match /users/{userId} {
      allow read, write: if request.auth != null && request.auth.uid == userId;

      // User sub-collections (challenges, food history, etc.)
      match /{document=**} {
        allow read, write: if request.auth != null && request.auth.uid == userId;
      }
    }
  }
}
```

### 5. Configure Google Sign-In for Windows

1. In Firebase Console, go to **"Authentication"** → **"Settings"** → **"Authorized domains"**
2. Add `localhost` if not already present

For Windows desktop app:

```powershell
# No additional configuration needed for development
# The app will use web-based OAuth flow
```

### 6. Update Firebase Configuration in Code

Open `lib/main.dart` and replace the placeholder Firebase options (around line 71):

```dart
await Firebase.initializeApp(
  options: const FirebaseOptions(
    apiKey: 'YOUR_API_KEY',              // From Firebase Console
    appId: 'YOUR_APP_ID',                // From Firebase Console
    messagingSenderId: 'YOUR_SENDER_ID', // From Firebase Console
    projectId: 'your-project-id',        // Your Firebase project ID
    storageBucket: 'your-project.appspot.com', // Your storage bucket
    // For web authentication:
    authDomain: 'your-project.firebaseapp.com',
  ),
);
```

**Where to find these values:**

- Go to Firebase Console → Project Settings → General
- Scroll to "Your apps" → Select your web app
- Copy the values from the Firebase configuration object

---

## 🎨 Optional: Add Google Logo

For better UI, add a Google logo to your assets:

1. Create `assets/` folder if it doesn't exist
2. Download Google logo: [Google Brand Resource Center](https://about.google/brand-resource-center/)
3. Save as `assets/google_logo.png`
4. Update `pubspec.yaml`:

```yaml
flutter:
  assets:
    - assets/google_logo.png
```

---

## 🧪 Testing the Integration

### Test Anonymous Sign-In:

1. Run the app: `flutter run -d windows`
2. Click **"Continue as Guest"**
3. You should see the home screen
4. Check Firebase Console → Authentication → Users (should see anonymous user)

### Test Google Sign-In:

1. Click **"Continue with Google"**
2. Select your Google account
3. Grant permissions
4. You should see the home screen with your profile
5. Check Firebase Console → Authentication → Users (should see your Google account)

### Test Data Sync:

1. Sign in with Google
2. Select some health goals (e.g., "Muscle Gain")
3. Analyze a food item
4. Go to Firebase Console → Firestore Database
5. You should see:
   - `users/{userId}/selectedChallenges`
   - `users/{userId}/daily_nutrition/{date}`
   - `users/{userId}/food_history/{analysisId}`

### Test Account Upgrade:

1. Sign in as Guest
2. Select some goals and analyze foods
3. Go to Settings → **"Upgrade to Full Account"**
4. Complete Google Sign-In
5. Your data should be preserved and now linked to your Google account

---

## 🔒 Security Considerations

### Development Mode (Current):

✅ Test mode Firestore rules (anyone can read/write)
✅ API keys exposed in code (acceptable for development)

### Production Mode (Before Release):

❌ Update Firestore rules (see Step 4 above)
❌ Use environment variables for sensitive keys:

```dart
// Use flutter_dotenv or similar
final apiKey = dotenv.env['FIREBASE_API_KEY']!;
```

❌ Enable App Check for additional security
❌ Set up proper security rules for Cloud Storage if using images

---

## 🌐 Multi-Platform Setup (Future)

### Android:

1. Add Android app in Firebase Console
2. Download `google-services.json`
3. Place in `android/app/`
4. Follow [FlutterFire setup](https://firebase.flutter.dev/docs/overview)

### iOS:

1. Add iOS app in Firebase Console
2. Download `GoogleService-Info.plist`
3. Place in `ios/Runner/`
4. Configure URL schemes
5. Follow [FlutterFire setup](https://firebase.flutter.dev/docs/overview)

---

## 🐛 Troubleshooting

### "Firebase initialization error"

- Check that your Firebase configuration is correct
- Ensure you're connected to the internet
- Verify project ID matches your Firebase project

### "Google Sign-In failed"

- Check that Google provider is enabled in Firebase Console
- Ensure `localhost` is in authorized domains
- Clear browser cache if using web view

### "Permission denied" in Firestore

- Check Firestore security rules
- Ensure you're signed in
- Verify user ID matches the document path

### "No data syncing"

- Check console for error messages
- Verify Firestore is enabled
- Check your internet connection
- Look at Firebase Console → Firestore to see if writes are happening

---

## 📚 Additional Resources

- [Firebase Documentation](https://firebase.google.com/docs)
- [FlutterFire Documentation](https://firebase.flutter.dev/)
- [Google Sign-In Plugin](https://pub.dev/packages/google_sign_in)
- [Cloud Firestore Guide](https://firebase.google.com/docs/firestore)

---

## 🎯 What's Working Now

✅ Google Sign-In with OAuth flow
✅ Anonymous authentication for guest users  
✅ Account upgrade (guest → Google account)
✅ Cloud Firestore data sync
✅ User profile management
✅ Settings screen with account controls
✅ Persistent challenge selection across devices
✅ Food analysis history saved to cloud
✅ Daily nutrition totals tracked in Firestore

---

## 🚀 Next Steps

After setting up Firebase:

1. Test all authentication flows
2. Verify data is syncing to Firestore
3. Set up proper security rules (production)
4. Add analytics tracking (optional)
5. Implement password reset flow (if adding email/password)
6. Add social features (friend challenges, leaderboards)

**Happy coding! 🎉**
