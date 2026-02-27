import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import 'health_profile_screen.dart';

class SignInScreen extends StatefulWidget {
  const SignInScreen({super.key});

  @override
  State<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends State<SignInScreen> {
  final AuthService _authService = AuthService();
  bool _isLoading = false;
  bool _isAnonymousLoading = false;

  Future<void> _handleGoogleSignIn() async {
    setState(() {
      _isLoading = true;
    });

    try {
      debugPrint('Starting Google Sign-In...');
      final userCredential = await _authService.signInWithGoogle();
      if (userCredential != null && mounted) {
        debugPrint('Google Sign-In successful: ${userCredential.user?.email}');
        // Navigation handled by auth state listener in main.dart
      } else {
        debugPrint('Google Sign-In cancelled by user');
      }
    } catch (e) {
      debugPrint('Google Sign-In error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Sign in failed: ${e.toString()}'),
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

  Future<void> _handleAnonymousSignIn() async {
    setState(() {
      _isAnonymousLoading = true;
    });

    try {
      debugPrint('Starting Anonymous Sign-In...');
      final result = await _authService.signInAnonymously();
      debugPrint('Anonymous Sign-In successful: ${result.user?.uid}');
      // Navigation handled by auth state listener in main.dart
    } catch (e) {
      debugPrint('Anonymous Sign-In error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Anonymous sign in failed: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isAnonymousLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 20),

              // App Logo/Icon
              Icon(Icons.restaurant_menu, size: 80, color: colorScheme.primary),
              const SizedBox(height: 16),

              // App Name
              Text(
                '🥗 NutriBuddy',
                textAlign: TextAlign.center,
                style: theme.textTheme.displaySmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: colorScheme.primary,
                ),
              ),
              const SizedBox(height: 8),

              // Tagline
              Text(
                'Your AI-powered nutrition companion',
                textAlign: TextAlign.center,
                style: theme.textTheme.titleMedium?.copyWith(
                  color: colorScheme.onSurface.withValues(alpha: 0.7),
                ),
              ),
              const SizedBox(height: 32),

              // Features List
              _buildFeatureItem(
                Icons.camera_alt,
                'Scan food products instantly',
                colorScheme,
              ),
              const SizedBox(height: 12),
              _buildFeatureItem(
                Icons.analytics,
                'Get AI-powered nutrition analysis',
                colorScheme,
              ),
              const SizedBox(height: 12),
              _buildFeatureItem(
                Icons.emoji_events,
                'Track your health goals',
                colorScheme,
              ),
              const SizedBox(height: 12),
              _buildFeatureItem(
                Icons.cloud_sync,
                'Sync across all your devices',
                colorScheme,
              ),
              const SizedBox(height: 32),

              // Create Account Button
              SizedBox(
                height: 56,
                child: ElevatedButton.icon(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) =>
                            const HealthProfileScreen(showBackButton: true),
                      ),
                    );
                  },
                  icon: const Icon(Icons.person_add, size: 24),
                  label: const Text(
                    'Create Account',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: colorScheme.primary,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Divider with OR
              Row(
                children: [
                  Expanded(child: Divider(color: colorScheme.outline)),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Text(
                      'OR',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurface.withValues(alpha: 0.5),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Expanded(child: Divider(color: colorScheme.outline)),
                ],
              ),
              const SizedBox(height: 16),

              // Sign In Label
              Text(
                'Already have an account?',
                textAlign: TextAlign.center,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: 12),

              // Google Sign In Button
              SizedBox(
                height: 56,
                child: ElevatedButton.icon(
                  onPressed: _isLoading ? null : _handleGoogleSignIn,
                  icon: _isLoading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              Colors.white,
                            ),
                          ),
                        )
                      : Image.asset(
                          'assets/google_logo.png',
                          height: 24,
                          errorBuilder: (context, error, stackTrace) =>
                              const Icon(Icons.login, color: Colors.white),
                        ),
                  label: Text(
                    _isLoading ? 'Signing in...' : 'Sign in with Google',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: colorScheme.primary,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),

              // Helper text
              Text(
                'Sign in with your existing Google account',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurface.withValues(alpha: 0.6),
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 12),

              // Divider with OR
              Row(
                children: [
                  Expanded(child: Divider(color: colorScheme.outline)),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Text(
                      'OR',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurface.withValues(alpha: 0.5),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Expanded(child: Divider(color: colorScheme.outline)),
                ],
              ),
              const SizedBox(height: 12),

              // Anonymous Sign In Button
              SizedBox(
                height: 56,
                child: OutlinedButton.icon(
                  onPressed: _isAnonymousLoading
                      ? null
                      : _handleAnonymousSignIn,
                  icon: _isAnonymousLoading
                      ? SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              colorScheme.primary,
                            ),
                          ),
                        )
                      : const Icon(Icons.person_outline),
                  label: Text(
                    _isAnonymousLoading ? 'Starting...' : 'Try as Guest',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: colorScheme.primary,
                    side: BorderSide(
                      color: colorScheme.outline.withValues(alpha: 0.5),
                      width: 1.5,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 6),

              // Guest mode explanation
              Text(
                'No account needed • Upgrade to save data anytime',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurface.withValues(alpha: 0.5),
                  fontSize: 11,
                ),
              ),
              const SizedBox(height: 16),

              // Privacy Notice
              Text(
                'By continuing, you agree to our Terms of Service and Privacy Policy',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurface.withValues(alpha: 0.5),
                ),
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFeatureItem(
    IconData icon,
    String text,
    ColorScheme colorScheme,
  ) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: colorScheme.primaryContainer,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, size: 20, color: colorScheme.primary),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              fontSize: 15,
              color: colorScheme.onSurface.withValues(alpha: 0.8),
            ),
          ),
        ),
      ],
    );
  }
}
