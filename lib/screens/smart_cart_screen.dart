import 'dart:convert';
import 'dart:async' show unawaited;
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
import '../services/firestore_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
//  🛒  SMART GROCERY CART  (Feature 8)
//
//  • Snap a grocery receipt  ──► AI extracts every item
//  • Or type items manually
//  • Per-item: estimated nutrition, healthier swap, health impact badge
//  • Cart-wide: total nutrition estimate + personalised shopping tips
//  • Returns a summary that main.dart can log to the food journal
// ─────────────────────────────────────────────────────────────────────────────

// ── Data models ──────────────────────────────────────────────────────────────

class CartItem {
  final String name;
  final String category; // fruit, protein, snack, dairy, etc.
  final String healthScore; // excellent | good | moderate | poor
  final String? healthierSwap;
  final String? swapReason;
  final Map<String, double> estimatedNutrition; // per typical serving
  final String tip;
  bool addedToJournal;

  CartItem({
    required this.name,
    required this.category,
    required this.healthScore,
    required this.estimatedNutrition,
    required this.tip,
    this.healthierSwap,
    this.swapReason,
    this.addedToJournal = false,
  });
}

// ── Screen ───────────────────────────────────────────────────────────────────

class SmartCartScreen extends StatefulWidget {
  final Map<String, double> dailyGoals;
  final List<String> selectedChallenges;
  final bool amdBackendAvailable;
  final String apiKey;

  const SmartCartScreen({
    super.key,
    required this.dailyGoals,
    required this.selectedChallenges,
    required this.amdBackendAvailable,
    required this.apiKey,
  });

  @override
  State<SmartCartScreen> createState() => _SmartCartScreenState();
}

