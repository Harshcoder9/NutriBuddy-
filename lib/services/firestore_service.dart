import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

// Health Profile Model
class HealthProfile {
  final String name;
  final int age;
  final String gender; // Male, Female, Other
  final double height; // in cm
  final double weight; // in kg
  final String bloodGroup; // A+, A-, B+, B-, AB+, AB-, O+, O-
  final List<String>? allergies; // Optional, for future use

  HealthProfile({
    required this.name,
    required this.age,
    required this.gender,
    required this.height,
    required this.weight,
    required this.bloodGroup,
    this.allergies,
  });

  // Convert to Firestore map
  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'age': age,
      'gender': gender,
      'height': height,
      'weight': weight,
      'bloodGroup': bloodGroup,
      'allergies': allergies ?? [],
      'updatedAt': FieldValue.serverTimestamp(),
    };
  }

  // Create from Firestore map
  factory HealthProfile.fromMap(Map<String, dynamic> map) {
    return HealthProfile(
      name: map['name'] ?? '',
      age: map['age'] ?? 0,
      gender: map['gender'] ?? 'Other',
      height: (map['height'] ?? 0).toDouble(),
      weight: (map['weight'] ?? 0).toDouble(),
      bloodGroup: map['bloodGroup'] ?? 'O+',
      allergies: map['allergies'] != null
          ? List<String>.from(map['allergies'])
          : null,
    );
  }
}

