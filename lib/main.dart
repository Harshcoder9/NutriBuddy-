import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'firebase_options.dart';
import 'challenges_screen.dart';
import 'services/firestore_service.dart';
import 'services/nutrition_calculator.dart';
import 'screens/sign_in_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/health_profile_screen.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'services/amd_inference_service.dart';
import 'screens/video_analysis_screen.dart';
import 'screens/smart_cart_screen.dart';
import 'screens/supplement_optimizer_screen.dart';
import 'screens/family_hub_screen.dart';

// ─────────────────────────────────────────────
// 🔑  GEMINI API KEY - never hardcode here!
// Pass it at run/build time via --dart-define:
//   flutter run --dart-define=GEMINI_API_KEY=your_key_here
//   flutter build apk --dart-define=GEMINI_API_KEY=your_key_here
// Get a key free at: https://aistudio.google.com/app/apikey
// If no key is provided, the app runs in demo mode (simulated responses).
const _kGeminiApiKey = String.fromEnvironment('GEMINI_API_KEY');
const _kDemoMode = _kGeminiApiKey == '';
// ─────────────────────────────────────────────

// Challenge model class
class Challenge {
  final String id;
  final String name;
  final String icon;
  final Color color;
  final String description;

  Challenge({
    required this.id,
    required this.name,
    required this.icon,
    required this.color,
    required this.description,
  });
}

// Available challenges list
final List<Challenge> availableChallenges = [
  Challenge(
    id: 'weight_loss',
    name: 'Weight Loss',
    icon: '⚖️',
    color: Colors.orange,
    description: 'Reduce calorie intake and maintain healthy weight',
  ),
  Challenge(
    id: 'muscle_gain',
    name: 'Muscle Gain',
    icon: '💪',
    color: Colors.red,
    description: 'Increase protein intake for muscle building',
  ),
  Challenge(
    id: 'balanced_diet',
    name: 'Balanced Diet',
    icon: '🥗',
    color: Color(0xFF1565C0),
    description: 'Maintain balanced macronutrient ratios',
  ),
  Challenge(
    id: 'low_sugar',
    name: 'Low Sugar',
    icon: '🍬',
    color: Colors.pink,
    description: 'Reduce sugar consumption',
  ),
  Challenge(
    id: 'heart_health',
    name: 'Heart Health',
    icon: '❤️',
    color: Colors.red,
    description: 'Focus on low sodium and healthy fats',
  ),
];

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Firebase
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    debugPrint('Firebase initialized successfully');
  } catch (e) {
    debugPrint('Firebase initialization error: $e');
    // Continue without Firebase for development
  }

  runApp(const NutritionAIApp());
}

class NutritionAIApp extends StatelessWidget {
  const NutritionAIApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'NutriBuddy',
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF1565C0),
          brightness: Brightness.light,
        ),
        cardTheme: CardThemeData(
          elevation: 2,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color.fromARGB(160, 21, 101, 192),
          brightness: Brightness.dark,
        ),
        cardTheme: CardThemeData(
          elevation: 2,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      ),
      home: const AuthGate(),
    );
  }
}

// Authentication gate to handle sign-in flow
class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        debugPrint(
          'AuthGate - Connection: ${snapshot.connectionState}, HasData: ${snapshot.hasData}',
        );

        // Show loading while checking auth state
        if (snapshot.connectionState == ConnectionState.waiting) {
          debugPrint('AuthGate - Waiting for auth state...');
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        // Show sign-in screen if not authenticated
        if (!snapshot.hasData) {
          debugPrint('AuthGate - No user data, showing SignInScreen');
          return const SignInScreen();
        }

        debugPrint(
          'AuthGate - User authenticated: ${snapshot.data?.email ?? snapshot.data?.uid}',
        );

        // Check if user has completed health profile
        return FutureBuilder<bool>(
          future: FirestoreService().hasCompletedHealthProfile(),
          builder: (context, profileSnapshot) {
            debugPrint(
              'AuthGate - Profile check - Connection: ${profileSnapshot.connectionState}, Data: ${profileSnapshot.data}',
            );

            if (profileSnapshot.connectionState == ConnectionState.waiting) {
              debugPrint('AuthGate - Checking health profile...');
              return const Scaffold(
                body: Center(child: CircularProgressIndicator()),
              );
            }

            // Show health profile screen if not completed
            if (profileSnapshot.data == false) {
              debugPrint(
                'AuthGate - No health profile, showing HealthProfileScreen',
              );
              return const HealthProfileScreen(showBackButton: true);
            }

            debugPrint('AuthGate - Health profile complete, showing HomePage');
            // Show home page if profile is completed
            return const HomePage();
          },
        );
      },
    );
  }
}

class ChatMessage {
  final String text;
  final bool isUser;
  final Uint8List? imageBytes;
  final Map<String, dynamic>? analysisData;
  final DateTime timestamp;
  // 'mood_prompt' | 'credit_status' | 'recipe_mode' | null
  final String? messageType;
  final String? foodNameForMood;

  ChatMessage({
    required this.text,
    required this.isUser,
    this.imageBytes,
    this.analysisData,
    this.messageType,
    this.foodNameForMood,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();
}

// Challenge history statistics model
class ChallengeStats {
  final int streakDays;
  final int totalDaysTracked;
  final int avgCalories;
  final int avgProtein;
  final int avgCarbs;
  final int goalHitRate; // 0–100 percentage

  ChallengeStats({
    required this.streakDays,
    required this.totalDaysTracked,
    required this.avgCalories,
    required this.avgProtein,
    required this.avgCarbs,
    required this.goalHitRate,
  });
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final ImagePicker _picker = ImagePicker();
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FirestoreService _firestoreService = FirestoreService();
  final List<ChatMessage> _messages = [];
  XFile? _selectedImage;
  // Separate states for image vs text processing
  bool _isAnalyzingImage = false;
  bool _isProcessingText = false;
  String? _processingMessage; // Display message for user
  Map<String, dynamic>? _analysisResult;
  List<String> _selectedChallenges = [];
  // Conversation history for AI context (last 5 exchanges = 10 messages)
  final List<Map<String, String>> _conversationHistory = [];
  // Whether we are awaiting a recipe paste for Recipe Healthify
  bool _awaitingRecipe = false;
  // Last analyzed food nutrition — used for consumption detection
  Map<String, dynamic>? _lastAnalyzedNutrition;
  String? _lastAnalyzedProductName;
  // Challenge history stats
  ChallengeStats? _challengeStats;
  Map<String, String> _challengeStartDates = {};
  // AMD GPU backend availability flag
  bool _amdBackendAvailable = false;
  // Real-time cart item count (streamed from Firestore)
  int _cartItemCount = 0;
  List<Map<String, dynamic>> _cartCache = [];
  StreamSubscription<int>? _cartCountSub;
  StreamSubscription<List<Map<String, dynamic>>>? _cartSub;
  // Whether the progress panel is expanded on narrow screens
  bool _progressPanelExpanded = false;
  // Current bottom-nav / rail tab index (0=Chat 1=Family 2=Supplements 3=Goals)
  int _selectedTab = 0;

  @override
  void initState() {
    super.initState();
    _loadDataFromCloud();
    _loadWelcomeMessage();
    _checkAmdBackend();
    _cartCountSub = _firestoreService.watchCartCount().listen((count) {
      if (mounted) setState(() => _cartItemCount = count);
    });
    _cartSub = _firestoreService.watchCart().listen((items) {
      if (mounted) setState(() => _cartCache = items);
    });
  }

  Future<void> _checkAmdBackend() async {
    final available = await AmdInferenceService.isAvailable();
    if (mounted) {
      setState(() => _amdBackendAvailable = available);
      if (available)
        debugPrint('[AMD] ⚡ ROCm/Ollama backend detected and ready!');
    }
  }

  Future<void> _loadWelcomeMessage() async {
    final healthProfile = await _firestoreService.getHealthProfile();
    final userName = healthProfile?.name ?? 'there';
    final hour = DateTime.now().hour;

    // Get user's recent activity data
    final recentHistory = await _firestoreService.getChallengeHistory(7);
    final moodLogs = await _firestoreService.getRecentMoodLogs(7);
    final isReturningUser = recentHistory.isNotEmpty || moodLogs.isNotEmpty;

    String timeGreeting;
    String personalizedMessage;

    if (hour >= 5 && hour < 12) {
      timeGreeting = 'Good morning';
    } else if (hour >= 12 && hour < 17) {
      timeGreeting = 'Good afternoon';
    } else if (hour >= 17 && hour < 21) {
      timeGreeting = 'Good evening';
    } else {
      timeGreeting = 'Hey';
    }

    // Build personalized message for returning users
    if (isReturningUser) {
      String statsMessage = '';

      // Calculate weekly stats
      if (recentHistory.isNotEmpty) {
        double totalCalories = 0;
        double totalProtein = 0;
        int daysTracked = 0;

        for (var day in recentHistory) {
          if (day['totals'] != null) {
            totalCalories += (day['totals']['calories'] ?? 0).toDouble();
            totalProtein += (day['totals']['protein'] ?? 0).toDouble();
            daysTracked++;
          }
        }

        // Calculate estimated calories burned (rough estimate based on BMR)
        double estimatedDailyBurn = 2000; // Default
        if (healthProfile != null) {
          // Basic BMR calculation (Mifflin-St Jeor)
          if (healthProfile.gender == 'Male') {
            estimatedDailyBurn =
                10 * healthProfile.weight +
                6.25 * healthProfile.height -
                5 * healthProfile.age +
                5;
          } else {
            estimatedDailyBurn =
                10 * healthProfile.weight +
                6.25 * healthProfile.height -
                5 * healthProfile.age -
                161;
          }
        }

        double weeklyCalorieBurn = estimatedDailyBurn * 7;
        double calorieDeficit = weeklyCalorieBurn - totalCalories;
        double estimatedFatLoss = (calorieDeficit / 7700)
            .abs(); // 1kg fat ≈ 7700 kcal

        if (daysTracked > 0) {
          String progressEmoji = calorieDeficit > 0 ? '📉' : '📊';

          statsMessage = '\n\n$progressEmoji *Your Weekly Progress:*\n';
          statsMessage +=
              '• Tracked $daysTracked day${daysTracked > 1 ? 's' : ''} this week\n';

          if (calorieDeficit > 0) {
            statsMessage +=
                '• Estimated fat loss: ${estimatedFatLoss.toStringAsFixed(2)} kg\n';
            statsMessage += '• Great job maintaining a calorie deficit! 💪\n';
          } else if (calorieDeficit < -500) {
            statsMessage +=
                '• You\'re in a surplus - perfect for muscle building! 💪\n';
          } else {
            statsMessage += '• You\'re maintaining your weight well! ⚖️\n';
          }

          double avgProtein = totalProtein / daysTracked;
          statsMessage +=
              '• Daily avg protein: ${avgProtein.toStringAsFixed(0)}g';

          if (avgProtein >= 100) {
            statsMessage += ' - Excellent! 🥇';
          } else if (avgProtein >= 60) {
            statsMessage += ' - Good! 👍';
          }
        }
      }

      // Add mood insights
      if (moodLogs.isNotEmpty) {
        final recentMood = moodLogs.first['mood'];
        final recentFood = moodLogs.first['foodName'];
        statsMessage +=
            '\n\n😊 *Last meal feeling:* $recentMood after $recentFood';
      }

      personalizedMessage =
          '$timeGreeting, $userName! 👋 Welcome back to NutriBuddy! 🥗$statsMessage\n\n*Ready to continue your journey?*\n• 📸 Scan your next meal\n• 💬 Ask nutrition questions\n• 🍳 Healthify a recipe\n• 📊 Check detailed stats';
    } else {
      // New user message
      String timeTip;
      if (hour >= 5 && hour < 12) {
        timeTip =
            'Great time for a protein-rich breakfast to fuel your day! ☀️';
      } else if (hour >= 12 && hour < 17) {
        timeTip = 'Keep up your nutrition goals this afternoon! 🌤️';
      } else if (hour >= 17 && hour < 21) {
        timeTip =
            'Evening tip: keep dinner light and nutrient-dense for better sleep. 🌙';
      } else {
        timeTip =
            'Late-night tip: if hungry, choose something light and protein-rich. 🌙';
      }

      personalizedMessage =
          '$timeGreeting, $userName! 👋 I\'m NutriBuddy, your AI nutrition companion. 🥗\n\n$timeTip\n\n*You can:*\n• 📸 Scan food photos for instant analysis\n• 💬 Ask any nutrition or diet question\n• 🍳 Paste a recipe to healthify it\n• 💳 Check your cheat meal credits';
    }

    setState(() {
      _messages.add(ChatMessage(text: personalizedMessage, isUser: false));
    });
  }

  @override
  void dispose() {
    _cartCountSub?.cancel();
    _cartSub?.cancel();
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  // User's daily challenge goals
  final Map<String, double> _dailyGoals = {
    'maxCalories': 2000,
    'minProtein': 120,
    'maxCarbs': 200,
    'maxFat': 65,
    'maxSugar': 50,
  };

  final Map<String, double> _currentTotals = {
    'calories': 0,
    'protein': 0,
    'carbs': 0,
    'fat': 0,
    'sugar': 0,
  };

  Future<void> _pickImage(ImageSource source) async {
    try {
      final XFile? image = await _picker.pickImage(
        source: source,
        maxWidth: 1024,
        maxHeight: 1024,
        imageQuality: 85,
      );

      if (image != null) {
        final imageBytes = await image.readAsBytes();
        setState(() {
          _selectedImage = image;
          _analysisResult = null;
        });

        // Add user message with image
        _messages.add(
          ChatMessage(
            text: "Please analyze this food item",
            isUser: true,
            imageBytes: imageBytes,
          ),
        );

        // Auto-analyze the image
        await _analyzeImage();
        _scrollToBottom();
      }
    } catch (e) {
      _showError('Failed to pick image: $e');
    }
  }

  void _scrollToBottom() {
    Future.delayed(const Duration(milliseconds: 100), () {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  // Load all data from cloud and local storage
  Future<void> _loadDataFromCloud() async {
    try {
      // Try to load from Firestore first
      final cloudChallenges = await _firestoreService.getUserChallenges();
      final cloudGoals = await _firestoreService.getDailyGoals();
      final cloudTotals = await _firestoreService.getDailyTotals();

      if (cloudChallenges.isNotEmpty) {
        setState(() {
          _selectedChallenges = cloudChallenges;
        });
        // Save to local as backup
        final prefs = await SharedPreferences.getInstance();
        await prefs.setStringList('selected_challenges', cloudChallenges);
      } else {
        // Fallback to local storage
        await _loadSelectedChallenges();
      }

      if (cloudGoals != null) {
        _dailyGoals.addAll(cloudGoals);
      }

      if (cloudTotals != null) {
        _currentTotals.addAll(cloudTotals);
      }
      // Load challenge history stats
      await _loadChallengeStats();
    } catch (e) {
      debugPrint('Error loading data from cloud: $e');
      // Fallback to local storage
      await _loadSelectedChallenges();
    }
  }

  // Load selected challenges from persistent storage
  Future<void> _loadSelectedChallenges() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedChallenges = prefs.getStringList('selected_challenges') ?? [];
      setState(() {
        _selectedChallenges = savedChallenges;
      });
    } catch (e) {
      debugPrint('Error loading challenges: $e');
    }
  }

  // Save selected challenges to persistent storage and cloud
  Future<void> _saveSelectedChallenges() async {
    try {
      // Save to local storage
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList('selected_challenges', _selectedChallenges);

      // Save to Firestore
      await _firestoreService.saveUserChallenges(_selectedChallenges);

      // Record start dates for any newly added challenges (won't overwrite existing)
      for (final id in _selectedChallenges) {
        if (!_challengeStartDates.containsKey(id)) {
          await _firestoreService.saveChallengeStartDate(id);
        }
      }
      // Refresh local start dates cache
      _challengeStartDates = await _firestoreService.getChallengeStartDates();

      // Calculate and save personalized daily goals based on health profile
      final healthProfile = await _firestoreService.getHealthProfile();
      if (healthProfile != null) {
        final calculatedCalories = NutritionCalculator.calculateDailyCalories(
          healthProfile,
          _selectedChallenges,
        );
        final macros = NutritionCalculator.getRecommendedMacros(
          calculatedCalories,
          challenges: _selectedChallenges,
        );

        setState(() {
          _dailyGoals.addAll(macros);
        });

        // Save calculated goals to Firestore
        await _firestoreService.saveDailyGoals(macros);

        // Show confirmation with calculated values
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Goals updated! Daily target: ${calculatedCalories.round()} calories',
              ),
              duration: const Duration(seconds: 3),
            ),
          );
        }
      }
    } catch (e) {
      debugPrint('Error saving challenges: $e');
    }
  }