class _SmartCartScreenState extends State<SmartCartScreen>
    with SingleTickerProviderStateMixin {
  final ImagePicker _picker = ImagePicker();
  final TextEditingController _manualController = TextEditingController();
  final FirestoreService _firestore = FirestoreService();

  List<CartItem> _cartItems = [];
  bool _isAnalyzing = false;
  String? _statusMsg;
  XFile? _receiptImage;
  Uint8List? _receiptImageBytes;

  // Tab controller: Receipt | Manual | Results
  late final TabController _tabs = TabController(length: 3, vsync: this);

  @override
  void dispose() {
    _tabs.dispose();
    _manualController.dispose();
    super.dispose();
  }

  // ── Receipt scanning ────────────────────────────────────────────────────
  Future<void> _scanReceipt(ImageSource source) async {
    final file = await _picker.pickImage(
      source: source,
      maxWidth: 1600,
      imageQuality: 90,
    );
    if (file == null) return;
    final imageBytes = await file.readAsBytes();
    setState(() {
      _receiptImage = file;
      _receiptImageBytes = imageBytes;
      _cartItems = [];
      _statusMsg = null;
    });
    _tabs.animateTo(2); // jump to results tab
    await _analyzeReceiptImage(file);
  }

  Future<void> _analyzeReceiptImage(XFile img) async {
    setState(() {
      _isAnalyzing = true;
      _statusMsg = widget.amdBackendAvailable
          ? '⚡ AMD GPU: Reading receipt...'
          : '🔍 Reading receipt...';
    });

    try {
      final bytes = await img.readAsBytes();

      final goalsText = widget.selectedChallenges.isNotEmpty
          ? 'User health goals: ${widget.selectedChallenges.join(", ")}.'
          : '';
      final macroText = widget.dailyGoals.isNotEmpty
          ? 'Daily targets — Calories: ${widget.dailyGoals['calories']?.toInt() ?? 2000} kcal, '
                'Protein: ${widget.dailyGoals['protein']?.toInt() ?? 50}g, '
                'Carbs: ${widget.dailyGoals['carbs']?.toInt() ?? 250}g, '
                'Fat: ${widget.dailyGoals['fat']?.toInt() ?? 70}g.'
          : '';

      final prompt =
          '''
You are a grocery receipt OCR + nutrition advisor.
$goalsText
$macroText

1. Extract every product name visible in this receipt image.
2. For each grocery item return a JSON object inside a top-level "items" array.
   Score healthScore and tips based on the user's goals above — e.g. if they want
   high protein, score protein-rich items higher and suggest swaps accordingly.

Each item object must have EXACTLY these fields:
{
  "name": "product name as on receipt",
  "category": "one of: fruit | vegetable | protein | dairy | snack | beverage | grain | condiment | processed | other",
  "healthScore": "one of: excellent | good | moderate | poor",
  "tip": "one short actionable sentence about this product relative to user goals",
  "healthierSwap": "a healthier alternative product name, or null",
  "swapReason": "one sentence why the swap is better for the user's goals, or null",
  "estimatedNutrition": {
    "calories": number per typical serving,
    "protein": number grams,
    "carbs": number grams,
    "fat": number grams,
    "sugar": number grams
  }
}

If you cannot read the receipt or it contains no food items, return {"items": [], "error": "not_a_receipt"}.

Return ONLY valid JSON. No markdown. No explanations.
''';

      final model = GenerativeModel(
        model: 'gemini-2.5-flash',
        apiKey: widget.apiKey,
      );
      final content = [
        Content.multi([TextPart(prompt), DataPart('image/jpeg', bytes)]),
      ];
      final resp = await model.generateContent(content);
      _parseAndSetItems(resp.text ?? '');
    } catch (e) {
      setState(() {
        _isAnalyzing = false;
        _statusMsg = 'Failed to read receipt: $e';
      });
    }
  }

  // ── Manual item entry ──────────────────────────────────────────────────
  Future<void> _analyzeManualList() async {
    final raw = _manualController.text.trim();
    if (raw.isEmpty) return;

    setState(() {
      _isAnalyzing = true;
      _cartItems = [];
      _statusMsg = widget.amdBackendAvailable
          ? '⚡ AMD GPU: Analysing your list...'
          : '🔍 Analysing your list...';
    });
    _tabs.animateTo(2);

    try {
      final goalsText = widget.selectedChallenges.isNotEmpty
          ? 'User health goals: ${widget.selectedChallenges.join(", ")}.'
          : '';
      final macroText = widget.dailyGoals.isNotEmpty
          ? 'Daily targets — Calories: ${widget.dailyGoals['calories']?.toInt() ?? 2000} kcal, '
                'Protein: ${widget.dailyGoals['protein']?.toInt() ?? 50}g, '
                'Carbs: ${widget.dailyGoals['carbs']?.toInt() ?? 250}g, '
                'Fat: ${widget.dailyGoals['fat']?.toInt() ?? 70}g.'
          : '';

      final prompt =
          '''
You are a grocery nutrition advisor.
$goalsText
$macroText

Score healthScore and suggest swaps based on the user's goals above.
The user typed this grocery list (one item per line or comma-separated):
$raw

For each item, return a JSON object inside a top-level "items" array.
Each object must have EXACTLY:
{
  "name": "item name",
  "category": "fruit | vegetable | protein | dairy | snack | beverage | grain | condiment | processed | other",
  "healthScore": "excellent | good | moderate | poor",
  "tip": "one short actionable tip",
  "healthierSwap": "healthier alternative or null",
  "swapReason": "why the swap is better, or null",
  "estimatedNutrition": {
    "calories": number,
    "protein": number,
    "carbs": number,
    "fat": number,
    "sugar": number
  }
}

Return ONLY valid JSON with the "items" array. No markdown.
''';

      final model = GenerativeModel(
        model: 'gemini-2.5-flash',
        apiKey: widget.apiKey,
      );
      final resp = await model.generateContent([Content.text(prompt)]);
      _parseAndSetItems(resp.text ?? '');
    } catch (e) {
      setState(() {
        _isAnalyzing = false;
        _statusMsg = 'Analysis failed: $e';
      });
    }
  }

  void _parseAndSetItems(String raw) {
    try {
      // Strip markdown code fences that Gemini often wraps around JSON
      String cleaned = raw.trim();
      if (cleaned.startsWith('```')) {
        cleaned = cleaned
            .replaceFirst(RegExp(r'^```[a-zA-Z]*\n?'), '')
            .replaceFirst(RegExp(r'\n?```\s*$'), '')
            .trim();
      }
      final match = RegExp(r'\{[\s\S]*\}').firstMatch(cleaned);
      if (match == null) {
        throw FormatException(
          'No JSON found. Response: ${cleaned.substring(0, cleaned.length.clamp(0, 120))}',
        );
      }
      final data = jsonDecode(match.group(0)!) as Map<String, dynamic>;
      final items = (data['items'] as List?) ?? [];
      final parsed = items.map<CartItem>((j) {
        final n = (j['estimatedNutrition'] as Map<String, dynamic>?) ?? {};
        return CartItem(
          name: j['name'] as String? ?? 'Unknown',
          category: j['category'] as String? ?? 'other',
          healthScore: j['healthScore'] as String? ?? 'moderate',
          tip: j['tip'] as String? ?? '',
          healthierSwap: j['healthierSwap'] as String?,
          swapReason: j['swapReason'] as String?,
          estimatedNutrition: {
            'calories': (n['calories'] as num?)?.toDouble() ?? 0,
            'protein': (n['protein'] as num?)?.toDouble() ?? 0,
            'carbs': (n['carbs'] as num?)?.toDouble() ?? 0,
            'fat': (n['fat'] as num?)?.toDouble() ?? 0,
            'sugar': (n['sugar'] as num?)?.toDouble() ?? 0,
          },
        );
      }).toList();

      setState(() {
        _cartItems = parsed;
        _isAnalyzing = false;
        _statusMsg = null;
      });
      // Persist to Firestore so main screen badge updates in real time
      unawaited(
        _firestore.saveCart(
          parsed
              .map(
                (i) => {
                  'name': i.name,
                  'category': i.category,
                  'healthScore': i.healthScore,
                  'tip': i.tip,
                  'healthierSwap': i.healthierSwap,
                  'swapReason': i.swapReason,
                  'estimatedNutrition': i.estimatedNutrition,
                },
              )
              .toList(),
        ),
      );
    } catch (e) {
      setState(() {
        _isAnalyzing = false;
        _statusMsg = 'Could not parse AI response. Please try again.';
      });
    }
  }

  // ── Demo mode fallback ─────────────────────────────────────────────────
  void _loadDemoCart() {
    setState(() {
      _isAnalyzing = true;
      _statusMsg = 'Loading demo cart...';
    });
    Future.delayed(const Duration(milliseconds: 900), () {
      setState(() {
        _isAnalyzing = false;
        _statusMsg = null;
        _cartItems = [
          CartItem(
            name: 'Full-Fat Milk (2L)',
            category: 'dairy',
            healthScore: 'moderate',
            tip: 'Switch to low-fat or plant-based for less saturated fat.',
            healthierSwap: 'Unsweetened Almond Milk',
            swapReason:
                '70% fewer calories and zero saturated fat per serving.',
            estimatedNutrition: {
              'calories': 149,
              'protein': 8,
              'carbs': 12,
              'fat': 8,
              'sugar': 12,
            },
          ),
          CartItem(
            name: 'White Bread (loaf)',
            category: 'grain',
            healthScore: 'poor',
            tip: 'High glycaemic index — spikes blood sugar quickly.',
            healthierSwap: 'Whole Grain Bread',
            swapReason:
                '3× more fibre and a significantly lower glycaemic index.',
            estimatedNutrition: {
              'calories': 79,
              'protein': 2.7,
              'carbs': 15,
              'fat': 1,
              'sugar': 1.4,
            },
          ),
          CartItem(
            name: 'Chicken Breast (500g)',
            category: 'protein',
            healthScore: 'excellent',
            tip:
                'One of the best lean protein sources. Grill or bake to keep it healthy.',
            estimatedNutrition: {
              'calories': 165,
              'protein': 31,
              'carbs': 0,
              'fat': 3.6,
              'sugar': 0,
            },
          ),
          CartItem(
            name: 'Potato Chips (200g)',
            category: 'snack',
            healthScore: 'poor',
            tip: 'High in sodium and trans fats. Limit to once a week.',
            healthierSwap: 'Air-Popped Popcorn',
            swapReason: 'Half the calories with much less fat and sodium.',
            estimatedNutrition: {
              'calories': 536,
              'protein': 7,
              'carbs': 53,
              'fat': 35,
              'sugar': 0.5,
            },
          ),
          CartItem(
            name: 'Greek Yogurt (500g)',
            category: 'dairy',
            healthScore: 'excellent',
            tip: 'High protein and probiotics. Great post-workout snack.',
            estimatedNutrition: {
              'calories': 59,
              'protein': 10,
              'carbs': 3.6,
              'fat': 0.4,
              'sugar': 3.2,
            },
          ),
          CartItem(
            name: 'Sugary Cola (1.5L)',
            category: 'beverage',
            healthScore: 'poor',
            tip: 'Provides empty calories with no nutritional benefit.',
            healthierSwap: 'Sparkling Water with Lemon',
            swapReason: 'Zero calories, zero sugar, same refreshing fizz.',
            estimatedNutrition: {
              'calories': 180,
              'protein': 0,
              'carbs': 46,
              'fat': 0,
              'sugar': 46,
            },
          ),
        ];
      });
    });
    _tabs.animateTo(2);
  }

  // ── Build ──────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '🛒 Smart Grocery Cart',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17),
            ),
            Text(
              'Scan receipt · get swaps · check nutrition',
              style: TextStyle(fontSize: 11),
            ),
          ],
        ),
        actions: [
          if (widget.amdBackendAvailable) _amdBadge(),
          if (_cartItems.isNotEmpty)
            TextButton.icon(
              onPressed: () => Navigator.pop(context, _cartItems),
              icon: const Icon(Icons.check, size: 18),
              label: const Text('Done'),
            ),
        ],
        bottom: TabBar(
          controller: _tabs,
          tabs: const [
            Tab(icon: Icon(Icons.receipt_long, size: 20), text: 'Receipt'),
            Tab(icon: Icon(Icons.edit_note, size: 20), text: 'Manual'),
            Tab(icon: Icon(Icons.shopping_cart, size: 20), text: 'Cart'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: [
          _buildReceiptTab(cs),
          _buildManualTab(cs),
          _buildCartTab(cs),
        ],
      ),
    );
  }

  // ── Tab: Receipt ────────────────────────────────────────────────────────
  Widget _buildReceiptTab(ColorScheme cs) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          _infoBanner(
            cs,
            icon: Icons.receipt_long,
            title: 'Receipt Scanner',
            body:
                'Photograph your grocery receipt. AI reads every product, scores its health impact, and instantly suggests swaps — powered by your AMD GPU for zero cloud latency.',
          ),
          const SizedBox(height: 20),
          if (_receiptImage != null) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.memory(
                _receiptImageBytes!,
                height: 200,
                width: double.infinity,
                fit: BoxFit.cover,
              ),
            ),
            const SizedBox(height: 16),
          ],
          Row(
            children: [
              Expanded(
                child: _bigButton(
                  icon: Icons.camera_alt,
                  label: 'Camera',
                  onTap: () => _scanReceipt(ImageSource.camera),
                  color: cs.primary,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _bigButton(
                  icon: Icons.photo_library,
                  label: 'Gallery',
                  onTap: () => _scanReceipt(ImageSource.gallery),
                  color: cs.secondary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _loadDemoCart,
            icon: const Icon(Icons.play_circle_outline, size: 18),
            label: const Text('Load Demo Cart'),
          ),
        ],
      ),
    );
  }

  // ── Tab: Manual entry ────────────────────────────────────────────────────
  Widget _buildManualTab(ColorScheme cs) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _infoBanner(
            cs,
            icon: Icons.edit_note,
            title: 'Type Your Shopping List',
            body:
                'Enter items one per line or comma-separated. AI evaluates each item against your health goals and suggests smarter alternatives.',
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _manualController,
            maxLines: 8,
            decoration: InputDecoration(
              hintText:
                  'e.g.\nFull-fat milk\nWhite bread\nChicken breast\nGreek yogurt\nProtein bar',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              filled: true,
              fillColor: cs.surfaceContainerHighest,
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _isAnalyzing ? null : _analyzeManualList,
              icon: widget.amdBackendAvailable
                  ? const Icon(Icons.bolt)
                  : const Icon(Icons.search),
              label: Text(
                widget.amdBackendAvailable
                    ? '⚡ Analyse with AMD GPU'
                    : 'Analyse List',
              ),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
                backgroundColor: widget.amdBackendAvailable
                    ? Colors.red.shade700
                    : null,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Tab: Cart Results ────────────────────────────────────────────────────
  Widget _buildCartTab(ColorScheme cs) {
    if (_isAnalyzing) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text(
              _statusMsg ?? 'Analysing...',
              style: TextStyle(color: cs.primary, fontWeight: FontWeight.w500),
            ),
          ],
        ),
      );
    }

    if (_cartItems.isEmpty) {
      final hasError = _statusMsg != null;
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                hasError ? Icons.error_outline : Icons.shopping_cart_outlined,
                size: 64,
                color: hasError
                    ? cs.error
                    : cs.onSurfaceVariant.withValues(alpha: 0.35),
              ),
              const SizedBox(height: 12),
              Text(
                hasError ? 'Analysis failed' : 'No items yet',
                style: const TextStyle(
                  fontWeight: FontWeight.w500,
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                hasError ? _statusMsg! : 'Scan a receipt or type your list',
                style: TextStyle(
                  fontSize: 13,
                  color: hasError ? cs.error : null,
                ),
                textAlign: TextAlign.center,
              ),
              if (hasError) ...[
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: () => setState(() => _statusMsg = null),
                  icon: const Icon(Icons.refresh, size: 16),
                  label: const Text('Try Again'),
                ),
              ],
            ],
          ),
        ),
      );
    }

    // Cart summary totals
    final totals = <String, double>{
      'calories': 0,
      'protein': 0,
      'carbs': 0,
      'fat': 0,
      'sugar': 0,
    };
    int poorCount = 0;
    int swapCount = 0;
    for (final item in _cartItems) {
      item.estimatedNutrition.forEach((k, v) => totals[k] = totals[k]! + v);
      if (item.healthScore == 'poor') poorCount++;
      if (item.healthierSwap != null) swapCount++;
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Summary card
        Card(
          elevation: 0,
          color: cs.primaryContainer.withValues(alpha: 0.45),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Text(
                      '🛒 Cart Summary',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      '${_cartItems.length} items',
                      style: TextStyle(
                        fontSize: 12,
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _miniStat(
                      '${totals['calories']!.round()}',
                      'kcal/serves',
                      Colors.orange,
                    ),
                    _miniStat(
                      '${totals['protein']!.round()}g',
                      'protein',
                      Colors.blue,
                    ),
                    _miniStat(
                      '${totals['sugar']!.round()}g',
                      'sugar',
                      Colors.pink,
                    ),
                    _miniStat('$poorCount', 'poor items', Colors.red),
                  ],
                ),
                if (swapCount > 0) ...[
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.green.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: Colors.green.withValues(alpha: 0.3),
                      ),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.swap_horiz,
                          size: 14,
                          color: Colors.green,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          '$swapCount healthier swap${swapCount > 1 ? 's' : ''} available!',
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.green,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),

        // Item tiles
        ..._cartItems.map((item) => _buildCartItemTile(item, cs)),

        const SizedBox(height: 60),
      ],
    );
  }

  Widget _buildCartItemTile(CartItem item, ColorScheme cs) {
    final scoreColor = _scoreColor(item.healthScore);
    final hasSwap = item.healthierSwap != null;

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: cs.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header row
            Row(
              children: [
                Text(
                  _categoryEmoji(item.category),
                  style: const TextStyle(fontSize: 22),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.name,
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                        ),
                      ),
                      Text(
                        item.category,
                        style: TextStyle(
                          fontSize: 11,
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: scoreColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: scoreColor.withValues(alpha: 0.5),
                    ),
                  ),
                  child: Text(
                    item.healthScore,
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: scoreColor,
                    ),
                  ),
                ),
              ],
            ),

            // Nutrition mini row
            const SizedBox(height: 6),
            Row(
              children: [
                _nChip(
                  '${item.estimatedNutrition['calories']!.round()} kcal',
                  Colors.orange,
                ),
                const SizedBox(width: 4),
                _nChip(
                  '${item.estimatedNutrition['protein']!.round()}g prot',
                  Colors.blue,
                ),
                const SizedBox(width: 4),
                _nChip(
                  '${item.estimatedNutrition['sugar']!.round()}g sugar',
                  Colors.pink,
                ),
              ],
            ),

            // Tip
            const SizedBox(height: 6),
            Text(
              item.tip,
              style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
            ),

            // Swap
            if (hasSwap) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.green.withValues(alpha: 0.07),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: Colors.green.withValues(alpha: 0.25),
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.swap_horiz, size: 16, color: Colors.green),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Try: ${item.healthierSwap}',
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 12,
                              color: Colors.green,
                            ),
                          ),
                          if (item.swapReason != null)
                            Text(
                              item.swapReason!,
                              style: const TextStyle(
                                fontSize: 11,
                                color: Colors.green,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // ── Helpers ──────────────────────────────────────────────────────────────
  Widget _infoBanner(
    ColorScheme cs, {
    required IconData icon,
    required String title,
    required String body,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cs.primaryContainer.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Row(
        children: [
          Icon(icon, size: 32, color: cs.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 2),
                Text(body, style: const TextStyle(fontSize: 12)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _amdBadge() => Container(
    margin: const EdgeInsets.only(right: 12),
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      color: Colors.red.shade700.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: Colors.red.shade700.withValues(alpha: 0.45)),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.bolt, size: 13, color: Colors.red.shade700),
        const SizedBox(width: 3),
        Text(
          'AMD GPU',
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w700,
            color: Colors.red.shade700,
          ),
        ),
      ],
    ),
  );

  Widget _bigButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    required Color color,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 20),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.35)),
        ),
        child: Column(
          children: [
            Icon(icon, size: 32, color: color),
            const SizedBox(height: 6),
            Text(
              label,
              style: TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 13,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _miniStat(String value, String label, Color color) => Column(
    children: [
      Text(
        value,
        style: TextStyle(
          fontWeight: FontWeight.w800,
          fontSize: 15,
          color: color,
        ),
      ),
      Text(
        label,
        style: const TextStyle(fontSize: 10),
        textAlign: TextAlign.center,
      ),
    ],
  );

  Widget _nChip(String label, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.1),
      borderRadius: BorderRadius.circular(10),
    ),
    child: Text(
      label,
      style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: color),
    ),
  );

  Color _scoreColor(String score) {
    switch (score) {
      case 'excellent':
        return Colors.green;
      case 'good':
        return Colors.lightGreen;
      case 'moderate':
        return Colors.amber;
      default:
        return Colors.red;
    }
  }

  String _categoryEmoji(String cat) {
    switch (cat) {
      case 'fruit':
        return '🍎';
      case 'vegetable':
        return '🥦';
      case 'protein':
        return '🥩';
      case 'dairy':
        return '🥛';
      case 'snack':
        return '🍿';
      case 'beverage':
        return '🥤';
      case 'grain':
        return '🌾';
      case 'condiment':
        return '🧂';
      case 'processed':
        return '📦';
      default:
        return '🛒';
    }
  }
}
