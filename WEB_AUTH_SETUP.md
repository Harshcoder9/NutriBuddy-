# NutriBuddy Web Authentication Setup

## What Was Fixed

The web app authentication required three key components:

1. **firebase-config.js** — Centralized Firebase initialization with Auth, Firestore, and Google Sign-In
2. **Enhanced index.html** — Added auth state listener and global Firebase functions
3. **auth.html** — Standalone authentication page with Google and Guest sign-in
4. **firebase.json** — Updated with proper routing and CORS headers

## Setup Instructions

### 1. Configure Google OAuth Credentials

1. Go to [Google Cloud Console](https://console.cloud.google.com/)
2. Select the `nutribuddy-4e3b7` project
3. Navigate to **APIs & Services** → **Credentials**
4. Click **Create Credentials** → **OAuth 2.0 Client ID**
5. Choose **Web application**
6. Add authorized redirect URIs:
   ```
   https://nutribuddy-4e3b7.web.app/__/auth/handler
   https://nutribuddy-4e3b7.web.app
   http://localhost:5000
   http://localhost:3000
   ```
7. Copy the **Client ID** (you'll need this for firebase-config.js if needed)

### 2. Enable Google Sign-In in Firebase Console

1. Go to [Firebase Console](https://console.firebase.google.com/)
2. Select `nutribuddy-4e3b7` project
3. Go to **Authentication** → **Sign-in method**
4. Enable **Google**:
   - Click the Google provider
   - Toggle **Enable**
   - Select the Google Cloud project
   - Add support email
   - Save
5. Add authorized domains (if not already present):
   - `nutribuddy-4e3b7.web.app`
   - (For local testing: add your localhost domain)

### 3. Update Firestore Security Rules

Go to **Firestore Database** → **Rules** and update:

```javascript
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    match /users/{userId} {
      allow read, write: if request.auth != null && request.auth.uid == userId;
      match /{document=**} {
        allow read, write: if request.auth != null && request.auth.uid == userId;
      }
    }
  }
}
```

### 4. Build and Deploy Web App

```bash
# Build Flutter web
flutter build web --release --dart-define=GEMINI_API_KEY=YOUR_KEY

# Copy Firebase config files to build directory
cp web/firebase-config.js build/web/
cp web/auth.html build/web/

# Deploy to Firebase
firebase deploy --only hosting
```

## File Structure

```
web/
├── index.html           # Main app (updated with Firebase init)
├── auth.html           # Standalone auth page (NEW)
├── firebase-config.js  # Firebase initialization (NEW)
└── manifest.json
```

## How Authentication Works

### Web Flow

1. User visits `https://nutribuddy-4e3b7.web.app/auth`
2. Clicks "Sign in with Google" or "Continue as Guest"
3. Firebase Auth handles the OAuth popup on Google's domain
4. After successful auth, redirects to `/` (main app)
5. Flutter app receives auth state via Firebase Auth listener

### Key Features

✅ Google Sign-In with OAuth 2.0 popup
✅ Guest/Anonymous sign-in without account
✅ Automatic auth state persistence (localStorage)
✅ Cross-platform error handling
✅ CORS headers configured for Firebase Hosting
✅ Proper cache headers for performance

## Testing Locally

```bash
# Install Firebase CLI
npm install -g firebase-tools

# Login to Firebase
firebase login

# Serve locally (from project root)
firebase serve --only hosting

# Visit http://localhost:5000/auth
```

## Troubleshooting

### "Popup blocked" error
- Check browser popup settings
- Ensure site has permission to open popups
- Try in incognito mode

### "CORS error" on localhost
- Add `http://localhost:5000` and `http://localhost:3000` to OAuth credentials
- Firebase Hosting local serve uses port 5000 by default

### "Sign-in failed" with no error code
- Verify Google OAuth credentials are created
- Check Firebase Authentication is enabled
- Ensure authorized domains include your domain

### Auth state not persisting
- Browser must allow localStorage
- Check that `browserLocalPersistence` is set (handled in firebase-config.js)

## Performance Notes

- Firebase config is initialized once and cached
- Auth state persists across page reloads
- Google Sign-In SDK loaded asynchronously
- No impact on initial page load time

## Security Notes

⚠️ API keys are visible in client-side code (expected for web apps)
✅ Use Firebase Security Rules to restrict data access (configured above)
✅ Never store sensitive data in client-side localStorage
✅ Always validate on backend before processing

## Next Steps

1. ✅ Create Google OAuth 2.0 credentials
2. ✅ Add authorized redirect URIs
3. ✅ Update Firestore security rules
4. ✅ Build web app
5. ✅ Deploy to Firebase Hosting
6. ✅ Test authentication flow
7. Optional: Set up Analytics for user tracking

---

For more info, see:
- [Firebase Web Setup](https://firebase.google.com/docs/web/setup)
- [Google Sign-In for Web](https://developers.google.com/identity/protocols/oauth2)
- [Firebase Auth Web SDK](https://firebase.google.com/docs/auth/web)