  Future<void> _sendTextMessage() async {
    final text = _messageController.text.trim();
    if (text.isEmpty) return;
    if (_isProcessingText) return; // prevent duplicate text submissions

    setState(() {
      _messages.add(ChatMessage(text: text, isUser: true));
      _messageController.clear();
    });
    _scrollToBottom();

    final lower = text.toLowerCase();

    // ── Tier-1: Explicit food eaten (works even without a prior scan) ─────────
    // e.g. "i ate vegetables", "i just had an apple", "i consumed rice"
    // Guard: skip if message is long (>80 chars) — likely a question, not a log
    const explicitEatPhrases = [
      'i just had',
      'i just ate',
      'i just consumed',
      'i ate',
      'i had',
      'i consumed',
      "i'm eating",
      'eating some',
      'had some',
      'ate some',
    ];
    if (lower.length <= 80 &&
        explicitEatPhrases.any((p) => lower.contains(p))) {
      await _logNamedFood(text);
      return;
    }

    // ── Tier-2: Generic confirmation — only meaningful after a food scan ───────
    // e.g. "yes", "log it", "ate it"
    // Guard: message must be short (≤30 chars) so "had it, feels good" doesn't trigger this
    if (_lastAnalyzedNutrition != null && lower.length <= 30) {
      const confirmPhrases = [
        'yes',
        'yep',
        'yeah',
        'yup',
        'sure',
        'ate it',
        'had it',
        'finished it',
        'i finished',
        'just finished',
        'ate that',
        'had that',
        'log it',
        'log this',
        'add it',
        'add to my log',
        'count it',
        'eating it',
        'eating now',
      ];
      if (confirmPhrases.any((p) => lower.contains(p))) {
        await _logConsumedMeal();
        return;
      }
    }

    // If awaiting a recipe paste, process it
    if (_awaitingRecipe) {
      await _processRecipeHealthify(text);
      return;
    }

    // Route to specific feature handlers based on intent
    // Smart Cart routing
    if (lower.contains('smart cart') ||
        lower.contains('grocery') ||
        lower.contains('shopping list') ||
        lower.contains('receipt') ||
        lower.contains('supermarket')) {
      await _launchSmartCart();
      return;
    }
    // Supplement routing
    if (lower.contains('supplement') ||
        lower.contains('vitamins') ||
        lower.contains('creatine') ||
        lower.contains('my stack') ||
        lower.contains('omega')) {
      await _launchSupplementOptimizer();
      return;
    }
    // Family Hub routing
    if (lower.contains('family') ||
        lower.contains('kid') ||
        lower.contains('children') ||
        lower.contains('family meal') ||
        lower.contains('family hub')) {
      await _launchFamilyHub();
      return;
    }
    if (lower.contains('cheat') ||
        lower.contains('credit') ||
        lower.contains('reward meal')) {
      await _checkCheatCredit();
    } else if (lower.contains('healthify') ||
        lower.contains('healthy recipe') ||
        lower.contains('make it healthier') ||
        lower.contains('substitute ingredients') ||
        lower.contains('recipe')) {
      _startRecipeMode();
    } else {
      await _processTextQuery(text);
    }
  }

