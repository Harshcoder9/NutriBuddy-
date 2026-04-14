import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final GoogleSignIn _googleSignIn = GoogleSignIn();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // Get current user
  User? get currentUser => _auth.currentUser;

  // Auth state changes stream
  Stream<User?> get authStateChanges => _auth.authStateChanges();

  // Check if user is signed in
  bool get isSignedIn => _auth.currentUser != null;

  // Sign in with Google
  Future<UserCredential?> signInWithGoogle() async {
    try {
      if (kIsWeb) {
        // For web, use Firebase's built-in OAuth flow
        return await _signInWithGoogleWeb();
      } else {
        // For native platforms, use google_sign_in package
        return await _signInWithGoogleNative();
      }
    } catch (e) {
      debugPrint('Error signing in with Google: $e');
      rethrow;
    }
  }

  // Native platform Google Sign-In
  Future<UserCredential?> _signInWithGoogleNative() async {
    try {
      final GoogleSignInAccount? googleUser = await _googleSignIn.signIn();

      if (googleUser == null) {
        return null;
      }

      final GoogleSignInAuthentication googleAuth =
          await googleUser.authentication;

      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      final userCredential = await _auth.signInWithCredential(credential);

      if (userCredential.user != null) {
        await _createUserProfileIfNeeded(userCredential.user!);
      }

      return userCredential;
    } catch (e) {
      debugPrint('Error in native Google Sign-In: $e');
      rethrow;
    }
  }

  // Web platform Google Sign-In using Firebase's OAuth
  Future<UserCredential?> _signInWithGoogleWeb() async {
    try {
      final GoogleAuthProvider googleProvider = GoogleAuthProvider();
      googleProvider.addScope('profile');
      googleProvider.addScope('email');

      final userCredential = await _auth.signInWithPopup(googleProvider);

      if (userCredential.user != null) {
        await _createUserProfileIfNeeded(userCredential.user!);
      }

      return userCredential;
    } catch (e) {
      debugPrint('Error in web Google Sign-In: $e');
      // Check for specific web errors
      if (e.toString().contains('popup-blocked')) {
        throw Exception('Sign-in popup was blocked. Please allow popups.');
      }
      rethrow;
    }
  }

  // Sign in anonymously
  Future<UserCredential> signInAnonymously() async {
    try {
      final userCredential = await _auth.signInAnonymously();

      // Create anonymous user profile
      if (userCredential.user != null) {
        await _createUserProfileIfNeeded(userCredential.user!);
      }

      return userCredential;
    } catch (e) {
      debugPrint('Error signing in anonymously: $e');
      rethrow;
    }
  }

  // Sign out
  Future<void> signOut() async {
    try {
      if (kIsWeb) {
        // Web only needs Firebase sign out
        await _auth.signOut();
      } else {
        // Native platforms need both Firebase and GoogleSignIn sign out
        await Future.wait([_auth.signOut(), _googleSignIn.signOut()]);
      }
    } catch (e) {
      debugPrint('Error signing out: $e');
      rethrow;
    }
  }

  // Create user profile in Firestore
  Future<void> _createUserProfileIfNeeded(User user) async {
    final userDoc = _firestore.collection('users').doc(user.uid);
    final docSnapshot = await userDoc.get();

    if (!docSnapshot.exists) {
      await userDoc.set({
        'uid': user.uid,
        'email': user.email,
        'displayName': user.displayName,
        'photoURL': user.photoURL,
        'isAnonymous': user.isAnonymous,
        'createdAt': FieldValue.serverTimestamp(),
        'lastLoginAt': FieldValue.serverTimestamp(),
      });
    } else {
      // Update last login time
      await userDoc.update({'lastLoginAt': FieldValue.serverTimestamp()});
    }
  }

  // Upgrade anonymous account to Google account
  Future<UserCredential?> upgradeAnonymousWithGoogle() async {
    try {
      if (!_auth.currentUser!.isAnonymous) {
        throw Exception('User is not anonymous');
      }

      if (kIsWeb) {
        // Web: use Firebase OAuth
        final GoogleAuthProvider googleProvider = GoogleAuthProvider();
        googleProvider.addScope('profile');
        googleProvider.addScope('email');

        final userCredential = await _auth.currentUser!.linkWithPopup(googleProvider);

        if (userCredential.user != null) {
          await _firestore
              .collection('users')
              .doc(userCredential.user!.uid)
              .update({
                'email': userCredential.user!.email,
                'displayName': userCredential.user!.displayName,
                'photoURL': userCredential.user!.photoURL,
                'isAnonymous': false,
                'upgradedAt': FieldValue.serverTimestamp(),
              });
        }

        return userCredential;
      } else {
        // Native: use google_sign_in package
        final GoogleSignInAccount? googleUser = await _googleSignIn.signIn();

        if (googleUser == null) {
          return null;
        }

        final GoogleSignInAuthentication googleAuth =
            await googleUser.authentication;

        final credential = GoogleAuthProvider.credential(
          accessToken: googleAuth.accessToken,
          idToken: googleAuth.idToken,
        );

        final userCredential = await _auth.currentUser!.linkWithCredential(credential);

        if (userCredential.user != null) {
          await _firestore
              .collection('users')
              .doc(userCredential.user!.uid)
              .update({
                'email': userCredential.user!.email,
                'displayName': userCredential.user!.displayName,
                'photoURL': userCredential.user!.photoURL,
                'isAnonymous': false,
                'upgradedAt': FieldValue.serverTimestamp(),
              });
        }

        return userCredential;
      }
    } catch (e) {
      debugPrint('Error upgrading anonymous account: $e');
      rethrow;
    }
  }

  // Delete account
  Future<void> deleteAccount() async {
    try {
      final user = _auth.currentUser;
      if (user == null) {
        throw Exception('No user logged in');
      }

      debugPrint('Starting account deletion for user: ${user.uid}');
      debugPrint('User email: ${user.email}');
      debugPrint('User is anonymous: ${user.isAnonymous}');

      // Delete user data from Firestore first (with error tolerance)
      try {
        debugPrint('Deleting Firestore data...');

        // Try to delete challenges
        try {
          final challengesSnapshot = await _firestore
              .collection('users')
              .doc(user.uid)
              .collection('challenges')
              .get();

          for (var doc in challengesSnapshot.docs) {
            await doc.reference.delete();
          }
          debugPrint('Deleted ${challengesSnapshot.docs.length} challenges');
        } catch (e) {
          debugPrint('Error deleting challenges: $e - continuing...');
        }

        // Try to delete food history
        try {
          final foodHistorySnapshot = await _firestore
              .collection('users')
              .doc(user.uid)
              .collection('foodHistory')
              .get();

          for (var doc in foodHistorySnapshot.docs) {
            await doc.reference.delete();
          }
          debugPrint('Deleted ${foodHistorySnapshot.docs.length} food items');
        } catch (e) {
          debugPrint('Error deleting food history: $e - continuing...');
        }

        // Delete daily totals
        try {
          final dailyTotalsSnapshot = await _firestore
              .collection('users')
              .doc(user.uid)
              .collection('dailyTotals')
              .get();

          for (var doc in dailyTotalsSnapshot.docs) {
            await doc.reference.delete();
          }
          debugPrint('Deleted ${dailyTotalsSnapshot.docs.length} daily totals');
        } catch (e) {
          debugPrint('Error deleting daily totals: $e - continuing...');
        }

        // Delete main user document
        try {
          await _firestore.collection('users').doc(user.uid).delete();
          debugPrint('Deleted user document');
        } catch (e) {
          debugPrint('Error deleting user document: $e - continuing...');
        }
      } catch (e) {
        debugPrint(
          'Firestore deletion error: $e - continuing to delete auth account...',
        );
      }

      // Delete Firebase auth account
      debugPrint('Deleting Firebase auth account...');
      try {
        await user.delete();
        debugPrint('Auth account deleted successfully');
      } catch (e) {
        debugPrint('Auth deletion error: $e');
        // Check if it's a requires-recent-login error
        if (e.toString().contains('requires-recent-login')) {
          // Sign out the user so they can sign in fresh and try again
          await signOut();
          throw Exception(
            'For security, please sign in again and then delete your account',
          );
        }
        rethrow;
      }

      // Sign out from Google if needed
      try {
        await _googleSignIn.signOut();
      } catch (e) {
        debugPrint('Error signing out of Google: $e');
      }

      debugPrint('Account deletion completed successfully');
    } catch (e) {
      debugPrint('Error deleting account: $e');
      rethrow;
    }
  }
}


