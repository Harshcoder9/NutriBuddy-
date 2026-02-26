import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import '../services/firestore_service.dart';
import '../services/nutrition_calculator.dart';
import '../main.dart';
import 'health_profile_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final AuthService _authService = AuthService();
  final FirestoreService _firestoreService = FirestoreService();
  bool _isLoading = false;
  HealthProfile? _healthProfile;

  @override
  void initState() {
    super.initState();
    _loadHealthProfile();
  }

  Future<void> _loadHealthProfile() async {
    final profile = await _firestoreService.getHealthProfile();
    if (mounted) {
      setState(() {
        _healthProfile = profile;
      });
    }
  }

  Future<void> _editHealthProfile() async {
    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (context) => HealthProfileScreen(
          isEditing: true,
          existingProfile: _healthProfile,
        ),
      ),
    );

    if (result == true) {
      // Reload profile after editing
      await _loadHealthProfile();

      // Recalculate daily goals
      if (_healthProfile != null && mounted) {
        final challenges = await _firestoreService.getUserChallenges();
        final calculatedCalories = NutritionCalculator.calculateDailyCalories(
          _healthProfile!,
          challenges,
        );
        final macros = NutritionCalculator.getRecommendedMacros(
          calculatedCalories,
          challenges: challenges,
        );
        await _firestoreService.saveDailyGoals(macros);

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Profile updated! Daily goals recalculated: ${calculatedCalories.round()} cal',
              ),
              backgroundColor: const Color(0xFF1565C0),
            ),
          );
        }
      }
    }
  }

  Future<void> _handleSignOut() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Sign Out'),
        content: const Text('Are you sure you want to sign out?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Sign Out'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      setState(() {
        _isLoading = true;
      });

      try {
        // Sign out first
        await _authService.signOut();
        
        // Wait a moment for Firebase to process the sign-out
        await Future.delayed(const Duration(milliseconds: 100));
        
        // Navigate back to root and force rebuild
        if (mounted) {
          Navigator.of(context, rootNavigator: true).pushAndRemoveUntil(
            MaterialPageRoute(builder: (context) => const AuthGate()),
            (route) => false,
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error signing out: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      } finally {
        if (mounted) {
          setState(() {
            _isLoading = false;
          });
        }
      }
    }
  }

  Future<void> _handleUpgradeAccount() async {
    setState(() {
      _isLoading = true;
    });

    try {
      await _authService.upgradeAnonymousWithGoogle();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Account upgraded successfully! Your data is now backed up.',
            ),
            backgroundColor: Color(0xFF1565C0),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error upgrading account: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _handleDeleteAccount() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Account'),
        content: const Text(
          'Are you sure you want to delete your account? This action cannot be undone and all your data will be permanently deleted.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      setState(() {
        _isLoading = true;
      });

      try {
        // Delete account first
        await _authService.deleteAccount();
        
        // Wait a moment for Firebase to process
        await Future.delayed(const Duration(milliseconds: 100));

        // Navigate back to root and force rebuild
        if (mounted) {
          // Show success message
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Account deleted successfully'),
              backgroundColor: Color(0xFF1565C0),
              duration: Duration(seconds: 2),
            ),
          );
          // Navigate back to root
          Navigator.of(context, rootNavigator: true).pushAndRemoveUntil(
            MaterialPageRoute(builder: (context) => const AuthGate()),
            (route) => false,
          );
        }
      } catch (e) {
        print('Delete account error: $e');
        if (mounted) {
          setState(() {
            _isLoading = false;
          });

          // Extract meaningful error message
          String errorMessage = e.toString();
          if (errorMessage.contains('sign in again')) {
            errorMessage =
                'For security, please sign out, sign back in, and try again';
          } else if (errorMessage.contains('cancelled')) {
            errorMessage = 'Deletion cancelled';
          } else if (errorMessage.contains('requires-recent-login')) {
            errorMessage = 'Please sign out, sign back in, and try again';
          } else {
            // Show a user-friendly message
            errorMessage = 'Unable to delete account. Please try again.';
          }

          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(errorMessage),
              backgroundColor: Colors.red,
              duration: const Duration(seconds: 5),
              action: SnackBarAction(
                label: 'OK',
                textColor: Colors.white,
                onPressed: () {},
              ),
            ),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final user = _authService.currentUser;

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // User Profile Section
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        CircleAvatar(
                          radius: 40,
                          backgroundColor: colorScheme.primaryContainer,
                          backgroundImage: user?.photoURL != null
                              ? NetworkImage(user!.photoURL!)
                              : null,
                          child: user?.photoURL == null
                              ? Icon(
                                  Icons.person,
                                  size: 40,
                                  color: colorScheme.primary,
                                )
                              : null,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          user?.displayName ?? 'Guest User',
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        if (user?.email != null) ...[
                          const SizedBox(height: 4),
                          Text(
                            user!.email!,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: colorScheme.onSurface.withOpacity(0.6),
                            ),
                          ),
                        ],
                        if (user?.isAnonymous == true) ...[
                          const SizedBox(height: 8),
                          Chip(
                            label: const Text('Guest Account'),
                            backgroundColor: colorScheme.secondaryContainer,
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 24),

                // Health Profile Section
                Text(
                  'Health Profile',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 12),
                Card(
                  child: _healthProfile == null
                      ? ListTile(
                          leading: Icon(
                            Icons.favorite_border,
                            color: colorScheme.primary,
                          ),
                          title: const Text('Set Up Health Profile'),
                          subtitle: const Text(
                            'Add your health details for personalized recommendations',
                          ),
                          trailing: const Icon(
                            Icons.arrow_forward_ios,
                            size: 16,
                          ),
                          onTap: _editHealthProfile,
                        )
                      : Column(
                          children: [
                            ListTile(
                              leading: Icon(
                                Icons.favorite,
                                color: colorScheme.primary,
                              ),
                              title: const Text('Health Information'),
                              trailing: IconButton(
                                icon: const Icon(Icons.edit, size: 20),
                                onPressed: _editHealthProfile,
                              ),
                            ),
                            const Divider(height: 1),
                            Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                children: [
                                  _buildInfoRow(
                                    'Name',
                                    _healthProfile!.name,
                                    Icons.badge,
                                  ),
                                  const SizedBox(height: 8),
                                  _buildInfoRow(
                                    'Age',
                                    '${_healthProfile!.age} years',
                                    Icons.cake,
                                  ),
                                  const SizedBox(height: 8),
                                  _buildInfoRow(
                                    'Gender',
                                    _healthProfile!.gender,
                                    Icons.person,
                                  ),
                                  const SizedBox(height: 8),
                                  _buildInfoRow(
                                    'Height',
                                    '${_healthProfile!.height.toStringAsFixed(0)} cm',
                                    Icons.height,
                                  ),
                                  const SizedBox(height: 8),
                                  _buildInfoRow(
                                    'Weight',
                                    '${_healthProfile!.weight.toStringAsFixed(1)} kg',
                                    Icons.monitor_weight,
                                  ),
                                  const SizedBox(height: 8),
                                  _buildInfoRow(
                                    'Blood Group',
                                    _healthProfile!.bloodGroup,
                                    Icons.bloodtype,
                                  ),
                                  const SizedBox(height: 12),
                                  Container(
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: colorScheme.primaryContainer
                                          .withOpacity(0.3),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Row(
                                      children: [
                                        Icon(
                                          Icons.info_outline,
                                          size: 20,
                                          color: colorScheme.primary,
                                        ),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Text(
                                            'BMI: ${NutritionCalculator.calculateBMI(_healthProfile!).toStringAsFixed(1)} (${NutritionCalculator.getBMICategory(NutritionCalculator.calculateBMI(_healthProfile!))})',
                                            style: theme.textTheme.bodySmall,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                ),
                const SizedBox(height: 24),

                // Account Actions
                if (user?.isAnonymous == true) ...[
                  Text(
                    'Account',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Card(
                    child: ListTile(
                      leading: Icon(Icons.upgrade, color: colorScheme.primary),
                      title: const Text('Upgrade to Full Account'),
                      subtitle: const Text(
                        'Link with Google to backup your data',
                      ),
                      trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                      onTap: _handleUpgradeAccount,
                    ),
                  ),
                  const SizedBox(height: 24),
                ],

                // App Info
                Text(
                  'About',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 12),
                Card(
                  child: Column(
                    children: [
                      ListTile(
                        leading: Icon(
                          Icons.info_outline,
                          color: colorScheme.primary,
                        ),
                        title: const Text('Version'),
                        trailing: const Text('1.0.0'),
                      ),
                      const Divider(height: 1),
                      ListTile(
                        leading: Icon(
                          Icons.privacy_tip_outlined,
                          color: colorScheme.primary,
                        ),
                        title: const Text('Privacy Policy'),
                        trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                        onTap: () {
                          // TODO: Open privacy policy
                        },
                      ),
                      const Divider(height: 1),
                      ListTile(
                        leading: Icon(
                          Icons.description_outlined,
                          color: colorScheme.primary,
                        ),
                        title: const Text('Terms of Service'),
                        trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                        onTap: () {
                          // TODO: Open terms of service
                        },
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),

                // Danger Zone
                Text(
                  'Danger Zone',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: Colors.red,
                  ),
                ),
                const SizedBox(height: 12),
                Card(
                  child: Column(
                    children: [
                      ListTile(
                        leading: const Icon(Icons.logout, color: Colors.red),
                        title: const Text(
                          'Sign Out',
                          style: TextStyle(color: Colors.red),
                        ),
                        trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                        onTap: _handleSignOut,
                      ),
                      const Divider(height: 1),
                      ListTile(
                        leading: const Icon(
                          Icons.delete_forever,
                          color: Colors.red,
                        ),
                        title: const Text(
                          'Delete Account',
                          style: TextStyle(color: Colors.red),
                        ),
                        trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                        onTap: _handleDeleteAccount,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 32),
              ],
            ),
    );
  }

  Widget _buildInfoRow(String label, String value, IconData icon) {
    return Row(
      children: [
        Icon(icon, size: 20, color: Colors.grey[600]),
        const SizedBox(width: 12),
        Text(
          label,
          style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 14),
        ),
        const Spacer(),
        Text(value, style: const TextStyle(fontSize: 14, color: Colors.grey)),
      ],
    );
  }
}
