import 'package:firebase_auth/firebase_auth.dart';
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
      // Trigger the Google Sign-In flow
      final GoogleSignInAccount? googleUser = await _googleSignIn.signIn();

      if (googleUser == null) {
        // User canceled the sign-in
        return null;
      }

      // Obtain the auth details from the request
      final GoogleSignInAuthentication googleAuth =
          await googleUser.authentication;

      // Create a new credential
      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      // Sign in to Firebase with the Google credential
      final userCredential = await _auth.signInWithCredential(credential);

      // Create user profile in Firestore if it doesn't exist
      if (userCredential.user != null) {
        await _createUserProfileIfNeeded(userCredential.user!);
      }

      return userCredential;
    } catch (e) {
      print('Error signing in with Google: $e');
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
      print('Error signing in anonymously: $e');
      rethrow;
    }
  }

  // Sign out
  Future<void> signOut() async {
    try {
      await Future.wait([_auth.signOut(), _googleSignIn.signOut()]);
    } catch (e) {
      print('Error signing out: $e');
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

      // Trigger the Google Sign-In flow
      final GoogleSignInAccount? googleUser = await _googleSignIn.signIn();

      if (googleUser == null) {
        return null;
      }

      // Obtain the auth details
      final GoogleSignInAuthentication googleAuth =
          await googleUser.authentication;

      // Create credential
      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      // Link the anonymous account with Google credential
      final userCredential = await _auth.currentUser!.linkWithCredential(
        credential,
      );

      // Update user profile
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
    } catch (e) {
      print('Error upgrading anonymous account: $e');
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

      print('Starting account deletion for user: ${user.uid}');
      print('User email: ${user.email}');
      print('User is anonymous: ${user.isAnonymous}');

      // Delete user data from Firestore first (with error tolerance)
      try {
        print('Deleting Firestore data...');

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
          print('Deleted ${challengesSnapshot.docs.length} challenges');
        } catch (e) {
          print('Error deleting challenges: $e - continuing...');
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
          print('Deleted ${foodHistorySnapshot.docs.length} food items');
        } catch (e) {
          print('Error deleting food history: $e - continuing...');
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
          print('Deleted ${dailyTotalsSnapshot.docs.length} daily totals');
        } catch (e) {
          print('Error deleting daily totals: $e - continuing...');
        }

        // Delete main user document
        try {
          await _firestore.collection('users').doc(user.uid).delete();
          print('Deleted user document');
        } catch (e) {
          print('Error deleting user document: $e - continuing...');
        }
      } catch (e) {
        print(
          'Firestore deletion error: $e - continuing to delete auth account...',
        );
      }

      // Delete Firebase auth account
      print('Deleting Firebase auth account...');
      try {
        await user.delete();
        print('Auth account deleted successfully');
      } catch (e) {
        print('Auth deletion error: $e');
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
        print('Error signing out of Google: $e');
      }

      print('Account deletion completed successfully');
    } catch (e) {
      print('Error deleting account: $e');
      rethrow;
    }
  }
}