  Future<void> _analyzeImage() async {
    if (_selectedImage == null) return;

    setState(() {
      _isAnalyzingImage = true;
      _processingMessage = 'Analyzing your food...';
    });

    try {
      const apiKey = _kGeminiApiKey;

      if (_kDemoMode) {
        // Demo mode - simulate AI response
        await Future.delayed(const Duration(seconds: 2));
        _simulateAIResponse();
        return;
      }

      final model = GenerativeModel(model: 'gemini-2.5-flash', apiKey: apiKey);

      // Fetch user's health profile for personalized recommendations
      final healthProfile = await _firestoreService.getHealthProfile();
      String healthProfileInfo = '';
      if (healthProfile != null) {
        final bmi = NutritionCalculator.calculateBMI(healthProfile);
        final calculatedCalories = NutritionCalculator.calculateDailyCalories(
          healthProfile,
          _selectedChallenges,
        );
        healthProfileInfo =
            '''

User Health Profile:
- Age: ${healthProfile.age} years
- Gender: ${healthProfile.gender}
- Height: ${healthProfile.height.toStringAsFixed(0)} cm
- Weight: ${healthProfile.weight.toStringAsFixed(1)} kg
- BMI: ${bmi.toStringAsFixed(1)} (${NutritionCalculator.getBMICategory(bmi)})
- Calculated Daily Needs: ${calculatedCalories.round()} calories

IMPORTANT: Consider the user's age, gender, and BMI when providing recommendations. Ensure advice is age-appropriate and supports their health status.
''';
      }

      final imageBytes = await _selectedImage!.readAsBytes();
      final prompt =
          '''
CRITICAL - FOOD DETECTION STEP:
First, determine if this image contains ACTUAL FOOD, PREPARED MEALS, or FOOD PACKAGING with visible nutrition labels.

REJECT and return error JSON if the image shows:
- Non-food items: electronics, screens, furniture, vehicles, tools, documents
- People, animals, pets (even if near food)
- Empty plates, bowls, or containers
- Landscapes, buildings, nature scenes
- Text, code, or screenshots without food
- Drinks only (unless nutritional beverage like protein shake)
- Raw ingredients in isolation (unless specifically a meal prep context)

If NOT food-related, return this JSON immediately:
{
  "error": "not_food",
  "message": "I can only analyze food and meals! 🍽️ Please take a photo of:\n• Prepared meals or dishes\n• Food packaging with nutrition labels\n• Snacks or beverages\n\nTip: Make sure the food is clearly visible and well-lit for best results."
}

ONLY if the image clearly shows ACTUAL FOOD, MEALS, OR FOOD PACKAGING, proceed to analyze nutritional content and provide recommendations in JSON format.

Include:
1. Product name (be specific - e.g., "Chicken Biryani" not just "rice dish")
2. Nutritional values per serving (calories, protein, carbs, fat, sugar)
3. Serving size
4. Key ingredients (top 5)
5. Health considerations (allergens, additives, etc.)

Current user daily intake:
- Calories: ${_currentTotals['calories']}/${_dailyGoals['maxCalories']}
- Protein: ${_currentTotals['protein']}g/${_dailyGoals['minProtein']}g
- Carbs: ${_currentTotals['carbs']}g/${_dailyGoals['maxCarbs']}g
- Fat: ${_currentTotals['fat']}g/${_dailyGoals['maxFat']}g
- Sugar: ${_currentTotals['sugar']}g/${_dailyGoals['maxSugar']}g
${_selectedChallenges.isNotEmpty ? '\nUser\'s health goals: ${_selectedChallenges.map((id) => availableChallenges.firstWhere((c) => c.id == id).name).join(', ')}\n\nIMPORTANT: Consider the user\'s specific health goals when making recommendations. Tailor your advice to support their ${_selectedChallenges.map((id) => availableChallenges.firstWhere((c) => c.id == id).name).join(', ')} goals.' : ''}$healthProfileInfo

Based on their remaining budget${_selectedChallenges.isNotEmpty ? ', health goals,' : ''}${healthProfile != null ? ' and health profile' : ''}, provide:
- recommendation (highly_recommended, recommended, moderate, not_recommended)
- reason (why it fits or doesn't fit their goals)
- alternatives (if not recommended)
- tips (how to consume this product wisely)

Return ONLY valid JSON with this structure:
{
  "productName": "string",
  "servingSize": "string",
  "nutrition": {
    "calories": number,
    "protein": number,
    "carbs": number,
    "fat": number,
    "sugar": number
  },
  "ingredients": ["string"],
  "healthConsiderations": ["string"],
  "recommendation": "highly_recommended|recommended|moderate|not_recommended",
  "reason": "string",
  "alternatives": ["string"],
  "tips": ["string"],
  "complianceScore": number (0-100)
}
''';

      final content = [
        Content.multi([TextPart(prompt), DataPart('image/jpeg', imageBytes)]),
      ];

      final response = await model.generateContent(content);
      final text = response.text ?? '';

      // Extract JSON from response
      final jsonMatch = RegExp(r'\{[\s\S]*\}').firstMatch(text);
      if (jsonMatch != null) {
        final jsonStr = jsonMatch.group(0)!;
        final result = jsonDecode(jsonStr) as Map<String, dynamic>;

        // Check if it's an error (not food)
        if (result['error'] == 'not_food') {
          setState(() {
            _isAnalyzingImage = false;
            _processingMessage = null;
            _messages.add(
              ChatMessage(
                text:
                    result['message'] as String? ??
                    'This doesn\'t appear to be food. Please take a photo of actual food or food packaging.',
                isUser: false,
              ),
            );
          });
          _scrollToBottom();
          return;
        }

        final productName = result['productName'] as String? ?? 'that food';

        setState(() {
          _analysisResult = result;
          _lastAnalyzedNutrition = result['nutrition'] as Map<String, dynamic>?;
          _lastAnalyzedProductName = result['productName'] as String?;
          _isAnalyzingImage = false;
          _processingMessage = null;

          // Add AI response to chat
          _messages.add(
            ChatMessage(
              text: "Here's the nutritional analysis:",
              isUser: false,
              analysisData: result,
            ),
          );

          // Add mood prompt after analysis
          _messages.add(
            ChatMessage(
              text: 'How do you feel after eating $productName?',
              isUser: false,
              messageType: 'mood_prompt',
              foodNameForMood: productName,
            ),
          );
        });

        // Save analysis to Firestore
        _saveAnalysisToCloud(result);

        _scrollToBottom();
      } else {
        throw Exception('Invalid response format');
      }
    } catch (e, stackTrace) {
      debugPrint('=== IMAGE ANALYSIS ERROR ===');
      debugPrint('Error: $e');
      debugPrint('Stack trace: $stackTrace');
      debugPrint('API Key starts with: ${_kGeminiApiKey.substring(0, 10)}...');

      setState(() {
        _isAnalyzingImage = false;
        _processingMessage = null;
      });

      String errorMessage = 'Analysis failed. ';
      if (e.toString().contains('PERMISSION_DENIED') ||
          e.toString().contains('API_KEY_INVALID')) {
        errorMessage +=
            'Invalid API key or permissions denied. Please check your Gemini API key and ensure "Generative Language API" is enabled in Google Cloud Console.';
      } else if (e.toString().contains('RESOURCE_EXHAUSTED') ||
          e.toString().contains('quota')) {
        errorMessage +=
            'API quota exceeded. Please check your Gemini API usage limits.';
      } else if (e.toString().contains('Failed host lookup') ||
          e.toString().contains('SocketException') ||
          e.toString().contains('Connection')) {
        errorMessage +=
            'Network connection failed. Please check your internet connection and try again.';
      } else {
        errorMessage += 'Error: ${e.toString().split('\n').first}';
      }

      _showError(errorMessage);
    }
  }

  void _simulateAIResponse() {
    // Goal-aware demo response that adapts to the user's active challenges
    // and current daily totals.
    final hasGoal = _selectedChallenges.isNotEmpty;
    final primaryGoal = hasGoal ? _selectedChallenges.first : '';

    // Pick a demo food that matches the detected/primary goal
    Map<String, dynamic> demoData;

    if (primaryGoal == 'muscle_gain') {
      demoData = {
        'productName': 'Grilled Chicken Breast',
        'servingSize': '150g serving',
        'nutrition': {
          'calories': 248,
          'protein': 46,
          'carbs': 0,
          'fat': 5,
          'sugar': 0,
        },
        'ingredients': [
          'Chicken breast',
          'Olive oil',
          'Garlic',
          'Mixed herbs',
          'Black pepper',
        ],
        'healthConsiderations': [
          'High-quality complete protein',
          'Low in saturated fat',
          'Excellent for muscle synthesis',
          'Zero sugar',
        ],
        'recommendation': 'highly_recommended',
        'reason':
            'Outstanding choice for your Muscle Gain goal! 46g of lean protein in one serving covers ${((46 / (_dailyGoals['minProtein'] ?? 120)) * 100).toInt()}% of your daily protein target. You have ${(_dailyGoals['minProtein']! - _currentTotals['protein']!).toInt()}g protein remaining today — this gets you much closer!',
        'alternatives': [
          'Turkey breast (similar protein, slightly leaner)',
          'Cottage cheese (slower-digesting casein protein)',
        ],
        'tips': [
          'Eat within 30 mins post-workout for best muscle recovery',
          'Pair with complex carbs like sweet potato for an anabolic meal',
          'Season with lemon + herbs to boost iron absorption',
        ],
        'complianceScore': 97,
      };
    } else if (primaryGoal == 'weight_loss') {
      demoData = {
        'productName': 'Mixed Green Salad with Tuna',
        'servingSize': '1 bowl (300g)',
        'nutrition': {
          'calories': 180,
          'protein': 22,
          'carbs': 8,
          'fat': 6,
          'sugar': 3,
        },
        'ingredients': [
          'Tuna in spring water',
          'Mixed greens',
          'Cherry tomatoes',
          'Cucumber',
          'Olive oil dressing',
        ],
        'healthConsiderations': [
          'Very low calorie, high satiety',
          'Rich in omega-3 (tuna)',
          'High fibre from vegetables',
          'Low glycaemic index',
        ],
        'recommendation': 'highly_recommended',
        'reason':
            'Perfect for Weight Loss! Only 180 kcal — you have ${(_dailyGoals['maxCalories']! - _currentTotals['calories']!).toInt()} kcal remaining today. High protein (22g) keeps you full and preserves muscle while in a calorie deficit.',
        'alternatives': [
          'Chicken Caesar salad (swap dressing for Greek yogurt)',
          'Egg-white omelette with spinach',
        ],
        'tips': [
          'Eat slowly — takes 20 min for satiety signals to reach your brain',
          'Add chickpeas for extra fibre and protein',
          'Avoid croutons or creamy dressings to keep calories low',
        ],
        'complianceScore': 96,
      };
    } else if (primaryGoal == 'low_sugar') {
      demoData = {
        'productName': 'Greek Yogurt (Plain, Full-Fat)',
        'servingSize': '150g pot',
        'nutrition': {
          'calories': 148,
          'protein': 12,
          'carbs': 5,
          'fat': 8,
          'sugar': 5,
        },
        'ingredients': [
          'Pasteurised whole milk',
          'Live cultures (L. bulgaricus, S. thermophilus)',
        ],
        'healthConsiderations': [
          'Contains live probiotic cultures',
          'Minimal added sugar (only natural lactose)',
          'Avoid flavoured varieties — high in added sugar',
          'Contains calcium and B12',
        ],
        'recommendation': 'highly_recommended',
        'reason':
            'Excellent Low Sugar choice! Only 5g of natural sugar (no added sugar). You have ${(_dailyGoals['maxSugar']! - _currentTotals['sugar']!).toInt()}g sugar budget remaining — this uses just a fraction. The probiotics also help gut health.',
        'alternatives': [
          'Kefir (even more probiotics, similar sugar)',
          'Cottage cheese (lower fat, similar protein)',
        ],
        'tips': [
          'Add fresh berries instead of honey for flavour without added sugar',
          'Avoid fruit-flavoured yogurts — can have 15–20g added sugar',
          'Great as a dessert substitute to kill sweet cravings naturally',
        ],
        'complianceScore': 93,
      };
    } else if (primaryGoal == 'heart_health') {
      demoData = {
        'productName': 'Salmon Fillet (Baked)',
        'servingSize': '140g fillet',
        'nutrition': {
          'calories': 280,
          'protein': 39,
          'carbs': 0,
          'fat': 13,
          'sugar': 0,
        },
        'ingredients': ['Atlantic salmon', 'Olive oil', 'Dill', 'Lemon'],
        'healthConsiderations': [
          'High in omega-3 fatty acids (EPA & DHA)',
          'Reduces LDL cholesterol',
          'Excellent for cardiovascular health',
          'Rich in selenium and B vitamins',
        ],
        'recommendation': 'highly_recommended',
        'reason':
            'Outstanding for Heart Health! Omega-3 fatty acids in salmon directly reduce triglycerides and blood pressure. Zero sodium when baked plain — ideal for your cardiovascular goal.',
        'alternatives': [
          'Sardines in water (more omega-3 per gram)',
          'Mackerel fillet (similar heart benefits)',
        ],
        'tips': [
          'Bake or grill — avoid frying to preserve omega-3 integrity',
          'Pair with leafy greens and whole grains for a heart-healthy plate',
          'Aim for fatty fish 2–3 times per week',
        ],
        'complianceScore': 98,
      };
    } else {
      // Balanced diet or no goal set
      demoData = {
        'productName': 'Quinoa & Veggie Buddha Bowl',
        'servingSize': '1 bowl (400g)',
        'nutrition': {
          'calories': 420,
          'protein': 18,
          'carbs': 52,
          'fat': 14,
          'sugar': 8,
        },
        'ingredients': [
          'Cooked quinoa',
          'Roasted chickpeas',
          'Avocado',
          'Kale',
          'Tahini dressing',
        ],
        'healthConsiderations': [
          'Complete protein from quinoa + chickpeas combo',
          'High in dietary fibre (11g)',
          'Healthy unsaturated fats from avocado',
          'Rich in iron, magnesium, and folate',
        ],
        'recommendation': 'highly_recommended',
        'reason':
            'A beautifully balanced meal! Macros are well-distributed — fits comfortably within today\'s remaining budget. Calories: ${(_dailyGoals['maxCalories']! - _currentTotals['calories']!).toInt()} kcal left today.',
        'alternatives': [
          'Brown rice bowl (simpler, still balanced)',
          'Lentil soup with whole-grain bread',
        ],
        'tips': [
          'Meal prep this in batches — keeps well for 4 days',
          'Add a soft-boiled egg for extra protein and B12',
          'Drizzle lemon juice to enhance iron absorption from kale',
        ],
        'complianceScore': 91,
      };
    }

    setState(() {
      _analysisResult = demoData;
      _lastAnalyzedNutrition = demoData['nutrition'] as Map<String, dynamic>?;
      _lastAnalyzedProductName = demoData['productName'] as String?;
      _processingMessage = null;

      // Demo mode notice
      _messages.add(
        ChatMessage(
          text:
              '⚠️ DEMO MODE: This analysis is simulated, NOT based on your actual photo. '
              'The food name and nutrition shown are generic examples. '
              'To get real AI-powered analysis of what you uploaded, please add a valid Gemini API key in main.dart.',
          isUser: false,
        ),
      );

      _messages.add(
        ChatMessage(
          text: "Here's the nutritional analysis:",
          isUser: false,
          analysisData: _analysisResult,
        ),
      );

      final demoProductName =
          _analysisResult?['productName'] as String? ?? 'that food';
      _messages.add(
        ChatMessage(
          text: 'How do you feel after eating $demoProductName?',
          isUser: false,
          messageType: 'mood_prompt',
          foodNameForMood: demoProductName,
        ),
      );

      _saveAnalysisToCloud(_analysisResult);
    });
    _scrollToBottom();
  }

