import 'package:flutter/material.dart';
import 'main.dart';

class ChallengesScreen extends StatefulWidget {
  final List<String> initialSelected;

  const ChallengesScreen({super.key, required this.initialSelected});

  @override
  State<ChallengesScreen> createState() => _ChallengesScreenState();
}

class _ChallengesScreenState extends State<ChallengesScreen> {
  late List<String> _selectedChallengeIds;

  @override
  void initState() {
    super.initState();
    _selectedChallengeIds = List.from(widget.initialSelected);
  }

  void _toggleChallenge(String challengeId) {
    setState(() {
      if (_selectedChallengeIds.contains(challengeId)) {
        _selectedChallengeIds.remove(challengeId);
      } else {
        _selectedChallengeIds.add(challengeId);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Your Health Goals'), elevation: 0),
      body: Column(
        children: [
          // Header section
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            color: colorScheme.primaryContainer.withOpacity(0.3),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Select Your Challenges',
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Choose one or more goals to help me provide personalized nutrition advice tailored to your needs.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: colorScheme.onSurface.withOpacity(0.7),
                  ),
                ),
              ],
            ),
          ),

          // Challenges grid
          Expanded(
            child: GridView.builder(
              padding: const EdgeInsets.all(16),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                childAspectRatio: 0.85,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
              ),
              itemCount: availableChallenges.length,
              itemBuilder: (context, index) {
                final challenge = availableChallenges[index];
                final isSelected = _selectedChallengeIds.contains(challenge.id);

                return GestureDetector(
                  onTap: () => _toggleChallenge(challenge.id),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? challenge.color.withOpacity(0.15)
                          : colorScheme.surfaceContainerHighest.withOpacity(
                              0.5,
                            ),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: isSelected
                            ? challenge.color
                            : colorScheme.outline.withOpacity(0.3),
                        width: isSelected ? 2.5 : 1,
                      ),
                    ),
                    child: Stack(
                      children: [
                        // Main content
                        Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Icon
                              Container(
                                width: 50,
                                height: 50,
                                decoration: BoxDecoration(
                                  color: challenge.color.withOpacity(0.2),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Center(
                                  child: Text(
                                    challenge.icon,
                                    style: const TextStyle(fontSize: 28),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 12),
                              // Name
                              Text(
                                challenge.name,
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.bold,
                                  color: isSelected
                                      ? challenge.color.withOpacity(0.9)
                                      : colorScheme.onSurface,
                                ),
                              ),
                              const SizedBox(height: 6),
                              // Description
                              Expanded(
                                child: Text(
                                  challenge.description,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: colorScheme.onSurface.withOpacity(
                                      0.6,
                                    ),
                                    height: 1.3,
                                  ),
                                  maxLines: 3,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ),
                        // Checkmark badge
                        if (isSelected)
                          Positioned(
                            top: 8,
                            right: 8,
                            child: Container(
                              width: 28,
                              height: 28,
                              decoration: BoxDecoration(
                                color: challenge.color,
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.check,
                                color: Colors.white,
                                size: 18,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),

          // Bottom action bar
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: colorScheme.surface,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 10,
                  offset: const Offset(0, -2),
                ),
              ],
            ),
            child: SafeArea(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Selected count indicator
                  if (_selectedChallengeIds.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Text(
                        '${_selectedChallengeIds.length} ${_selectedChallengeIds.length == 1 ? 'goal' : 'goals'} selected',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: colorScheme.primary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  // Save button
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: FilledButton.icon(
                      onPressed: () {
                        Navigator.pop(context, _selectedChallengeIds);
                      },
                      icon: const Icon(Icons.check_circle),
                      label: const Text('Save Goals'),
                      style: FilledButton.styleFrom(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