class FirestoreService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  String? get _userId => _auth.currentUser?.uid;

  // Save user challenges
  Future<void> saveUserChallenges(List<String> challengeIds) async {
    if (_userId == null) return;

    try {
      await _firestore.collection('users').doc(_userId).update({
        'selectedChallenges': challengeIds,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      print('Error saving challenges: $e');
      rethrow;
    }
  }

  // Get user challenges
  Future<List<String>> getUserChallenges() async {
    if (_userId == null) return [];

    try {
      final doc = await _firestore.collection('users').doc(_userId).get();
      if (doc.exists && doc.data()?['selectedChallenges'] != null) {
        return List<String>.from(doc.data()!['selectedChallenges']);
      }
      return [];
    } catch (e) {
      print('Error getting challenges: $e');
      return [];
    }
  }

  // Save daily goals
  Future<void> saveDailyGoals(Map<String, double> goals) async {
    if (_userId == null) return;

    try {
      await _firestore.collection('users').doc(_userId).update({
        'dailyGoals': goals,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      print('Error saving daily goals: $e');
      rethrow;
    }
  }

  // Get daily goals
  Future<Map<String, double>?> getDailyGoals() async {
    if (_userId == null) return null;

    try {
      final doc = await _firestore.collection('users').doc(_userId).get();
      if (doc.exists && doc.data()?['dailyGoals'] != null) {
        return Map<String, double>.from(doc.data()!['dailyGoals']);
      }
      return null;
    } catch (e) {
      print('Error getting daily goals: $e');
      return null;
    }
  }

  // Save daily totals
  Future<void> saveDailyTotals(Map<String, double> totals) async {
    if (_userId == null) return;

    try {
      final today = DateTime.now();
      final dateKey =
          '${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';

      await _firestore
          .collection('users')
          .doc(_userId)
          .collection('daily_nutrition')
          .doc(dateKey)
          .set({
            'totals': totals,
            'date': dateKey,
            'timestamp': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));
    } catch (e) {
      print('Error saving daily totals: $e');
      rethrow;
    }
  }

  // Get daily totals
  Future<Map<String, double>?> getDailyTotals([DateTime? date]) async {
    if (_userId == null) return null;

    try {
      final targetDate = date ?? DateTime.now();
      final dateKey =
          '${targetDate.year}-${targetDate.month.toString().padLeft(2, '0')}-${targetDate.day.toString().padLeft(2, '0')}';

      final doc = await _firestore
          .collection('users')
          .doc(_userId)
          .collection('daily_nutrition')
          .doc(dateKey)
          .get();

      if (doc.exists && doc.data()?['totals'] != null) {
        return Map<String, double>.from(doc.data()!['totals']);
      }
      return null;
    } catch (e) {
      print('Error getting daily totals: $e');
      return null;
    }
  }

  // Save food analysis
  Future<void> saveFoodAnalysis(Map<String, dynamic> analysis) async {
    if (_userId == null) return;

    try {
      await _firestore
          .collection('users')
          .doc(_userId)
          .collection('food_history')
          .add({...analysis, 'timestamp': FieldValue.serverTimestamp()});
    } catch (e) {
      print('Error saving food analysis: $e');
      rethrow;
    }
  }

  // Get food history
  Stream<QuerySnapshot> getFoodHistory({int limit = 50}) {
    if (_userId == null) {
      return Stream.empty();
    }

    return _firestore
        .collection('users')
        .doc(_userId)
        .collection('food_history')
        .orderBy('timestamp', descending: true)
        .limit(limit)
        .snapshots();
  }

  // Initialize user profile with default data
  Future<void> initializeUserProfile({
    required List<String> challenges,
    required Map<String, double> dailyGoals,
    required Map<String, double> currentTotals,
  }) async {
    if (_userId == null) return;

    try {
      await _firestore.collection('users').doc(_userId).set({
        'selectedChallenges': challenges,
        'dailyGoals': dailyGoals,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      // Save current day's totals
      if (currentTotals.isNotEmpty) {
        await saveDailyTotals(currentTotals);
      }
    } catch (e) {
      print('Error initializing user profile: $e');
      rethrow;
    }
  }

  // Check if user has cloud data
  Future<bool> hasCloudData() async {
    if (_userId == null) return false;

    try {
      final doc = await _firestore.collection('users').doc(_userId).get();
      return doc.exists && doc.data()?['selectedChallenges'] != null;
    } catch (e) {
      return false;
    }
  }

  // Save health profile
  Future<void> saveHealthProfile(HealthProfile profile) async {
    if (_userId == null) return;

    try {
      await _firestore.collection('users').doc(_userId).set({
        'healthProfile': profile.toMap(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (e) {
      print('Error saving health profile: $e');
      rethrow;
    }
  }

  // Get health profile
  Future<HealthProfile?> getHealthProfile() async {
    if (_userId == null) return null;

    try {
      final doc = await _firestore.collection('users').doc(_userId).get();
      if (doc.exists && doc.data()?['healthProfile'] != null) {
        return HealthProfile.fromMap(doc.data()!['healthProfile']);
      }
      return null;
    } catch (e) {
      print('Error getting health profile: $e');
      return null;
    }
  }

  // Check if user has completed health profile
  Future<bool> hasCompletedHealthProfile() async {
    if (_userId == null) return false;

    try {
      final doc = await _firestore.collection('users').doc(_userId).get();
      return doc.exists && doc.data()?['healthProfile'] != null;
    } catch (e) {
      print('Error checking health profile: $e');
      return false;
    }
  }

  // Save mood log after a meal
  Future<void> saveMoodLog(String foodName, String mood) async {
    if (_userId == null) return;

    try {
      final today = DateTime.now();
      final dateKey =
          '${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';

      await _firestore
          .collection('users')
          .doc(_userId)
          .collection('mood_logs')
          .add({
            'foodName': foodName,
            'mood': mood,
            'date': dateKey,
            'hour': today.hour,
            'timestamp': FieldValue.serverTimestamp(),
          });
    } catch (e) {
      print('Error saving mood log: $e');
    }
  }

  // Get mood logs for the last N days
  Future<List<Map<String, dynamic>>> getRecentMoodLogs(int days) async {
    if (_userId == null) return [];

    try {
      final cutoff = DateTime.now().subtract(Duration(days: days));
      final snapshot = await _firestore
          .collection('users')
          .doc(_userId)
          .collection('mood_logs')
          .where('timestamp', isGreaterThan: Timestamp.fromDate(cutoff))
          .orderBy('timestamp', descending: true)
          .get();

      return snapshot.docs.map((d) => d.data()).toList();
    } catch (e) {
      print('Error getting mood logs: $e');
      return [];
    }
  }
}