  // Save analysis result to Firestore
  Future<void> _saveAnalysisToCloud(Map<String, dynamic>? analysis) async {
    if (analysis == null) return;

    try {
      await _firestoreService.saveFoodAnalysis(analysis);
      // Daily totals are only persisted when the user confirms consumption via _logConsumedMeal()
    } catch (e) {
      debugPrint('Error saving analysis to cloud: $e');
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  // ──────────────────────────────────────────────────────────
  //  CORE AI BACKEND
  // ──────────────────────────────────────────────────────────

  /// Assembles the user's health profile + today's intake into a prompt string.
  /// Builds a compact summary of current cart items for the AI system prompt.
  String _buildCartContext() {
    if (_cartCache.isEmpty) return '';
    final lines = _cartCache
        .map((item) {
          final name = item['name'] ?? 'Unknown';
          final score = item['healthScore'] ?? '';
          final swap = item['healthierSwap'];
          final cal =
              (item['estimatedNutrition']?['calories'] as num?)?.toInt() ?? 0;
          final pro =
              (item['estimatedNutrition']?['protein'] as num?)?.toInt() ?? 0;
          String line =
              '  • $name (score: $score, ~${cal}kcal, ${pro}g protein';
          if (swap != null) line += ', healthier swap: $swap';
          line += ')';
          return line;
        })
        .join('\n');
    return '''
User's Smart Grocery Cart (${_cartCache.length} items):
$lines
When asked about meal planning, shopping, or nutrition advice, reference these specific items and suggest how they can be combined or improved.
''';
  }

  String _buildUserContext(HealthProfile? profile) {
    if (profile == null) return '';
    final bmi = NutritionCalculator.calculateBMI(profile);
    final bmiCat = NutritionCalculator.getBMICategory(bmi);
    final goals = _selectedChallenges.isNotEmpty
        ? _selectedChallenges
              .map(
                (id) => availableChallenges.firstWhere((c) => c.id == id).name,
              )
              .join(', ')
        : 'None set';
    return '''
User Profile:
- Name: ${profile.name}, Age: ${profile.age}, Gender: ${profile.gender}
- Height: ${profile.height.toStringAsFixed(0)} cm, Weight: ${profile.weight.toStringAsFixed(1)} kg
- BMI: ${bmi.toStringAsFixed(1)} ($bmiCat)
- Active Health Goals: $goals

Today's Intake vs Goals:
- Calories: ${_currentTotals['calories']?.toInt()}/${_dailyGoals['maxCalories']?.toInt()} kcal
- Protein:  ${_currentTotals['protein']?.toInt()}/${_dailyGoals['minProtein']?.toInt()} g
- Carbs:    ${_currentTotals['carbs']?.toInt()}/${_dailyGoals['maxCarbs']?.toInt()} g
- Fat:      ${_currentTotals['fat']?.toInt()}/${_dailyGoals['maxFat']?.toInt()} g
- Sugar:    ${_currentTotals['sugar']?.toInt()}/${_dailyGoals['maxSugar']?.toInt()} g
${_challengeStats != null ? '''
Challenge History (last ${_challengeStats!.totalDaysTracked} days tracked):
- Current streak: ${_challengeStats!.streakDays} days
- Goal hit rate: ${_challengeStats!.goalHitRate}%
- Avg daily calories: ${_challengeStats!.avgCalories} kcal
- Avg daily protein: ${_challengeStats!.avgProtein} g
- Avg daily carbs: ${_challengeStats!.avgCarbs} g''' : ''}
''';
  }

  /// Returns a time-of-day nutrition hint injected into every AI prompt.
  String _getCircadianContext() {
    final hour = DateTime.now().hour;
    if (hour >= 5 && hour < 10) {
      return 'Time context: Morning ($hour:00). Ideal for slow-release carbs and lean protein.';
    } else if (hour >= 10 && hour < 13) {
      return 'Time context: Late morning ($hour:00). Good window for a balanced snack if needed.';
    } else if (hour >= 13 && hour < 15) {
      return 'Time context: Lunch ($hour:00). Suggest balanced meals with protein + complex carbs + veg.';
    } else if (hour >= 15 && hour < 18) {
      return 'Time context: Afternoon ($hour:00). Pre-workout: fast carbs + protein. Otherwise light snack.';
    } else if (hour >= 18 && hour < 21) {
      return 'Time context: Evening ($hour:00). Suggest lighter, nutrient-dense meals; avoid heavy carbs.';
    } else {
      return 'Time context: Late night ($hour:00). Discourage heavy meals; suggest light, protein-rich options.';
    }
  }

  // ──────────────────────────────────────────────────────────
  //  CONSUMPTION DETECTION + CHALLENGE HISTORY
  // ──────────────────────────────────────────────────────────

  /// Logs the last analyzed meal into today's running totals and persists to Firestore.
  Future<void> _logConsumedMeal() async {
    if (_lastAnalyzedNutrition == null) return;

    final nutrition = _lastAnalyzedNutrition!;
    final foodName = _lastAnalyzedProductName ?? 'that meal';

    setState(() {
      _currentTotals['calories'] =
          (_currentTotals['calories'] ?? 0) +
          (nutrition['calories'] as num? ?? 0).toDouble();
      _currentTotals['protein'] =
          (_currentTotals['protein'] ?? 0) +
          (nutrition['protein'] as num? ?? 0).toDouble();
      _currentTotals['carbs'] =
          (_currentTotals['carbs'] ?? 0) +
          (nutrition['carbs'] as num? ?? 0).toDouble();
      _currentTotals['fat'] =
          (_currentTotals['fat'] ?? 0) +
          (nutrition['fat'] as num? ?? 0).toDouble();
      _currentTotals['sugar'] =
          (_currentTotals['sugar'] ?? 0) +
          (nutrition['sugar'] as num? ?? 0).toDouble();
    });

    // Persist updated totals and refresh history stats
    await _firestoreService.saveDailyTotals(_currentTotals);
    await _loadChallengeStats();

    final calAdded = (nutrition['calories'] as num? ?? 0).toInt();
    final calLeft =
        ((_dailyGoals['maxCalories'] ?? 2000) - _currentTotals['calories']!)
            .toInt();
    final proLeft =
        ((_dailyGoals['minProtein'] ?? 120) - _currentTotals['protein']!)
            .toInt();
    final streakMsg = (_challengeStats?.streakDays ?? 0) > 1
        ? '\n\n🔥 ${_challengeStats!.streakDays}-day streak! Keep it up!'
        : '';

    setState(() {
      _lastAnalyzedNutrition = null;
      _lastAnalyzedProductName = null;
      _messages.add(
        ChatMessage(
          text:
              '✅ Logged $foodName! +$calAdded kcal added.\n\n'
              '📊 Today so far:\n'
              '• Calories: ${calLeft > 0 ? '$calLeft kcal remaining' : '⚠️ Over budget by ${calLeft.abs()} kcal'}\n'
              '• Protein: ${proLeft > 0 ? '$proLeft g to goal' : '✅ Protein goal reached!'}\n'
              '• Carbs: ${((_dailyGoals['maxCarbs'] ?? 200) - _currentTotals['carbs']!).toInt()} g remaining'
              '$streakMsg',
          isUser: false,
        ),
      );
    });
    _scrollToBottom();
  }

  /// Parses an explicit "i ate X" message, estimates X's nutrition, and logs it.
  Future<void> _logNamedFood(String messageText) async {
    // Strip eating verb phrases to extract just the food name
    String foodText = messageText.toLowerCase();
    for (final phrase in [
      'i just had',
      'i just ate',
      'i just consumed',
      'i ate',
      'i had',
      'i consumed',
      "i'm eating",
      'eating some',
      'had some',
      'ate some',
    ]) {
      if (foodText.contains(phrase)) {
        foodText = foodText.replaceFirst(phrase, '').trim();
        break;
      }
    }
    // Strip trailing time words
    foodText = foodText
        .replaceAll(
          RegExp(
            r'\b(now|just now|today|just|right now|for lunch|for dinner|for breakfast)\b',
          ),
          '',
        )
        .replaceAll(RegExp(r'[^\w\s]'), '')
        .trim();
    final foodName = foodText.isEmpty ? 'food' : foodText;

    setState(() {
      _isProcessingText = true;
      _processingMessage = 'Estimating nutrition for $foodName...';
    });

    try {
      final nutrition = _kDemoMode
          ? _estimateDemoNutrition(foodName)
          : await _estimateNutritionWithAI(foodName);

      _lastAnalyzedNutrition = nutrition;
      _lastAnalyzedProductName = foodName;
      await _logConsumedMeal();
    } catch (e) {
      debugPrint('Error logging food: $e');
      setState(() {
        _messages.add(
          ChatMessage(
            text: 'Sorry, I had trouble logging that food. Please try again.',
            isUser: false,
          ),
        );
      });
    } finally {
      setState(() {
        _isProcessingText = false;
        _processingMessage = null;
      });
    }
  }

  /// Simple keyword-based nutrition estimator for demo mode.
  Map<String, dynamic> _estimateDemoNutrition(String food) {
    final f = food.toLowerCase();
    if (RegExp(
      r'vegetable|veggie|salad|broccoli|spinach|carrot|kale|cucumber|lettuce|pepper|tomato',
    ).hasMatch(f)) {
      return {
        'calories': 55.0,
        'protein': 3.0,
        'carbs': 9.0,
        'fat': 1.0,
        'sugar': 4.0,
      };
    }
    if (RegExp(
      r'fruit|apple|banana|orange|mango|berry|berries|grape|watermelon',
    ).hasMatch(f)) {
      return {
        'calories': 80.0,
        'protein': 1.0,
        'carbs': 20.0,
        'fat': 0.0,
        'sugar': 15.0,
      };
    }
    if (RegExp(
      r'chicken|turkey|fish|salmon|tuna|shrimp|prawn|meat|beef|pork|lamb|egg|eggs',
    ).hasMatch(f)) {
      return {
        'calories': 210.0,
        'protein': 30.0,
        'carbs': 1.0,
        'fat': 9.0,
        'sugar': 0.0,
      };
    }
    if (RegExp(
      r'rice|pasta|noodle|bread|roti|chapati|oat|oatmeal|quinoa|cereal',
    ).hasMatch(f)) {
      return {
        'calories': 220.0,
        'protein': 5.0,
        'carbs': 44.0,
        'fat': 2.0,
        'sugar': 1.0,
      };
    }
    if (RegExp(r'dal|lentil|bean|chickpea|tofu|paneer').hasMatch(f)) {
      return {
        'calories': 180.0,
        'protein': 12.0,
        'carbs': 22.0,
        'fat': 4.0,
        'sugar': 2.0,
      };
    }
    if (RegExp(r'milk|yogurt|curd|cheese|dairy').hasMatch(f)) {
      return {
        'calories': 120.0,
        'protein': 8.0,
        'carbs': 12.0,
        'fat': 5.0,
        'sugar': 10.0,
      };
    }
    if (RegExp(r'juice|smoothie|shake|drink').hasMatch(f)) {
      return {
        'calories': 130.0,
        'protein': 2.0,
        'carbs': 30.0,
        'fat': 0.0,
        'sugar': 25.0,
      };
    }
    // Default generic meal estimate
    return {
      'calories': 300.0,
      'protein': 12.0,
      'carbs': 35.0,
      'fat': 10.0,
      'sugar': 6.0,
    };
  }

  /// Uses Gemini to estimate nutrition for a named food (real mode).
  Future<Map<String, dynamic>> _estimateNutritionWithAI(String food) async {
    try {
      final model = GenerativeModel(
        model: 'gemini-2.5-flash',
        apiKey: _kGeminiApiKey,
      );
      final response = await model.generateContent([
        Content.text(
          'Estimate the nutrition for a typical single serving of "$food". '
          'Return ONLY valid JSON with keys: calories, protein, carbs, fat, sugar (all numbers in grams except calories). '
          'Example: {"calories":200,"protein":8,"carbs":30,"fat":5,"sugar":3}',
        ),
      ]);
      final text = response.text ?? '';
      final jsonMatch = RegExp(r'\{[\s\S]*?\}').firstMatch(text);
      if (jsonMatch != null) {
        final raw = jsonDecode(jsonMatch.group(0)!) as Map<String, dynamic>;
        return raw.map((k, v) => MapEntry(k, (v as num).toDouble()));
      }
    } catch (_) {}
    // Fallback
    return {
      'calories': 250.0,
      'protein': 10.0,
      'carbs': 30.0,
      'fat': 8.0,
      'sugar': 5.0,
    };
  }

  /// Loads challenge history from Firestore and computes ChallengeStats.
  Future<void> _loadChallengeStats() async {
    try {
      final startDates = await _firestoreService.getChallengeStartDates();
      final history = await _firestoreService.getChallengeHistory(90);

      if (history.isEmpty) {
        if (mounted) {
          setState(() {
            _challengeStartDates = startDates;
            _challengeStats = null;
          });
        }
        return;
      }

      // Build set of tracked date keys
      final trackedDates = history
          .map((d) {
            final key = d['dateKey'] as String?;
            return (key != null && key.isNotEmpty)
                ? key
                : (d['date'] as String? ?? '');
          })
          .where((k) => k.isNotEmpty)
          .toSet();

      // Compute streak (consecutive days from today backwards)
      int streak = 0;
      DateTime cursor = DateTime.now();
      while (true) {
        final key = _dateKey(cursor);
        if (trackedDates.contains(key)) {
          streak++;
          cursor = cursor.subtract(const Duration(days: 1));
        } else {
          break;
        }
      }

      // Rolling averages and goal-hit rate
      double totalCal = 0, totalPro = 0, totalCarbs = 0;
      int hitCount = 0;
      for (final day in history) {
        final totals = day['totals'] as Map<String, dynamic>? ?? {};
        totalCal += (totals['calories'] as num? ?? 0).toDouble();
        totalPro += (totals['protein'] as num? ?? 0).toDouble();
        totalCarbs += (totals['carbs'] as num? ?? 0).toDouble();
        // "Goal hit" = within calorie budget AND ≥80% of protein target
        final cal = (totals['calories'] as num? ?? 0).toDouble();
        final pro = (totals['protein'] as num? ?? 0).toDouble();
        if (cal <= (_dailyGoals['maxCalories'] ?? 2000) &&
            pro >= (_dailyGoals['minProtein'] ?? 120) * 0.8) {
          hitCount++;
        }
      }

      final n = history.length;
      if (mounted) {
        setState(() {
          _challengeStartDates = startDates;
          _challengeStats = ChallengeStats(
            streakDays: streak,
            totalDaysTracked: n,
            avgCalories: n > 0 ? (totalCal / n).round() : 0,
            avgProtein: n > 0 ? (totalPro / n).round() : 0,
            avgCarbs: n > 0 ? (totalCarbs / n).round() : 0,
            goalHitRate: n > 0 ? ((hitCount / n) * 100).round() : 0,
          );
        });
      }
    } catch (e) {
      debugPrint('Error loading challenge stats: $e');
    }
  }

  /// Returns a date key string (yyyy-MM-dd) for a given DateTime.
  String _dateKey(DateTime date) =>
      '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

  /// Main conversational AI handler for text questions.
  Future<void> _processTextQuery(String text) async {
    setState(() {
      _isProcessingText = true;
      _processingMessage = 'Thinking...';
    });

    try {
      const apiKey = _kGeminiApiKey;

      if (_kDemoMode) {
        // Demo mode
        await Future.delayed(const Duration(milliseconds: 1200));
        _simulateTextResponse(text);
        return;
      }

      final healthProfile = await _firestoreService.getHealthProfile();
      final userContext = _buildUserContext(healthProfile);
      final circadian = _getCircadianContext();
      final cartContext = _buildCartContext();

      // Build recent conversation snippet for context continuity
      String historyStr = '';
      if (_conversationHistory.isNotEmpty) {
        final recent = _conversationHistory.length > 6
            ? _conversationHistory.sublist(_conversationHistory.length - 6)
            : _conversationHistory;
        historyStr =
            '\nRecent conversation:\n${recent.map((m) => '${m['role']}: ${m['text']}').join('\n')}\n';
      }

      final systemPrompt =
          '''
You are NutriBuddy, a knowledgeable and friendly nutrition AI assistant. You ONLY answer questions about nutrition, food, diet, health, fitness, and wellness. If asked about anything unrelated (weather, coding, sports scores, entertainment, etc.), politely decline and say you specialise only in nutrition and health.

$userContext
$cartContext
$circadian
$historyStr

WHEN USER ASKS ABOUT SPECIFIC FOODS (e.g., "tell me about pav bhaji", "is pizza healthy?", "what about chicken salad?"):
1. **Nutritional Overview**: Provide typical nutrition per serving (calories, protein, carbs, fat, sugar, fiber, key vitamins/minerals)
2. **Ingredients Analysis**: Briefly explain main ingredients and their health impact
3. **Personalized Assessment**: Based on the user's goals and current intake, clearly state if this food is:
   - ✅ HIGHLY RECOMMENDED: Aligns perfectly with their goals
   - ✅ RECOMMENDED: Good choice with minor considerations
   - ⚠️ MODERATE: Can fit if prepared/portioned correctly
   - ❌ NOT RECOMMENDED: Conflicts with their health goals
4. **Practical Guidance**: 
   - Ideal serving size for this user
   - Best time to consume (based on circadian context)
   - Healthier preparation methods
   - What to pair it with for balanced nutrition
5. **Alternatives**: If not recommended, suggest 2-3 healthier alternatives that satisfy similar cravings

IMPORTANT: Always consider their remaining calorie/macro budget, active health goals, and BMI status. Be specific with numbers (e.g., "150g serving = 320 kcal"). Keep tone warm and encouraging, not judgmental.

Answer the following question with personalised, actionable advice. Be warm and concise. Reference the user's specific profile or goals where relevant. Keep paragraphs short.

User: $text
''';

      final model = GenerativeModel(model: 'gemini-2.5-flash', apiKey: apiKey);
      final response = await model.generateContent([
        Content.text(systemPrompt),
      ]);
      final responseText =
          response.text ?? 'Sorry, I could not generate a response.';

      // Maintain rolling conversation history
      _conversationHistory.addAll([
        {'role': 'User', 'text': text},
        {'role': 'NutriBuddy', 'text': responseText},
      ]);
      if (_conversationHistory.length > 10) {
        _conversationHistory.removeRange(0, 2);
      }

      setState(() {
        _isProcessingText = false;
        _processingMessage = null;
        _messages.add(ChatMessage(text: responseText, isUser: false));
      });
      _scrollToBottom();
    } catch (e) {
      debugPrint('=== TEXT QUERY ERROR ===');
      debugPrint('Error: $e');

      String errorMsg = 'Sorry, I had trouble responding right now. ';
      if (e.toString().contains('Failed host lookup') ||
          e.toString().contains('SocketException') ||
          e.toString().contains('Connection')) {
        errorMsg += 'Please check your internet connection and try again. 🌐';
      } else if (e.toString().contains('PERMISSION_DENIED') ||
          e.toString().contains('API_KEY_INVALID')) {
        errorMsg +=
            'API key issue detected. Please verify your Gemini API key. 🔑';
      } else {
        errorMsg += 'Please try again! 😅';
      }

      setState(() {
        _isProcessingText = false;
        _processingMessage = null;
        _messages.add(ChatMessage(text: errorMsg, isUser: false));
      });
      _scrollToBottom();
    }
  }

  /// Demo-mode simulated text responses for common queries.
  void _simulateTextResponse(String text) {
    final lower = text.toLowerCase();
    String response;

    if (lower.contains('oat') || lower.contains('oatmeal')) {
      response =
          'Oatmeal is excellent! 🌾 It\'s rich in beta-glucan fibre, lowers cholesterol, and keeps you full. For your goals, try 50g dry oats with a scoop of protein powder or Greek yogurt — roughly 280 kcal, 22g protein, 30g carbs. Perfect morning fuel!';
    } else if (lower.contains('protein')) {
      response =
          'You\'ve hit ${_currentTotals['protein']?.toInt() ?? 0}g protein today against your ${_dailyGoals['minProtein']?.toInt() ?? 120}g goal. 💪 Top-up ideas: Greek yogurt (10g/100g), chicken breast (31g/100g), eggs (6g each), or a protein shake (20–25g).';
    } else if (lower.contains('what should i eat') ||
        lower.contains('dinner') ||
        lower.contains('lunch') ||
        lower.contains('breakfast') ||
        lower.contains('meal')) {
      final hour = DateTime.now().hour;
      final meal = hour < 11 ? 'breakfast' : (hour < 15 ? 'lunch' : 'dinner');
      final remaining =
          (_dailyGoals['maxCalories'] ?? 2000) -
          (_currentTotals['calories'] ?? 0);
      response =
          'For $meal you have ~${remaining.toInt()} kcal remaining today. 🥗 I\'d suggest grilled chicken or tofu + roasted vegetables + a small portion of brown rice or quinoa. That covers your protein goal and keeps carbs in check!';
    } else if (lower.contains('weight') || lower.contains('lose')) {
      response =
          'You\'re at ${_currentTotals['calories']?.toInt() ?? 0} kcal today vs your ${_dailyGoals['maxCalories']?.toInt() ?? 2000} kcal goal. ⚖️ A 300–500 kcal daily deficit is ideal for steady fat loss. Prioritise protein to preserve muscle, and fill half your plate with non-starchy veg!';
    } else if (lower.contains('sugar') ||
        lower.contains('sweet') ||
        lower.contains('craving')) {
      response =
          'You\'re at ${_currentTotals['sugar']?.toInt() ?? 0}g sugar today (goal: ${_dailyGoals['maxSugar']?.toInt() ?? 50}g). 🍫 When cravings hit: try dark chocolate (70%+), a small handful of dates, or fresh berries. These satisfy the sweet tooth while providing real nutrients!';
    } else if (lower.contains('water') || lower.contains('hydration')) {
      response =
          'Hydration matters! 💧 Aim for 35ml per kg of body weight daily. Proper hydration boosts metabolism, reduces false hunger cues, and improves workout performance. Start each meal with a glass of water as a simple habit!';
    } else if (lower.contains('weather') ||
        lower.contains('news') ||
        lower.contains('joke') ||
        lower.contains('sport') ||
        lower.contains('football') ||
        lower.contains('cricket')) {
      response =
          'I\'m NutriBuddy — I specialise purely in nutrition, food, and health! 🥗 I can\'t help with that, but feel free to ask me about meals, macros, your goals, or scan a food photo for analysis!';
    } else {
      response =
          'Great question! I can help with meal planning, macro targets, food analysis, and advice tailored to your ${_selectedChallenges.isNotEmpty ? availableChallenges.firstWhere((c) => c.id == _selectedChallenges.first).name : 'health'} goal. Could you be more specific so I can give you the most useful answer? 🥗';
    }

    _conversationHistory.addAll([
      {'role': 'User', 'text': text},
      {'role': 'NutriBuddy', 'text': response},
    ]);
    if (_conversationHistory.length > 10) {
      _conversationHistory.removeRange(0, 2);
    }

    setState(() {
      _processingMessage = null;
      _messages.add(ChatMessage(text: response, isUser: false));
    });
    _scrollToBottom();
  }

  // ──────────────────────────────────────────────────────────
  //  CHEAT MEAL CREDIT SYSTEM
  // ──────────────────────────────────────────────────────────

  Future<void> _checkCheatCredit() async {
    setState(() {
      _processingMessage = 'Calculating your cheat credits...';
    });

    try {
      int credit = 0;
      int daysChecked = 0;

      for (int i = 1; i <= 7; i++) {
        final date = DateTime.now().subtract(Duration(days: i));
        final totals = await _firestoreService.getDailyTotals(date);
        if (totals != null) {
          daysChecked++;
          final calGoal = _dailyGoals['maxCalories'] ?? 2000;
          final proteinGoal = _dailyGoals['minProtein'] ?? 120;
          final carbGoal = _dailyGoals['maxCarbs'] ?? 200;

          if ((totals['calories'] ?? 0) <= calGoal) credit += 10;
          if ((totals['protein'] ?? 0) >= proteinGoal) credit += 5;
          // Penalise if carbs exceed goal by more than 20%
          if ((totals['carbs'] ?? 0) > carbGoal * 1.2) credit -= 5;
        }
      }

      // If no history, give a base score from today
      if (daysChecked == 0) credit = 25;
      credit = credit.clamp(0, 105);

      String advice;
      if (credit >= 70) {
        advice =
            'You\'ve been crushing it this week! 🎉 You have $credit credits — fully earned a cheat meal. Enjoy something you\'ve been craving (burger, pizza, dessert). One meal won\'t undo your progress!';
      } else if (credit >= 40) {
        advice =
            'Solid consistency — $credit credits! 💪 You\'re close to a full cheat meal. Maybe a small treat today? Keep hitting your goals and you\'ll hit 70 soon!';
      } else {
        advice =
            'Your credit is at $credit pts. Let\'s focus on hitting your calorie and protein goals for the next 3–4 days. Once you hit 70+ credits, you\'ll earn a guilt-free cheat meal!';
      }

      setState(() {
        _processingMessage = null;
        _messages.add(
          ChatMessage(
            text: '💳 Cheat Credit Score: $credit / 100\n\n$advice',
            isUser: false,
            messageType: 'credit_status',
          ),
        );
      });
      _scrollToBottom();
    } catch (e) {
      setState(() {
        _processingMessage = null;
        _messages.add(
          ChatMessage(
            text:
                'Could not calculate your cheat credit right now. Try again shortly!',
            isUser: false,
          ),
        );
      });
      _scrollToBottom();
    }
  }

  // ──────────────────────────────────────────────────────────
  //  RECIPE HEALTHIFY
  // ──────────────────────────────────────────────────────────

  void _startRecipeMode() {
    setState(() {
      _awaitingRecipe = true;
      _messages.add(
        ChatMessage(
          text:
              '📋 Recipe Healthify activated!\n\nPaste your recipe (ingredients + method) and I\'ll suggest healthier substitutions tailored to your ${_selectedChallenges.isNotEmpty ? availableChallenges.firstWhere((c) => c.id == _selectedChallenges.first).name : 'health'} goals.',
          isUser: false,
          messageType: 'recipe_mode',
        ),
      );
    });
    _scrollToBottom();
  }

  Future<void> _processRecipeHealthify(String recipeText) async {
    setState(() {
      _awaitingRecipe = false;
      _processingMessage = 'Healthifying your recipe...';
    });

    try {
      const apiKey = _kGeminiApiKey;

      if (_kDemoMode) {
        // Demo mode
        await Future.delayed(const Duration(seconds: 2));
        final goalName = _selectedChallenges.isNotEmpty
            ? availableChallenges
                  .firstWhere((c) => c.id == _selectedChallenges.first)
                  .name
            : 'balanced health';
        setState(() {
          _processingMessage = null;
          _messages.add(
            ChatMessage(
              text:
                  '🥗 Healthified Recipe!\n\nIngredient swaps for your $goalName goal:\n\n• Cream → Greek yogurt (saves ~150 kcal, adds 10g protein)\n• White pasta → Whole wheat pasta (adds 6g fibre)\n• Butter → Olive oil (better fats for heart health)\n• Table salt → Herbs + lemon juice (reduces sodium)\n• White rice → Cauliflower rice or quinoa (cuts net carbs)\n\n📊 Estimated change:\nBefore: ~650 kcal | 18g protein | 75g carbs\nAfter:  ~420 kcal | 28g protein | 45g carbs\n\nTip: Batch-cook and refrigerate — flavours improve overnight! 💪',
              isUser: false,
            ),
          );
        });
        _scrollToBottom();
        return;
      }

      final healthProfile = await _firestoreService.getHealthProfile();
      final userContext = _buildUserContext(healthProfile);
      final goalNames = _selectedChallenges.isNotEmpty
          ? _selectedChallenges
                .map(
                  (id) =>
                      availableChallenges.firstWhere((c) => c.id == id).name,
                )
                .join(', ')
          : 'balanced health';

      final prompt =
          '''
$userContext
The user wants to make this recipe healthier for their goals: $goalNames

Recipe:
$recipeText

Provide:
1. Ingredient-by-ingredient substitutions with brief reasons
2. Preparation tips to reduce calories or unhealthy components
3. Estimated before vs after macros (calories, protein, carbs, fat)
4. Two specific tips for their $goalNames goal

Keep the tone warm and practical.
''';

      final model = GenerativeModel(model: 'gemini-2.5-flash', apiKey: apiKey);
      final response = await model.generateContent([Content.text(prompt)]);

      setState(() {
        _processingMessage = null;
        _messages.add(
          ChatMessage(
            text: response.text ?? 'Could not healthify your recipe.',
            isUser: false,
          ),
        );
      });
      _scrollToBottom();
    } catch (e) {
      setState(() {
        _processingMessage = null;
        _awaitingRecipe = false;
        _messages.add(
          ChatMessage(
            text:
                'Sorry, I had trouble with your recipe. Please try pasting it again!',
            isUser: false,
          ),
        );
      });
      _scrollToBottom();
    }
  }

  // ──────────────────────────────────────────────────────────
  //  MOOD LOGGING
  // ──────────────────────────────────────────────────────────

  Future<void> _saveMoodLog(String foodName, String mood) async {
    try {
      await _firestoreService.saveMoodLog(foodName, mood);
      setState(() {
        _messages.add(
          ChatMessage(
            text:
                'Logged $mood after $foodName. I\'ll use this to spot patterns over time! 📊',
            isUser: false,
          ),
        );
      });
      _scrollToBottom();
    } catch (e) {
      debugPrint('Error saving mood: $e');
    }
  }

  // ──────────────────────────────────────────────────────────
  //  FEATURE LAUNCHERS
  // ──────────────────────────────────────────────────────────

  Future<void> _launchVideoAnalysis() async {
    final result = await Navigator.push<AggregatedMealResult>(
      context,
      MaterialPageRoute(
        builder: (context) => VideoAnalysisScreen(
          currentTotals: _currentTotals,
          dailyGoals: _dailyGoals,
          selectedChallenges: _selectedChallenges,
          amdBackendAvailable: _amdBackendAvailable,
          apiKey: _kGeminiApiKey,
        ),
      ),
    );
    if (result != null && mounted) {
      final cal = result.totalNutrition['calories'] ?? 0.0;
      final pro = result.totalNutrition['protein'] ?? 0.0;
      final carbs = result.totalNutrition['carbs'] ?? 0.0;
      final fat = result.totalNutrition['fat'] ?? 0.0;
      final sugar = result.totalNutrition['sugar'] ?? 0.0;
      setState(() {
        _currentTotals['calories'] = (_currentTotals['calories'] ?? 0) + cal;
        _currentTotals['protein'] = (_currentTotals['protein'] ?? 0) + pro;
        _currentTotals['carbs'] = (_currentTotals['carbs'] ?? 0) + carbs;
        _currentTotals['fat'] = (_currentTotals['fat'] ?? 0) + fat;
        _currentTotals['sugar'] = (_currentTotals['sugar'] ?? 0) + sugar;
        _messages.add(
          ChatMessage(
            text:
                '🎬 Multi-frame scan complete!\n'
                '📊 ${result.foodFrames} food frame${result.foodFrames == 1 ? '' : 's'} analyzed\n'
                '• Calories: +${cal.toInt()} kcal\n'
                '• Protein: +${pro.toInt()}g\n'
                '• Carbs: +${carbs.toInt()}g\n'
                '• Fat: +${fat.toInt()}g\n\n'
                '✅ Added to today\'s log!',
            isUser: false,
          ),
        );
      });
      await _firestoreService.saveDailyTotals(_currentTotals);
      _scrollToBottom();
    }
  }

  Future<void> _launchSmartCart() async {
    setState(() {
      _messages.add(
        ChatMessage(
          text:
              '🛒 Smart Grocery Cart opened — your items will sync here in real time as you scan or add them!',
          isUser: false,
        ),
      );
    });
    _scrollToBottom();
    // Non-blocking: user can keep chatting while cart is open
    Navigator.push<List<CartItem>>(
      context,
      MaterialPageRoute(
        builder: (context) => SmartCartScreen(
          dailyGoals: _dailyGoals,
          selectedChallenges: _selectedChallenges,
          amdBackendAvailable: _amdBackendAvailable,
          apiKey: _kGeminiApiKey,
        ),
      ),
    ).then((items) {
      if (!mounted) return;
      if (items != null && items.isNotEmpty) {
        setState(() {
          _messages.add(
            ChatMessage(
              text:
                  '✅ Cart session done! ${items.length} item${items.length == 1 ? '' : 's'} optimized and saved.',
              isUser: false,
            ),
          );
        });
        _scrollToBottom();
      }
    });
  }

  Future<void> _launchSupplementOptimizer() async {
    setState(() {
      _messages.add(
        ChatMessage(
          text: '💊 Opening Supplement Stack Optimizer...',
          isUser: false,
        ),
      );
    });
    _scrollToBottom();
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => SupplementOptimizerScreen(
          selectedChallenges: _selectedChallenges,
          currentTotals: _currentTotals,
          dailyGoals: _dailyGoals,
          amdBackendAvailable: _amdBackendAvailable,
        ),
      ),
    );
    if (mounted) {
      setState(() {
        _messages.add(
          ChatMessage(
            text:
                '✅ Supplement stack saved! Your personalized timing schedule has been updated.',
            isUser: false,
          ),
        );
      });
      _scrollToBottom();
    }
  }

