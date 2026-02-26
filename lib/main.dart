import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'challenges_screen.dart';
import 'services/firestore_service.dart';
import 'services/nutrition_calculator.dart';
import 'screens/sign_in_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/health_profile_screen.dart';

// ─────────────────────────────────────────────
// 🔑  REPLACE THIS WITH YOUR REAL GEMINI API KEY
// Get one free at: https://aistudio.google.com/app/apikey
// Leave it as-is to run in safe demo mode (simulated responses, no real calls)
const _kGeminiApiKey = 'YOUR_GEMINI_API_KEY_HERE';
const _kDemoMode = _kGeminiApiKey == 'YOUR_GEMINI_API_KEY_HERE';
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
      options: const FirebaseOptions(
        apiKey: 'AIzaSyD-4aQeMTxdHpcKS0mzhSz0gkS_iVIbejk',
        authDomain: 'nutribuddy-4e3b7.firebaseapp.com',
        projectId: 'nutribuddy-4e3b7',
        storageBucket: 'nutribuddy-4e3b7.firebasestorage.app',
        messagingSenderId: '328896889583',
        appId: '1:328896889583:web:8290c9555b75d0d8d0511a',
      ),
    );
  } catch (e) {
    print('Firebase initialization error: $e');
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
        // Show loading while checking auth state
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        // Show sign-in screen if not authenticated
        if (!snapshot.hasData) {
          return const SignInScreen();
        }

        // Check if user has completed health profile
        return FutureBuilder<bool>(
          future: FirestoreService().hasCompletedHealthProfile(),
          builder: (context, profileSnapshot) {
            if (profileSnapshot.connectionState == ConnectionState.waiting) {
              return const Scaffold(
                body: Center(child: CircularProgressIndicator()),
              );
            }

            // Show health profile screen if not completed
            if (profileSnapshot.data == false) {
              return const HealthProfileScreen();
            }

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
  final File? image;
  final Map<String, dynamic>? analysisData;
  final DateTime timestamp;
  // 'mood_prompt' | 'credit_status' | 'recipe_mode' | null
  final String? messageType;
  final String? foodNameForMood;

  ChatMessage({
    required this.text,
    required this.isUser,
    this.image,
    this.analysisData,
    this.messageType,
    this.foodNameForMood,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();
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
  File? _selectedImage;
  // null = not processing, non-null = loading message to display
  String? _processingMessage;
  Map<String, dynamic>? _analysisResult;
  List<String> _selectedChallenges = [];
  // Conversation history for AI context (last 5 exchanges = 10 messages)
  final List<Map<String, String>> _conversationHistory = [];
  // Whether we are awaiting a recipe paste for Recipe Healthify
  bool _awaitingRecipe = false;

  @override
  void initState() {
    super.initState();
    _loadDataFromCloud();
    _loadWelcomeMessage();
  }

  Future<void> _loadWelcomeMessage() async {
    final healthProfile = await _firestoreService.getHealthProfile();
    final userName = healthProfile?.name ?? 'there';
    final hour = DateTime.now().hour;

    String timeGreeting;
    String timeTip;
    if (hour >= 5 && hour < 12) {
      timeGreeting = 'Good morning';
      timeTip = 'Great time for a protein-rich breakfast to fuel your day! ☀️';
    } else if (hour >= 12 && hour < 17) {
      timeGreeting = 'Good afternoon';
      timeTip = 'Keep up your nutrition goals this afternoon! 🌤️';
    } else if (hour >= 17 && hour < 21) {
      timeGreeting = 'Good evening';
      timeTip =
          'Evening tip: keep dinner light and nutrient-dense for better sleep. 🌙';
    } else {
      timeGreeting = 'Hey';
      timeTip =
          'Late-night tip: if hungry, choose something light and protein-rich. 🌙';
    }

    setState(() {
      _messages.add(
        ChatMessage(
          text:
              '$timeGreeting, $userName! 👋 I\'m NutriBuddy, your AI nutrition companion. 🥗\n\n$timeTip\n\nYou can:\n• 📸 Scan food photos for instant analysis\n• 💬 Ask any nutrition or diet question\n• 🍳 Paste a recipe to healthify it\n• 💳 Check your cheat meal credits',
          isUser: false,
        ),
      );
    });
  }

  @override
  void dispose() {
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
    'calories': 850,
    'protein': 45,
    'carbs': 95,
    'fat': 28,
    'sugar': 18,
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
        setState(() {
          _selectedImage = File(image.path);
          _analysisResult = null;
        });

        // Add user message with image
        _messages.add(
          ChatMessage(
            text: "Please analyze this food item",
            isUser: true,
            image: File(image.path),
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
    } catch (e) {
      print('Error loading data from cloud: $e');
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
      print('Error loading challenges: $e');
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
      print('Error saving challenges: $e');
    }
  }

  Future<void> _sendTextMessage() async {
    final text = _messageController.text.trim();
    if (text.isEmpty) return;
    if (_processingMessage != null) return; // prevent spam while processing

    setState(() {
      _messages.add(ChatMessage(text: text, isUser: true));
      _messageController.clear();
    });
    _scrollToBottom();

    final lower = text.toLowerCase();

    // If awaiting a recipe paste, process it
    if (_awaitingRecipe) {
      await _processRecipeHealthify(text);
      return;
    }

    // Route to specific feature handlers based on intent
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

      final model = GenerativeModel(model: 'gemini-1.5-flash', apiKey: apiKey);

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
- Blood Group: ${healthProfile.bloodGroup}
- Calculated Daily Needs: ${calculatedCalories.round()} calories

IMPORTANT: Consider the user's age, gender, and BMI when providing recommendations. Ensure advice is age-appropriate and supports their health status. If any ingredients or nutritional aspects might be relevant to blood group ${healthProfile.bloodGroup} or their BMI category, mention them.
''';
      }

      final imageBytes = await _selectedImage!.readAsBytes();
      final prompt =
          '''
Analyze this food product image and provide nutritional information in JSON format.

Include:
1. Product name
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

        final productName = result['productName'] as String? ?? 'that food';

        setState(() {
          _analysisResult = result;
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
    } catch (e) {
      setState(() {
        _processingMessage = null;
      });
      _showError(
        'Analysis failed: $e\n\nNote: Add your Gemini API key to enable real AI analysis.',
      );
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
      _processingMessage = null;

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

      // Update daily totals in cloud
      await _firestoreService.saveDailyTotals(_currentTotals);
    } catch (e) {
      print('Error saving analysis to cloud: $e');
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
- BMI: ${bmi.toStringAsFixed(1)} ($bmiCat), Blood Group: ${profile.bloodGroup}
- Active Health Goals: $goals

Today's Intake vs Goals:
- Calories: ${_currentTotals['calories']?.toInt()}/${_dailyGoals['maxCalories']?.toInt()} kcal
- Protein:  ${_currentTotals['protein']?.toInt()}/${_dailyGoals['minProtein']?.toInt()} g
- Carbs:    ${_currentTotals['carbs']?.toInt()}/${_dailyGoals['maxCarbs']?.toInt()} g
- Fat:      ${_currentTotals['fat']?.toInt()}/${_dailyGoals['maxFat']?.toInt()} g
- Sugar:    ${_currentTotals['sugar']?.toInt()}/${_dailyGoals['maxSugar']?.toInt()} g
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

  /// Main conversational AI handler for text questions.
  Future<void> _processTextQuery(String text) async {
    setState(() {
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
$circadian
$historyStr
Answer the following question with personalised, actionable advice. Be warm and concise. Reference the user's specific profile or goals where relevant. Keep paragraphs short.

User: $text
''';

      final model = GenerativeModel(model: 'gemini-1.5-flash', apiKey: apiKey);
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
        _processingMessage = null;
        _messages.add(ChatMessage(text: responseText, isUser: false));
      });
      _scrollToBottom();
    } catch (e) {
      setState(() {
        _processingMessage = null;
        _messages.add(
          ChatMessage(
            text:
                'Sorry, I had trouble responding right now. Please try again! 😅',
            isUser: false,
          ),
        );
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

      final model = GenerativeModel(model: 'gemini-1.5-flash', apiKey: apiKey);
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
      print('Error saving mood: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '🥗 NutriBuddy',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
            ),
            Text(
              'Your nutrition companion',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w300),
            ),
          ],
        ),
        actions: [
          // Challenges/Goals Button
          Padding(
            padding: const EdgeInsets.only(right: 4.0),
            child: IconButton(
              icon: Badge(
                isLabelVisible: _selectedChallenges.isNotEmpty,
                label: Text(_selectedChallenges.length.toString()),
                child: const Icon(Icons.emoji_events),
              ),
              tooltip: 'Select Your Goals',
              onPressed: () async {
                final result = await Navigator.push<List<String>>(
                  context,
                  MaterialPageRoute(
                    builder: (context) =>
                        ChallengesScreen(initialSelected: _selectedChallenges),
                  ),
                );
                if (result != null) {
                  setState(() {
                    _selectedChallenges = result;
                  });
                  await _saveSelectedChallenges();
                }
              },
            ),
          ),
          // Settings Button
          Padding(
            padding: const EdgeInsets.only(right: 8.0),
            child: IconButton(
              icon: const Icon(Icons.settings),
              tooltip: 'Settings',
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const SettingsScreen(),
                  ),
                );
              },
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          // Daily Summary Card at top
          _buildDailySummaryCard(),

          // Selected Challenges Chips
          _buildChallengesChips(),

          const Divider(height: 1),

          // Chat Messages Section
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

          // Loading indicator
          if (_processingMessage != null)
            Container(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    _processingMessage!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.primary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),

          // Suggested prompt chips (show only at start of conversation)
          if (_messages.length <= 2 && _processingMessage == null)
            _buildSuggestedPrompts(),

          // Bottom Input Bar with Media Upload
          _buildBottomInputBar(),
        ],
      ),
    );
  }

  Widget _buildBottomInputBar() {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
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
                onPressed: () => _pickImage(ImageSource.camera),
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
                onPressed: () => _pickImage(ImageSource.gallery),
                icon: const Icon(Icons.photo_library),
                tooltip: 'Upload from Gallery',
                style: IconButton.styleFrom(
                  backgroundColor: Theme.of(
                    context,
                  ).colorScheme.primaryContainer,
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
    return Align(
      alignment: message.isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.75,
        ),
        child: Card(
          color: message.isUser
              ? Theme.of(context).colorScheme.primaryContainer
              : Theme.of(context).colorScheme.surfaceContainerHighest,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Show image if present
                if (message.image != null) ...[
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.file(
                      message.image!,
                      height: 200,
                      width: double.infinity,
                      fit: BoxFit.cover,
                    ),
                  ),
                  const SizedBox(height: 8),
                ],

                // Show text
                Text(
                  message.text,
                  style: TextStyle(
                    color: message.isUser
                        ? Theme.of(context).colorScheme.onPrimaryContainer
                        : Theme.of(context).colorScheme.onSurface,
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
                        onTap: () => _saveMoodLog(
                          message.foodNameForMood ?? 'food',
                          emoji,
                        ),
                        borderRadius: BorderRadius.circular(20),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: Theme.of(
                              context,
                            ).colorScheme.primaryContainer.withOpacity(0.5),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: Theme.of(
                                context,
                              ).colorScheme.primary.withOpacity(0.3),
                            ),
                          ),
                          child: Text(
                            emoji,
                            style: const TextStyle(fontSize: 20),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ],

                // Recipe mode indicator
                if (message.messageType == 'recipe_mode') ...[
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.green.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.green.withOpacity(0.3)),
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
                      final match = RegExp(
                        r'(\d+) / 100',
                      ).firstMatch(message.text);
                      if (match != null) {
                        return (int.tryParse(match.group(1) ?? '0') ?? 0) /
                            100.0;
                      }
                      return 0.0;
                    }(),
                    backgroundColor: Theme.of(
                      context,
                    ).colorScheme.primary.withOpacity(0.15),
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
                    color:
                        (message.isUser
                                ? Theme.of(
                                    context,
                                  ).colorScheme.onPrimaryContainer
                                : Theme.of(context).colorScheme.onSurface)
                            .withOpacity(0.6),
                  ),
                ),
              ],
            ),
          ),
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
              ).withOpacity(0.1),
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
        color: Theme.of(context).colorScheme.primaryContainer.withOpacity(0.3),
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
              Text(
                'Today\'s Progress',
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
              ),
            ],
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
              color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'No goals set - tap the trophy icon to get started',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(
                    context,
                  ).colorScheme.onSurface.withOpacity(0.5),
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
                backgroundColor: challenge.color.withOpacity(0.15),
                side: BorderSide(
                  color: challenge.color.withOpacity(0.3),
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
    final prompts = [
      ('🥣', 'What should I eat now?'),
      ('💳', 'Check my cheat credits'),
      ('🍳', 'Healthify a recipe'),
      ('📊', 'How are my macros?'),
      ('💧', 'Hydration tips'),
    ];
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 2),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: prompts.map((p) {
            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ActionChip(
                avatar: Text(p.$1),
                label: Text(p.$2, style: const TextStyle(fontSize: 12)),
                onPressed: () {
                  _messageController.text = p.$2;
                  _sendTextMessage();
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
                backgroundColor: color.withOpacity(0.2),
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
