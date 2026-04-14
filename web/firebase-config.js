// Import the functions you need from the SDKs you need
import { initializeApp } from 'firebase/app';
import { getAnalytics } from 'firebase/analytics';
import {
  getAuth,
  setPersistence,
  browserLocalPersistence,
  signInWithPopup,
  GoogleAuthProvider,
} from 'firebase/auth';
import { getFirestore } from 'firebase/firestore';

// Your web app's Firebase configuration
const firebaseConfig = {
  apiKey: 'AIzaSyD-4aQeMTxdHpcKS0mzhSz0gkS_iVIbejk',
  authDomain: 'nutribuddy-4e3b7.firebaseapp.com',
  projectId: 'nutribuddy-4e3b7',
  storageBucket: 'nutribuddy-4e3b7.firebasestorage.app',
  messagingSenderId: '328896889583',
  appId: '1:328896889583:web:d7ab1275df9d1794d0511a',
  measurementId: 'G-K91GM15PK3',
};

// Initialize Firebase
const app = initializeApp(firebaseConfig);

// Initialize Analytics
const analytics = getAnalytics(app);

// Initialize Firebase Authentication and set persistence
const auth = getAuth(app);
setPersistence(auth, browserLocalPersistence).catch(error => {
  console.error('Auth persistence error:', error);
});

// Initialize Firestore
const db = getFirestore(app);

// Configure Google Sign-In Provider
const googleProvider = new GoogleAuthProvider();
// Request specific scopes for user profile
googleProvider.addScope('profile');
googleProvider.addScope('email');

// Export for use in other modules
export { app, auth, db, analytics, googleProvider, signInWithPopup };

// Helper function for Google Sign-In
export const signInWithGoogle = async () => {
  try {
    const result = await signInWithPopup(auth, googleProvider);
    console.log('User signed in:', result.user.email);
    return result.user;
  } catch (error) {
    console.error('Google Sign-In error:', error.code, error.message);

    // Handle specific error codes
    if (error.code === 'auth/popup-blocked') {
      alert('Sign-in popup was blocked. Please allow popups for this site.');
    } else if (error.code === 'auth/popup-closed-by-user') {
      console.log('User closed the sign-in popup');
    } else if (error.code === 'auth/cancelled-popup-request') {
      console.log('Multiple popups were requested');
    }

    throw error;
  }
};

// Helper function to get current user
export const getCurrentUser = () => {
  return auth.currentUser;
};

// Helper function for sign out
export const signOutUser = async () => {
  try {
    await auth.signOut();
    console.log('User signed out');
  } catch (error) {
    console.error('Sign-out error:', error);
    throw error;
  }
};