  Future<void> _launchFamilyHub() async {
    setState(() {
      _messages.add(
        ChatMessage(
          text: '👨‍👩‍👧 Opening Family Nutrition Hub...',
          isUser: false,
        ),
      );
    });
    _scrollToBottom();
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => FamilyHubScreen(apiKey: _kGeminiApiKey),
      ),
    );
    if (mounted) {
      setState(() {
        _messages.add(
          ChatMessage(
            text:
                '✅ Family hub session complete! Meal plans and nutrition goals have been saved for your family.',
            isUser: false,
          ),
        );
      });
      _scrollToBottom();
    }
  }

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.of(context).size.width >= 600;

    // ── Navigation destinations ─────────────────────────────────────────
    const railDestinations = <NavigationRailDestination>[
      NavigationRailDestination(
        icon: Icon(Icons.chat_bubble_outline),
        selectedIcon: Icon(Icons.chat_bubble),
        label: Text('Chat'),
      ),
      NavigationRailDestination(
        icon: Icon(Icons.people_outline),
        selectedIcon: Icon(Icons.people),
        label: Text('Family'),
      ),
      NavigationRailDestination(
        icon: Icon(Icons.medication_outlined),
        selectedIcon: Icon(Icons.medication),
        label: Text('Supplements'),
      ),
      NavigationRailDestination(
        icon: Icon(Icons.emoji_events_outlined),
        selectedIcon: Icon(Icons.emoji_events),
        label: Text('Goals'),
      ),
    ];

    const barDestinations = <NavigationDestination>[
      NavigationDestination(
        icon: Icon(Icons.chat_bubble_outline, size: 22),
        selectedIcon: Icon(Icons.chat_bubble, size: 22),
        label: 'Chat',
      ),
      NavigationDestination(
        icon: Icon(Icons.people_outline, size: 22),
        selectedIcon: Icon(Icons.people, size: 22),
        label: 'Family',
      ),
      NavigationDestination(
        icon: Icon(Icons.medication_outlined, size: 22),
        selectedIcon: Icon(Icons.medication, size: 22),
        label: 'Supplements',
      ),
      NavigationDestination(
        icon: Icon(Icons.emoji_events_outlined, size: 22),
        selectedIcon: Icon(Icons.emoji_events, size: 22),
        label: 'Goals',
      ),
    ];

    // ── Tab content (IndexedStack keeps all alive) ─────────────────────
    final tabs = <Widget>[
      _buildChatBody(isWide),
      FamilyHubScreen(apiKey: _kGeminiApiKey),
      SupplementOptimizerScreen(
        selectedChallenges: _selectedChallenges,
        currentTotals: _currentTotals,
        dailyGoals: _dailyGoals,
        amdBackendAvailable: _amdBackendAvailable,
      ),
      ChallengesScreen(
        initialSelected: _selectedChallenges,
        onChanged: (list) {
          setState(() => _selectedChallenges = list);
          _saveSelectedChallenges();
        },
      ),
    ];

    // ── Chat AppBar (only shown on the Chat tab) ───────────────────────
    final chatAppBar = AppBar(
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            '🥗 NutriBuddy',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
          ),
          Row(
            children: [
              const Text(
                'Your nutrition companion',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w300),
              ),
              if (_amdBackendAvailable) ...[
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 5,
                    vertical: 1,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.red.shade700,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Text(
                    '⚡ AMD GPU',
                    style: TextStyle(
                      fontSize: 9,
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
      actions: [
        Padding(
          padding: const EdgeInsets.only(right: 4.0),
          child: IconButton(
            icon: Badge(
              isLabelVisible: _cartItemCount > 0,
              label: Text(_cartItemCount.toString()),
              backgroundColor: Colors.green,
              child: const Icon(Icons.shopping_cart),
            ),
            tooltip: 'Smart Grocery Cart',
            onPressed: _launchSmartCart,
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(right: 8.0),
          child: IconButton(
            icon: const Icon(Icons.settings),
            tooltip: 'Settings',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const SettingsScreen()),
              );
            },
          ),
        ),
      ],
    );

    if (isWide) {
      // ── Wide layout: NavigationRail on the left ─────────────────────
      return Scaffold(
        appBar: _selectedTab == 0 ? chatAppBar : null,
        body: Row(
          children: [
            NavigationRail(
              selectedIndex: _selectedTab,
              onDestinationSelected: (i) => setState(() => _selectedTab = i),
              labelType: NavigationRailLabelType.all,
              destinations: railDestinations,
              leading: const SizedBox(height: 8),
            ),
            const VerticalDivider(thickness: 1, width: 1),
            Expanded(
              child: IndexedStack(index: _selectedTab, children: tabs),
            ),
          ],
        ),
      );
    } else {
      // ── Narrow layout: NavigationBar at the bottom ──────────────────
      return Scaffold(
        appBar: _selectedTab == 0 ? chatAppBar : null,
        bottomNavigationBar: NavigationBar(
          selectedIndex: _selectedTab,
          onDestinationSelected: (i) => setState(() => _selectedTab = i),
          labelBehavior: NavigationDestinationLabelBehavior.onlyShowSelected,
          height: 62,
          destinations: barDestinations,
        ),
        body: IndexedStack(index: _selectedTab, children: tabs),
      );
    }
  }

  // Chat tab body – the full progress-panel + messaging UI
  Widget _buildChatBody(bool isWide) {
    // ── Shared chat column ────────────────────────────────────────────
    Widget chatColumn = Column(
      children: [
        Expanded(
          child: _messages.isEmpty
              ? const Center(
                  child: Text('Start a conversation by sending a message'),
                )
              : ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.all(8),
                  itemCount: _messages.length,
                  itemBuilder: (context, index) {
                    return _buildChatMessage(_messages[index]);
                  },
                ),
        ),
        if (_processingMessage != null)
          Container(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                SizedBox(
                  width: 20,
                  height: 20,
                  child: _isAnalyzingImage
                      ? const Icon(Icons.camera_alt, size: 20)
                      : const CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(width: 12),
                Flexible(
                  child: Text(
                    _processingMessage!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.primary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
        if (_messages.length <= 2 && _processingMessage == null)
          _buildSuggestedPrompts(),
        _buildBottomInputBar(),
      ],
    );

    if (isWide) {
      // ── Wide: progress panel left + chat right ────────────────────
      return Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            width: 230,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              border: Border(
                right: BorderSide(
                  color: Theme.of(context).colorScheme.outlineVariant,
                  width: 1,
                ),
              ),
            ),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildDailySummaryCard(),
                  const Divider(height: 1),
                  _buildChallengesChips(),
                ],
              ),
            ),
          ),
          Expanded(child: chatColumn),
        ],
      );
    } else {
      // ── Narrow: collapsible progress header + chat ────────────────
      final colorScheme = Theme.of(context).colorScheme;
      return Column(
        children: [
          InkWell(
            onTap: () => setState(
              () => _progressPanelExpanded = !_progressPanelExpanded,
            ),
            child: Container(
              color: colorScheme.surfaceContainerHighest,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  Icon(
                    Icons.track_changes,
                    size: 16,
                    color: colorScheme.primary,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Today\'s Progress & Goals',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: colorScheme.primary,
                      ),
                    ),
                  ),
                  Icon(
                    _progressPanelExpanded
                        ? Icons.expand_less
                        : Icons.expand_more,
                    size: 18,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ],
              ),
            ),
          ),
          AnimatedCrossFade(
            duration: const Duration(milliseconds: 200),
            crossFadeState: _progressPanelExpanded
                ? CrossFadeState.showFirst
                : CrossFadeState.showSecond,
            firstChild: Column(
              mainAxisSize: MainAxisSize.min,
              children: [_buildDailySummaryCard(), _buildChallengesChips()],
            ),
            secondChild: const SizedBox.shrink(),
          ),
          const Divider(height: 1),
          Expanded(child: chatColumn),
        ],
      );
    }
  }

  Widget _buildBottomInputBar() {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          child: Row(
            children: [
              // Camera Button
              IconButton(
                onPressed: _isAnalyzingImage
                    ? null
                    : () => _pickImage(ImageSource.camera),
                icon: const Icon(Icons.camera_alt),
                tooltip: 'Take Photo',
                style: IconButton.styleFrom(
                  backgroundColor: Theme.of(
                    context,
                  ).colorScheme.primaryContainer,
                ),
              ),
              const SizedBox(width: 4),

              // Gallery Button
              IconButton(
                onPressed: _isAnalyzingImage
                    ? null
                    : () => _pickImage(ImageSource.gallery),
                icon: const Icon(Icons.photo_library),
                tooltip: 'Upload from Gallery',
                style: IconButton.styleFrom(
                  backgroundColor: Theme.of(
                    context,
                  ).colorScheme.primaryContainer,
                ),
              ),
              const SizedBox(width: 4),

              // Multi-Frame Video Analysis Button
              IconButton(
                onPressed: _isAnalyzingImage ? null : _launchVideoAnalysis,
                icon: const Icon(Icons.video_collection),
                tooltip: 'Multi-Frame Meal Scan',
                style: IconButton.styleFrom(
                  backgroundColor: _amdBackendAvailable
                      ? Colors.red.shade700.withValues(alpha: 0.15)
                      : Theme.of(context).colorScheme.primaryContainer,
                  foregroundColor: _amdBackendAvailable
                      ? Colors.red.shade700
                      : null,
                ),
              ),
              const SizedBox(width: 8),

              // Text Input Field
              Expanded(
                child: TextField(
                  controller: _messageController,
                  decoration: InputDecoration(
                    hintText: 'Ask about nutrition...',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(24),
                      borderSide: BorderSide.none,
                    ),
                    filled: true,
                    fillColor: Theme.of(
                      context,
                    ).colorScheme.surfaceContainerHighest,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 10,
                    ),
                  ),
                  maxLines: null,
                  textCapitalization: TextCapitalization.sentences,
                  onSubmitted: (_) => _sendTextMessage(),
                ),
              ),
              const SizedBox(width: 8),

              // Send Button
              IconButton(
                onPressed: _sendTextMessage,
                icon: const Icon(Icons.send),
                tooltip: 'Send',
                style: IconButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.primary,
                  foregroundColor: Theme.of(context).colorScheme.onPrimary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildChatMessage(ChatMessage message) {
    final cs = Theme.of(context).colorScheme;
    final isUser = message.isUser;

    // Bubble shape: pointed corner on the sender's side
    final bubbleRadius = BorderRadius.only(
      topLeft: const Radius.circular(18),
      topRight: const Radius.circular(18),
      bottomLeft: Radius.circular(isUser ? 18 : 4),
      bottomRight: Radius.circular(isUser ? 4 : 18),
    );

    final bubbleColor = isUser ? cs.primary : cs.surfaceContainerHighest;
    final textColor = isUser ? cs.onPrimary : cs.onSurface;

    Widget avatar = Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: isUser ? cs.primaryContainer : cs.secondaryContainer,
      ),
      child: Center(
        child: Text(isUser ? '👤' : '🥗', style: const TextStyle(fontSize: 15)),
      ),
    );

    Widget bubble = Container(
      constraints: BoxConstraints(
        maxWidth: MediaQuery.of(context).size.width * 0.72,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: bubbleColor,
        borderRadius: bubbleRadius,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Sender label
          Text(
            isUser ? 'You' : 'NutriBuddy',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: isUser ? cs.onPrimary.withValues(alpha: 0.7) : cs.primary,
              letterSpacing: 0.3,
            ),
          ),
          const SizedBox(height: 4),

          // Image if present
          if (message.imageBytes != null) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Image.memory(
                message.imageBytes!,
                height: 180,
                width: double.infinity,
                fit: BoxFit.cover,
              ),
            ),
            const SizedBox(height: 8),
          ],

          // Message text
          if (isUser)
            Text(
              message.text,
              style: TextStyle(color: textColor, fontSize: 14, height: 1.4),
            )
          else
            MarkdownBody(
              data: message.text,
              shrinkWrap: true,
              styleSheet: MarkdownStyleSheet.fromTheme(Theme.of(context))
                  .copyWith(
                    p: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: textColor,
                      fontSize: 14,
                      height: 1.45,
                    ),
                    strong: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: textColor,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                    listBullet: Theme.of(context).textTheme.bodyMedium
                        ?.copyWith(color: textColor, fontSize: 14),
                  ),
            ),

          // Show analysis data if present
          if (message.analysisData != null) ...[
            const SizedBox(height: 12),
            _buildAnalysisCard(message.analysisData!),
          ],

          // Mood prompt buttons
          if (message.messageType == 'mood_prompt') ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              children: ['😊', '😐', '😔', '😴', '😤'].map((emoji) {
                return InkWell(
                  onTap: () =>
                      _saveMoodLog(message.foodNameForMood ?? 'food', emoji),
                  borderRadius: BorderRadius.circular(20),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: Theme.of(
                        context,
                      ).colorScheme.primaryContainer.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: Theme.of(
                          context,
                        ).colorScheme.primary.withValues(alpha: 0.3),
                      ),
                    ),
                    child: Text(emoji, style: const TextStyle(fontSize: 20)),
                  ),
                );
              }).toList(),
            ),
          ],

          // Recipe mode indicator
          if (message.messageType == 'recipe_mode') ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.green.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.green.withValues(alpha: 0.3)),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.edit_note, size: 14, color: Colors.green),
                  SizedBox(width: 4),
                  Text(
                    'Awaiting your recipe...',
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.green,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ],

          // Credit status indicator
          if (message.messageType == 'credit_status') ...[
            const SizedBox(height: 8),
            LinearProgressIndicator(
              value: () {
                final match = RegExp(r'(\d+) / 100').firstMatch(message.text);
                if (match != null) {
                  return (int.tryParse(match.group(1) ?? '0') ?? 0) / 100.0;
                }
                return 0.0;
              }(),
              backgroundColor: Theme.of(
                context,
              ).colorScheme.primary.withValues(alpha: 0.15),
              color: Colors.amber,
              minHeight: 6,
              borderRadius: BorderRadius.circular(4),
            ),
          ],

          // Timestamp
          const SizedBox(height: 4),
          Text(
            _formatTime(message.timestamp),
            style: TextStyle(
              fontSize: 10,
              color: textColor.withValues(alpha: 0.55),
            ),
          ),
        ],
      ),
    );

    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: isUser
              ? [bubble, const SizedBox(width: 6), avatar]
              : [avatar, const SizedBox(width: 6), bubble],
        ),
      ),
    );
  }

  String _formatTime(DateTime time) {
    final now = DateTime.now();
    final diff = now.difference(time);

    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inHours < 1) return '${diff.inMinutes}m ago';
    if (diff.inDays < 1) return '${diff.inHours}h ago';
    return '${time.hour}:${time.minute.toString().padLeft(2, '0')}';
  }

  Widget _buildAnalysisCard(Map<String, dynamic> result) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
      ),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Product name and score
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  result['productName'] ?? 'Unknown Product',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: _getScoreColor(result['complianceScore'] ?? 0),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  '${result['complianceScore']}%',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            result['servingSize'] ?? '',
            style: const TextStyle(fontSize: 12, color: Colors.grey),
          ),
          const SizedBox(height: 12),

          // Nutrition info
          _buildNutritionGrid(result['nutrition']),

          // Recommendation
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: _getRecommendationColor(
                result['recommendation'],
              ).withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              result['reason'] ?? '',
              style: const TextStyle(fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNutritionGrid(dynamic nutrition) {
    if (nutrition == null) return const SizedBox.shrink();

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        _buildNutrientChip('Calories', nutrition['calories'], ''),
        _buildNutrientChip('Protein', nutrition['protein'], 'g'),
        _buildNutrientChip('Carbs', nutrition['carbs'], 'g'),
        _buildNutrientChip('Fat', nutrition['fat'], 'g'),
        _buildNutrientChip('Sugar', nutrition['sugar'], 'g'),
      ],
    );
  }

  Widget _buildNutrientChip(String label, dynamic value, String unit) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Theme.of(
          context,
        ).colorScheme.primaryContainer.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        '$label: $value$unit',
        style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w500),
      ),
    );
  }

  Color _getScoreColor(int score) {
    if (score >= 80) return Colors.green;
    if (score >= 60) return Colors.orange;
    return Colors.red;
  }

  Color _getRecommendationColor(String? recommendation) {
    switch (recommendation) {
      case 'highly_recommended':
        return Colors.green;
      case 'recommended':
        return Colors.lightGreen;
      case 'moderate':
        return Colors.orange;
      case 'not_recommended':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  Widget _buildDailySummaryCard() {
    // Compute day-of-challenge for the primary active goal
    int? dayOfChallenge;
    if (_selectedChallenges.isNotEmpty) {
      final startStr = _challengeStartDates[_selectedChallenges.first];
      if (startStr != null) {
        final start = DateTime.tryParse(startStr);
        if (start != null) {
          dayOfChallenge = DateTime.now().difference(start).inDays + 1;
        }
      }
    }

    return Container(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.track_changes,
                color: Theme.of(context).colorScheme.primary,
                size: 20,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Today\'s Progress${dayOfChallenge != null ? ' · Day $dayOfChallenge' : ''}',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              if (_challengeStats != null && _challengeStats!.streakDays > 0)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.orange.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: Colors.orange.withValues(alpha: 0.4),
                      width: 1,
                    ),
                  ),
                  child: Text(
                    '🔥 ${_challengeStats!.streakDays}d streak',
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: Colors.orange,
                    ),
                  ),
                ),
            ],
          ),
          if (_challengeStats != null && _challengeStats!.totalDaysTracked > 1)
            Padding(
              padding: const EdgeInsets.only(top: 4, bottom: 2),
              child: Text(
                '${_challengeStats!.totalDaysTracked} days tracked · '
                '${_challengeStats!.goalHitRate}% goal hit rate · '
                'avg ${_challengeStats!.avgCalories} kcal/day',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(
                    context,
                  ).colorScheme.onSurface.withValues(alpha: 0.6),
                ),
              ),
            ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _buildCompactStat(
                  'Cal',
                  _currentTotals['calories']!,
                  _dailyGoals['maxCalories']!,
                  Colors.orange,
                ),
              ),
              Expanded(
                child: _buildCompactStat(
                  'Protein',
                  _currentTotals['protein']!,
                  _dailyGoals['minProtein']!,
                  Colors.red,
                ),
              ),
              Expanded(
                child: _buildCompactStat(
                  'Carbs',
                  _currentTotals['carbs']!,
                  _dailyGoals['maxCarbs']!,
                  Colors.blue,
                ),
              ),
              Expanded(
                child: _buildCompactStat(
                  'Fat',
                  _currentTotals['fat']!,
                  _dailyGoals['maxFat']!,
                  Colors.yellow.shade700,
                ),
              ),
              Expanded(
                child: _buildCompactStat(
                  'Sugar',
                  _currentTotals['sugar']!,
                  _dailyGoals['maxSugar']!,
                  Colors.pink,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildChallengesChips() {
    if (_selectedChallenges.isEmpty) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Icon(
              Icons.emoji_events_outlined,
              size: 16,
              color: Theme.of(
                context,
              ).colorScheme.onSurface.withValues(alpha: 0.5),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'No goals set - tap the trophy icon to get started',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(
                    context,
                  ).colorScheme.onSurface.withValues(alpha: 0.5),
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.emoji_events,
                size: 16,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(width: 6),
              Text(
                'Active Goals',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _selectedChallenges.map((challengeId) {
              final challenge = availableChallenges.firstWhere(
                (c) => c.id == challengeId,
              );
              return Chip(
                avatar: Text(
                  challenge.icon,
                  style: const TextStyle(fontSize: 14),
                ),
                label: Text(
                  challenge.name,
                  style: const TextStyle(fontSize: 12),
                ),
                backgroundColor: challenge.color.withValues(alpha: 0.15),
                side: BorderSide(
                  color: challenge.color.withValues(alpha: 0.3),
                  width: 1,
                ),
                deleteIcon: Icon(Icons.close, size: 16, color: challenge.color),
                onDeleted: () {
                  setState(() {
                    _selectedChallenges.remove(challengeId);
                  });
                  _saveSelectedChallenges();
                },
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildSuggestedPrompts() {
    // (icon, label, directAction) — null directAction uses text routing
    final chips = <(String, String, Future<void> Function()?)>[
      ('🥣', 'What should I eat now?', null),
      ('💳', 'Check my cheat credits', null),
      ('🍳', 'Healthify a recipe', null),
      ('🛒', 'Smart grocery cart', () => _launchSmartCart()),
      ('💊', 'My supplement stack', () => _launchSupplementOptimizer()),
      ('�‍👩‍👧', 'Family nutrition hub', () => _launchFamilyHub()),
      ('�📊', 'How are my macros?', null),
    ];
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 2),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: chips.map((c) {
            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ActionChip(
                avatar: Text(c.$1),
                label: Text(c.$2, style: const TextStyle(fontSize: 12)),
                onPressed: () {
                  if (c.$3 != null) {
                    c.$3!();
                  } else {
                    _messageController.text = c.$2;
                    _sendTextMessage();
                  }
                },
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildCompactStat(
    String label,
    double current,
    double goal,
    Color color,
  ) {
    final progress = (current / goal).clamp(0.0, 1.0);
    return Column(
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500),
        ),
        const SizedBox(height: 4),
        Stack(
          alignment: Alignment.center,
          children: [
            SizedBox(
              width: 40,
              height: 40,
              child: CircularProgressIndicator(
                value: progress,
                strokeWidth: 3,
                backgroundColor: color.withValues(alpha: 0.2),
                color: color,
              ),
            ),
            Text(
              '${(progress * 100).toInt()}%',
              style: const TextStyle(fontSize: 9, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          '${current.toInt()}/${goal.toInt()}',
          style: const TextStyle(fontSize: 9),
        ),
      ],
    );
  }
}
