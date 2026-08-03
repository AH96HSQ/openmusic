import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import '../../services/auth_service.dart';
import '../../services/sync_service.dart';
import '../../services/status_message_controller.dart';
import '../pages/restore_confirmation_bottom_sheet.dart';

/// Check if running on desktop platform
bool get _isDesktopPlatform =>
    Platform.isWindows || Platform.isMacOS || Platform.isLinux;

enum AuthStep { emailInput, passwordLogin, otpVerify, passwordCreate, loggedIn }

class AuthWidget extends StatefulWidget {
  final VoidCallback? onLoginSuccess;

  const AuthWidget({super.key, this.onLoginSuccess});

  @override
  State<AuthWidget> createState() => _AuthWidgetState();
}

class _AuthWidgetState extends State<AuthWidget> {
  // Auth state
  AuthStep _authStep = AuthStep.emailInput;
  bool _authLoading = false;
  String? _authError;
  String _userEmail = '';
  Map<String, dynamic>? _currentUser;
  bool _isResettingPassword = false; // Track if we're in password reset flow

  // Controllers
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _otpController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadAuthState();
  }

  @override
  void dispose() {
    _emailController.dispose();
    _otpController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _loadAuthState() async {
    // Check if user is already logged in
    if (AuthService.instance.isLoggedIn) {
      setState(() {
        _currentUser = AuthService.instance.currentUser;
        _userEmail = _currentUser?['email'] ?? '';
        _authStep = AuthStep.loggedIn;
      });
    }
  }

  Future<void> _handleEmailSubmit() async {
    // Dismiss keyboard
    FocusScope.of(context).unfocus();

    final email = _emailController.text.trim();
    if (email.isEmpty) {
      setState(() => _authError = 'Please enter an email address');
      return;
    }

    // Check for Outlook emails
    if (email.toLowerCase().contains('@outlook') ||
        email.toLowerCase().contains('@hotmail') ||
        email.toLowerCase().contains('@live.')) {
      StatusMessageController.instance.showMessage(
        'Outlook emails are not supported. Please use a different email provider.',
        duration: const Duration(seconds: 4),
      );
      return;
    }

    setState(() {
      _authLoading = true;
      _authError = null;
      _userEmail = email;
    });

    try {
      final result = await AuthService.instance.checkEmail(email);

      if (!mounted) return;

      if (result['exists'] == true) {
        // Existing user - show password login
        setState(() {
          _authStep = AuthStep.passwordLogin;
          _authLoading = false;
        });
      } else {
        // New user - send OTP
        await AuthService.instance.requestOTP(email);

        if (!mounted) return;

        setState(() {
          _authStep = AuthStep.otpVerify;
          _authLoading = false;
        });

        // Check if email is Gmail
        final isGmail = email.toLowerCase().contains('@gmail');

        if (isGmail) {
          StatusMessageController.instance.showMessage(
            'Verification code sent! Check your inbox and junk folder.',
            duration: const Duration(seconds: 4),
          );
        } else {
          // Non-Gmail warning
          StatusMessageController.instance.showMessage(
            'Code sent! Check junk folder. Note: Non-Gmail emails may not receive it.',
            duration: const Duration(seconds: 5),
          );

          // Show additional warning after a delay
          Future.delayed(const Duration(seconds: 5), () {
            if (mounted) {
              StatusMessageController.instance.showMessage(
                'Warning: Emails other than Gmail might not receive the verification code.',
                duration: const Duration(seconds: 4),
              );
            }
          });
        }
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _authError = e.toString().replaceFirst('Exception: ', '');
        _authLoading = false;
      });
    }
  }

  Future<void> _handleLogin() async {
    // Dismiss keyboard
    FocusScope.of(context).unfocus();

    final password = _passwordController.text;
    if (password.isEmpty) {
      setState(() => _authError = 'Please enter your password');
      return;
    }

    setState(() {
      _authLoading = true;
      _authError = null;
    });

    try {
      final result = await AuthService.instance.login(_userEmail, password);

      if (!mounted) return;

      if (result['success'] == true) {
        setState(() {
          _currentUser = result['user'];
          _authStep = AuthStep.loggedIn;
          _authLoading = false;
        });

        // Sync is now event-based (on app background) - no timer needed

        StatusMessageController.instance.showMessage(
          'Welcome back!',
          duration: const Duration(seconds: 2),
        );

        // Notify parent of successful login
        widget.onLoginSuccess?.call();
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _authError = e.toString().replaceFirst('Exception: ', '');
        _authLoading = false;
      });
    }
  }

  Future<void> _handleOTPVerify() async {
    // Dismiss keyboard
    FocusScope.of(context).unfocus();

    final otp = _otpController.text.trim();
    if (otp.isEmpty) {
      setState(() => _authError = 'Please enter the verification code');
      return;
    }

    setState(() {
      _authLoading = true;
      _authError = null;
    });

    try {
      final result = await AuthService.instance.verifyOTP(_userEmail, otp);

      if (!mounted) return;

      if (result['verified'] == true) {
        setState(() {
          _authStep = AuthStep.passwordCreate;
          _authLoading = false;
        });

        StatusMessageController.instance.showMessage(
          _isResettingPassword
              ? 'Verified! Create your new password'
              : 'Email verified! Create your password',
          duration: const Duration(seconds: 2),
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _authError = e.toString().replaceFirst('Exception: ', '');
        _authLoading = false;
      });
    }
  }

  Future<void> _handleResetPassword() async {
    // Show confirmation bottom sheet
    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Reset Password',
              style: Theme.of(
                context,
              ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            Text(
              'Reset your password for $_userEmail?',
              style: Theme.of(context).textTheme.bodyLarge,
            ),
            const SizedBox(height: 8),
            Text(
              'You will receive an OTP via email to verify and set a new password.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(
                  context,
                ).colorScheme.onSurface.withValues(alpha: 0.7),
              ),
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(false),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                    child: const Text('Cancel'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: () => Navigator.of(context).pop(true),
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.red,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                    child: const Text('Reset'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );

    if (confirmed != true) return;

    // Start the OTP flow for password reset
    setState(() {
      _authLoading = true;
      _authError = null;
    });

    try {
      await AuthService.instance.requestOTP(_userEmail);

      if (!mounted) return;

      setState(() {
        _authStep = AuthStep.otpVerify;
        _isResettingPassword = true; // Mark that we're in reset flow
        _authLoading = false;
      });

      StatusMessageController.instance.showMessage(
        'Reset OTP sent to $_userEmail',
        duration: const Duration(seconds: 2),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _authError = e.toString().replaceFirst('Exception: ', '');
        _authLoading = false;
      });
    }
  }

  Future<void> _handleCreateAccount() async {
    // Dismiss keyboard
    FocusScope.of(context).unfocus();

    final password = _passwordController.text;
    if (password.length < 6) {
      setState(() => _authError = 'Password must be at least 6 characters');
      return;
    }

    setState(() {
      _authLoading = true;
      _authError = null;
    });

    try {
      // Check if we're resetting password or creating account
      if (_isResettingPassword) {
        final result = await AuthService.instance.resetPassword(
          _userEmail,
          password,
        );

        if (!mounted) return;

        if (result['success'] == true) {
          setState(() {
            _authStep = AuthStep.passwordLogin;
            _authLoading = false;
            _isResettingPassword = false;
            _passwordController.clear();
          });

          StatusMessageController.instance.showMessage(
            'Password reset successfully! Please login',
            duration: const Duration(seconds: 2),
          );
        }
      } else {
        // Normal account creation
        final result = await AuthService.instance.createAccount(
          _userEmail,
          password,
        );

        if (!mounted) return;

        if (result['success'] == true) {
          setState(() {
            _currentUser = result['user'];
            _authStep = AuthStep.loggedIn;
            _authLoading = false;
          });

          // Sync is now event-based (on app background) - no timer needed

          StatusMessageController.instance.showMessage(
            'Account created successfully!',
            duration: const Duration(seconds: 2),
          );

          // Notify parent of successful login
          widget.onLoginSuccess?.call();
        }
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _authError = e.toString().replaceFirst('Exception: ', '');
        _authLoading = false;
      });
    }
  }

  Future<void> _handleLogout() async {
    // Show confirmation bottom sheet
    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Logout',
              style: Theme.of(
                context,
              ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            Text(
              'Are you sure you want to logout?',
              style: Theme.of(context).textTheme.bodyLarge,
            ),
            const SizedBox(height: 8),
            Text(
              'You will need to log in again to access your account.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(
                  context,
                ).colorScheme.onSurface.withValues(alpha: 0.7),
              ),
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(false),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                    child: const Text('Cancel'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: () => Navigator.of(context).pop(true),
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.red,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                    child: const Text('Logout'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );

    if (confirmed != true) return;

    // Clear persistent storage
    await AuthService.instance.logout();

    // Sync is event-based - nothing to stop on logout

    setState(() {
      _authStep = AuthStep.emailInput;
      _currentUser = null;
      _userEmail = '';
      _emailController.clear();
      _otpController.clear();
      _passwordController.clear();
      _authError = null;
    });

    StatusMessageController.instance.showMessage(
      'Logged out successfully',
      duration: const Duration(seconds: 2),
    );
  }

  Future<void> _handleRestore() async {
    // Show confirmation bottom sheet
    final confirmed = await showRestoreConfirmationBottomSheet(context);

    if (confirmed != true) return;

    // Show loading state
    setState(() {
      _authLoading = true;
      _authError = null;
    });

    try {
      await SyncService.instance.restoreData();

      if (mounted) {
        setState(() {
          _authLoading = false;
        });

        StatusMessageController.instance.showMessage(
          'Backup restored! Restart the app to see changes',
          duration: const Duration(milliseconds: 3500),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _authLoading = false;
          _authError = e.toString();
        });

        StatusMessageController.instance.showMessage(
          'Restore failed: ${e.toString()}',
          duration: const Duration(milliseconds: 3000),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final size = MediaQuery.of(context).size;

    // Use fixed sizes on desktop, responsive on mobile
    final isDesktop = _isDesktopPlatform;
    final buttonHeight = isDesktop ? 48.0 : size.height * 0.06;
    final borderRadius = isDesktop ? 12.0 : size.width * 0.03;
    final fontSize = isDesktop ? 14.0 : size.width * 0.04;
    final spacing = isDesktop ? 12.0 : size.width * 0.02;
    final verticalSpacing = isDesktop ? 16.0 : size.height * 0.02;
    final loadingSize = isDesktop ? 20.0 : size.width * 0.05;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // Show different content based on auth step
        if (_authStep == AuthStep.loggedIn) ...[
          // Logged in view - email, restore button, and logout button
          Text(
            _currentUser?['email'] ?? _userEmail,
            style: theme.textTheme.bodyLarge?.copyWith(
              fontWeight: FontWeight.w600,
              color: cs.primary,
            ),
          ),
          SizedBox(height: verticalSpacing),
          // Row with Restore (2x) and Logout (1x) buttons
          Row(
            children: [
              // Restore button (2x width)
              Expanded(
                flex: 2,
                child: ElevatedButton(
                  onPressed: _handleRestore,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: cs.primary,
                    foregroundColor: cs.onPrimary,
                    minimumSize: Size(double.infinity, buttonHeight),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(borderRadius),
                    ),
                  ),
                  child: Text(
                    'Restore Backup',
                    style: TextStyle(
                      fontSize: fontSize,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
              SizedBox(width: spacing),
              // Logout button (1x width)
              Expanded(
                flex: 1,
                child: FilledButton(
                  onPressed: _handleLogout,
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.red,
                    foregroundColor: Colors.white,
                    minimumSize: Size(double.infinity, buttonHeight),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(borderRadius),
                    ),
                  ),
                  child: Text(
                    'Logout',
                    style: TextStyle(
                      fontSize: fontSize,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ] else ...[
          // Auth flow views
          if (_authStep == AuthStep.emailInput) ...[
            // Email input
            TextField(
              controller: _emailController,
              keyboardType: TextInputType.emailAddress,
              enabled: !_authLoading,
              decoration: InputDecoration(
                labelText: 'Email Address',
                hintText: 'Enter your email',
                errorText: _authError,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(borderRadius),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(borderRadius),
                  borderSide: BorderSide(
                    color: cs.onSurface.withAlpha((0.3 * 255).round()),
                  ),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(borderRadius),
                  borderSide: BorderSide(color: cs.primary, width: 2),
                ),
                prefixIcon: Icon(Icons.email_outlined, color: cs.primary),
              ),
            ),
          ] else if (_authStep == AuthStep.otpVerify) ...[
            // OTP verification - no extra text
            TextField(
              controller: _otpController,
              keyboardType: TextInputType.number,
              enabled: !_authLoading,
              maxLength: 6,
              textAlign: TextAlign.center,
              decoration: InputDecoration(
                labelText: 'Verification Code',
                errorText: _authError,
                counterText: '',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(borderRadius),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(borderRadius),
                  borderSide: BorderSide(
                    color: cs.onSurface.withAlpha((0.3 * 255).round()),
                  ),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(borderRadius),
                  borderSide: BorderSide(color: cs.primary, width: 2),
                ),
              ),
            ),
          ] else if (_authStep == AuthStep.passwordLogin ||
              _authStep == AuthStep.passwordCreate) ...[
            // Password input - no extra text
            TextField(
              controller: _passwordController,
              obscureText: true,
              enabled: !_authLoading,
              decoration: InputDecoration(
                labelText: _isResettingPassword ? 'New Password' : 'Password',
                hintText: _authStep == AuthStep.passwordCreate
                    ? 'At least 6 characters'
                    : 'Enter your password',
                errorText: _authError,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(borderRadius),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(borderRadius),
                  borderSide: BorderSide(
                    color: cs.onSurface.withAlpha((0.3 * 255).round()),
                  ),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(borderRadius),
                  borderSide: BorderSide(color: cs.primary, width: 2),
                ),
                prefixIcon: Icon(Icons.lock_outlined, color: cs.primary),
              ),
            ),
          ],

          SizedBox(height: verticalSpacing),

          // Action button with Back button in row (2:1 flex)
          // For passwordLogin, show 3 buttons (Back, Login, Reset)
          if (_authStep == AuthStep.passwordLogin)
            Row(
              children: [
                // Back button
                Expanded(
                  flex: 1,
                  child: OutlinedButton(
                    onPressed: _authLoading
                        ? null
                        : () {
                            setState(() {
                              _authStep = AuthStep.emailInput;
                              _authError = null;
                              _otpController.clear();
                              _passwordController.clear();
                              _isResettingPassword = false;
                            });
                          },
                    style: OutlinedButton.styleFrom(
                      foregroundColor: cs.primary,
                      side: BorderSide(color: cs.primary),
                      minimumSize: Size(double.infinity, buttonHeight),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(borderRadius),
                      ),
                    ),
                    child: Text(
                      'Back',
                      style: TextStyle(
                        fontSize: fontSize,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
                SizedBox(width: spacing),
                // Login button
                Expanded(
                  flex: 1,
                  child: ElevatedButton(
                    onPressed: _authLoading ? null : _handleLogin,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: cs.primary,
                      foregroundColor: cs.onPrimary,
                      minimumSize: Size(double.infinity, buttonHeight),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(borderRadius),
                      ),
                      elevation: 2,
                    ),
                    child: _authLoading
                        ? SizedBox(
                            height: loadingSize,
                            width: loadingSize,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(
                                cs.onPrimary,
                              ),
                            ),
                          )
                        : Text(
                            'Login',
                            style: TextStyle(
                              fontSize: fontSize,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                  ),
                ),
                SizedBox(width: spacing),
                // Reset button
                Expanded(
                  flex: 1,
                  child: FilledButton(
                    onPressed: _authLoading ? null : _handleResetPassword,
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.red,
                      foregroundColor: Colors.white,
                      minimumSize: Size(double.infinity, buttonHeight),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(borderRadius),
                      ),
                    ),
                    child: Text(
                      'Reset',
                      style: TextStyle(
                        fontSize: fontSize,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ],
            )
          else
            // For other steps, show normal layout
            Row(
              children: [
                // Back button (except on email input)
                if (_authStep != AuthStep.emailInput) ...[
                  Expanded(
                    flex: 1,
                    child: OutlinedButton(
                      onPressed: _authLoading
                          ? null
                          : () {
                              setState(() {
                                _authStep = AuthStep.emailInput;
                                _authError = null;
                                _otpController.clear();
                                _passwordController.clear();
                                _isResettingPassword = false;
                              });
                            },
                      style: OutlinedButton.styleFrom(
                        foregroundColor: cs.primary,
                        side: BorderSide(color: cs.primary),
                        minimumSize: Size(double.infinity, buttonHeight),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(borderRadius),
                        ),
                      ),
                      child: Text(
                        'Back',
                        style: TextStyle(
                          fontSize: fontSize,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                  SizedBox(width: spacing),
                ],
                // Next/Action button
                Expanded(
                  flex: 2,
                  child: ElevatedButton(
                    onPressed: _authLoading
                        ? null
                        : () {
                            if (_authStep == AuthStep.emailInput) {
                              _handleEmailSubmit();
                            } else if (_authStep == AuthStep.passwordLogin) {
                              _handleLogin();
                            } else if (_authStep == AuthStep.otpVerify) {
                              _handleOTPVerify();
                            } else if (_authStep == AuthStep.passwordCreate) {
                              _handleCreateAccount();
                            }
                          },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: cs.primary,
                      foregroundColor: cs.onPrimary,
                      minimumSize: Size(double.infinity, buttonHeight),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(borderRadius),
                      ),
                      elevation: 2,
                    ),
                    child: _authLoading
                        ? SizedBox(
                            height: loadingSize,
                            width: loadingSize,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(
                                cs.onPrimary,
                              ),
                            ),
                          )
                        : Text(
                            _authStep == AuthStep.emailInput
                                ? 'Next'
                                : _authStep == AuthStep.passwordLogin
                                ? 'Login'
                                : _authStep == AuthStep.otpVerify
                                ? 'Verify'
                                : _authStep == AuthStep.passwordCreate
                                ? (_isResettingPassword
                                      ? 'Update Password'
                                      : 'Create Account')
                                : 'Create Account',
                            style: TextStyle(
                              fontSize: fontSize,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                  ),
                ),
              ],
            ),
        ],
      ],
    );
  }
}
