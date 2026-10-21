import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'home_screen.dart';
import 'services/auth_service.dart';
import 'services/session_manager.dart';

enum AuthMode { signIn, register, forgotPassword, resetPasswordOtp }

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key, this.initialMode = AuthMode.signIn});

  final AuthMode initialMode;

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  late AuthMode _mode;
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _newPasswordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _usernameController = TextEditingController();

  final List<TextEditingController> _otpControllers = List.generate(
    5,
    (_) => TextEditingController(),
  );
  final List<FocusNode> _otpFocusNodes = List.generate(5, (_) => FocusNode());

  bool _obscurePassword = true;
  bool _obscureNewPassword = true;
  bool _obscureConfirmPassword = true;
  bool _rememberMe = false;

  Timer? _resendTimer;
  int _resendSeconds = 45;
  bool _canResend = false;

  final _authService = AuthService();
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _mode = widget.initialMode;
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    _usernameController.dispose();
    for (final c in _otpControllers) {
      c.dispose();
    }
    for (final f in _otpFocusNodes) {
      f.dispose();
    }
    _resendTimer?.cancel();
    super.dispose();
  }

  void _startResendTimer() {
    _resendTimer?.cancel();
    setState(() {
      _resendSeconds = 45;
      _canResend = false;
    });
    _resendTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;
      if (_resendSeconds > 1) {
        setState(() => _resendSeconds--);
      } else {
        timer.cancel();
        setState(() => _canResend = true);
      }
    });
  }

  void _clearOtp() {
    for (final controller in _otpControllers) {
      controller.clear();
    }
  }

  void _switchMode(AuthMode mode) {
    setState(() {
      _mode = mode;
    });
    if (mode == AuthMode.resetPasswordOtp) {
      _clearOtp();
      _startResendTimer();
    }
  }

  Future<void> _handleSubmit() async {
    if (_isLoading) return;

    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();
    final username = _usernameController.text.trim();
    final otpToken = _otpControllers.map((c) => c.text.trim()).join();
    final newPassword = _newPasswordController.text.trim();
    final confirmPassword = _confirmPasswordController.text.trim();

    FocusScope.of(context).unfocus();

    switch (_mode) {
      case AuthMode.signIn:
        if (email.isEmpty || password.isEmpty) {
          _showToast(
            'Please enter your username or email and password.',
            isError: true,
          );
          return;
        }
        setState(() => _isLoading = true);
        try {
          final res = await _authService.login(
            identifier: email,
            password: password,
          );
          await SessionManager.instance.saveSession(
            user: res.user,
            tokens: res.tokens,
          );
          _showToast('Welcome back, ${res.user.username}!');
          _navigateToHome();
        } on AuthException catch (e) {
          _showToast(e.message, isError: true);
        } catch (e) {
          _showToast(
            'Failed to connect to server. Ensure server is running.',
            isError: true,
          );
        } finally {
          if (mounted) setState(() => _isLoading = false);
        }

      case AuthMode.register:
        if (username.isEmpty || email.isEmpty || password.isEmpty) {
          _showToast('Please fill in all required fields.', isError: true);
          return;
        }
        if (username.length < 3) {
          _showToast(
            'Username must be at least 3 characters long.',
            isError: true,
          );
          return;
        }
        if (password.length < 8) {
          _showToast(
            'Password must be at least 8 characters long.',
            isError: true,
          );
          return;
        }
        setState(() => _isLoading = true);
        try {
          await _authService.register(
            username: username,
            email: email,
            password: password,
          );
          _showToast(
            'Registration successful! Check your email for the verification link.',
          );
          _switchMode(AuthMode.signIn);
        } on AuthException catch (e) {
          _showToast(e.message, isError: true);
        } catch (e) {
          _showToast(
            'Failed to connect to server. Check network connection.',
            isError: true,
          );
        } finally {
          if (mounted) setState(() => _isLoading = false);
        }

      case AuthMode.forgotPassword:
        if (email.isEmpty) {
          _showToast('Please enter your email address.', isError: true);
          return;
        }
        setState(() => _isLoading = true);
        try {
          final msg = await _authService.forgotPassword(email);
          _showToast(msg);
          _switchMode(AuthMode.resetPasswordOtp);
        } on AuthException catch (e) {
          _showToast(e.message, isError: true);
        } catch (e) {
          _showToast('Failed to send reset email.', isError: true);
        } finally {
          if (mounted) setState(() => _isLoading = false);
        }

      case AuthMode.resetPasswordOtp:
        if (otpToken.length < 5) {
          _showToast(
            'Please enter the full 5-digit reset code.',
            isError: true,
          );
          return;
        }
        if (newPassword.isEmpty) {
          _showToast('Please enter a new password.', isError: true);
          return;
        }
        if (newPassword.length < 8) {
          _showToast(
            'New password must be at least 8 characters long.',
            isError: true,
          );
          return;
        }
        if (newPassword != confirmPassword) {
          _showToast('Passwords do not match.', isError: true);
          return;
        }
        setState(() => _isLoading = true);
        try {
          final msg = await _authService.resetPassword(
            token: otpToken,
            newPassword: newPassword,
          );
          _showToast(msg);
          _switchMode(AuthMode.signIn);
        } on AuthException catch (e) {
          _showToast(e.message, isError: true);
        } catch (e) {
          _showToast(
            'Password reset failed. Invalid or expired code.',
            isError: true,
          );
        } finally {
          if (mounted) setState(() => _isLoading = false);
        }
    }
  }

  Future<void> _handleGoogleSignIn() async {
    if (_isLoading) return;
    setState(() => _isLoading = true);
    try {
      final res = await _authService.googleLogin();
      await SessionManager.instance.saveSession(
        user: res.user,
        tokens: res.tokens,
      );
      if (!mounted) return;
      _showToast('Welcome, ${res.user.username}!');
      _navigateToHome();
    } on AuthException catch (error) {
      if (mounted) _showToast(error.message, isError: true);
    } catch (_) {
      if (mounted) {
        _showToast('Google sign-in could not be completed.', isError: true);
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showToast(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: TextStyle(
            color: isError ? Colors.white : const Color(0xFF0F081C),
            fontWeight: FontWeight.w800,
          ),
        ),
        backgroundColor: isError
            ? const Color(0xFFE53935)
            : const Color(0xFFFFD700),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        duration: const Duration(seconds: 4),
      ),
    );
  }

  void _navigateToHome() {
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    } else {
      Navigator.of(
        context,
      ).pushReplacement(MaterialPageRoute(builder: (_) => const HomeScreen()));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F081C),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final isCompactWidth = constraints.maxWidth < 360;
            final horizontalPadding = isCompactWidth ? 16.0 : 24.0;
            return SingleChildScrollView(
              padding: EdgeInsets.symmetric(
                horizontal: horizontalPadding,
                vertical: 12,
              ),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 440),
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 350),
                    switchInCurve: Curves.easeOutCubic,
                    switchOutCurve: Curves.easeInCubic,
                    transitionBuilder: (child, animation) => FadeTransition(
                      opacity: animation,
                      child: SlideTransition(
                        position: Tween<Offset>(
                          begin: const Offset(0.05, 0),
                          end: Offset.zero,
                        ).animate(animation),
                        child: child,
                      ),
                    ),
                    child: KeyedSubtree(
                      key: ValueKey(_mode),
                      child: _buildAuthContent(constraints),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildAuthContent(BoxConstraints outerConstraints) {
    final isCompactHeight = outerConstraints.maxHeight < 680;
    final orbSize = isCompactHeight ? 76.0 : 96.0;
    final topGap = isCompactHeight ? 16.0 : 28.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Top Bar
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            IconButton(
              onPressed: () {
                switch (_mode) {
                  case AuthMode.signIn:
                    if (Navigator.of(context).canPop()) {
                      Navigator.of(context).pop();
                    } else {
                      _navigateToHome();
                    }
                  case AuthMode.register:
                  case AuthMode.forgotPassword:
                    _switchMode(AuthMode.signIn);
                  case AuthMode.resetPasswordOtp:
                    _switchMode(AuthMode.forgotPassword);
                }
              },
              icon: Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.08),
                  shape: BoxShape.circle,
                  border: Border.all(color: const Color(0xFF38235E)),
                ),
                child: const Icon(
                  Icons.arrow_back,
                  size: 18,
                  color: Colors.white,
                ),
              ),
            ),
            _OrbHeaderGraphic(maxSize: orbSize),
            TextButton(
              onPressed: _navigateToHome,
              child: const Text(
                'Skip',
                style: TextStyle(
                  color: Color(0xFFFFD700),
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                ),
              ),
            ),
          ],
        ).animate().fadeIn(duration: 400.ms),

        SizedBox(height: topGap),

        // Progressive Step Indicator for Password Reset Flow
        if (_mode == AuthMode.forgotPassword ||
            _mode == AuthMode.resetPasswordOtp)
          _buildProgressiveResetIndicator(),

        // Headers
        Text(
              switch (_mode) {
                AuthMode.signIn => 'Welcome Back!',
                AuthMode.register => 'Create Your Account',
                AuthMode.forgotPassword => 'Forgot Password?',
                AuthMode.resetPasswordOtp => 'Set New Password',
              },
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white,
                fontSize: isCompactHeight ? 24 : 28,
                fontWeight: FontWeight.w900,
                letterSpacing: -0.5,
              ),
            )
            .animate()
            .fadeIn(duration: 400.ms, delay: 50.ms)
            .slideY(begin: 0.1, end: 0),
        const SizedBox(height: 8),
        Text(
          switch (_mode) {
            AuthMode.signIn =>
              'Sign in to access smart, personalized prediction plans made for you.',
            AuthMode.register =>
              'Create your account to explore exciting match predictions and insights.',
            AuthMode.forgotPassword =>
              "Enter your email address and we'll send a 5-digit reset code.",
            AuthMode.resetPasswordOtp =>
              'Enter the 5-digit code sent to your email and set your new password below.',
          },
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Color(0xFFA898C8),
            fontSize: 13,
            height: 1.4,
          ),
        ).animate().fadeIn(duration: 400.ms, delay: 100.ms),

        SizedBox(height: isCompactHeight ? 20 : 28),

        // Form Fields by Mode
        if (_mode == AuthMode.register) ...[
          _CustomLabelField(
                label: 'Username*',
                hint: 'alex_smith',
                controller: _usernameController,
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z0-9_]')),
                  LengthLimitingTextInputFormatter(30),
                ],
              )
              .animate()
              .fadeIn(duration: 400.ms, delay: 150.ms)
              .slideY(begin: 0.08, end: 0),
          const SizedBox(height: 16),
        ],

        if (_mode == AuthMode.signIn ||
            _mode == AuthMode.register ||
            _mode == AuthMode.forgotPassword) ...[
          _CustomLabelField(
                label: _mode == AuthMode.signIn
                    ? 'Username or email*'
                    : 'Email address*',
                hint: _mode == AuthMode.signIn
                    ? 'alex_smith or example@gmail.com'
                    : 'example@gmail.com',
                controller: _emailController,
                keyboardType: TextInputType.emailAddress,
              )
              .animate()
              .fadeIn(duration: 400.ms, delay: 180.ms)
              .slideY(begin: 0.08, end: 0),
        ],

        if (_mode == AuthMode.signIn || _mode == AuthMode.register) ...[
          const SizedBox(height: 16),
          _CustomLabelField(
                label: 'Password*',
                hint: '@Sn123hsn#',
                controller: _passwordController,
                obscureText: _obscurePassword,
                suffixIcon: IconButton(
                  icon: Icon(
                    _obscurePassword
                        ? Icons.visibility_off_outlined
                        : Icons.visibility_outlined,
                    color: const Color(0xFFA898C8),
                    size: 20,
                  ),
                  onPressed: () {
                    setState(() {
                      _obscurePassword = !_obscurePassword;
                    });
                  },
                ),
              )
              .animate()
              .fadeIn(duration: 400.ms, delay: 210.ms)
              .slideY(begin: 0.08, end: 0),
        ],

        // Step 2 Password Reset: OTP Code + New Password Fields
        if (_mode == AuthMode.resetPasswordOtp) ...[
          const Text(
            '5-Digit Reset Code*',
            style: TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          _OtpInputRow(controllers: _otpControllers, focusNodes: _otpFocusNodes)
              .animate()
              .fadeIn(duration: 400.ms, delay: 150.ms)
              .scale(begin: const Offset(0.96, 0.96), end: const Offset(1, 1)),
          const SizedBox(height: 14),

          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text(
                "Didn't receive code? ",
                style: TextStyle(color: Color(0xFFA898C8), fontSize: 13),
              ),
              GestureDetector(
                onTap: _canResend
                    ? () {
                        _startResendTimer();
                        _showToast('A new 5-digit reset code has been sent!');
                      }
                    : null,
                child: Text(
                  _canResend
                      ? 'Resend Code'
                      : 'Resend in 00:${_resendSeconds.toString().padLeft(2, '0')}',
                  style: TextStyle(
                    color: _canResend
                        ? const Color(0xFFFFD700)
                        : Colors.white54,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ).animate().fadeIn(duration: 400.ms, delay: 200.ms),

          const SizedBox(height: 20),
          _CustomLabelField(
                label: 'New Password*',
                hint: 'Enter new password',
                controller: _newPasswordController,
                obscureText: _obscureNewPassword,
                suffixIcon: IconButton(
                  icon: Icon(
                    _obscureNewPassword
                        ? Icons.visibility_off_outlined
                        : Icons.visibility_outlined,
                    color: const Color(0xFFA898C8),
                    size: 20,
                  ),
                  onPressed: () {
                    setState(() {
                      _obscureNewPassword = !_obscureNewPassword;
                    });
                  },
                ),
              )
              .animate()
              .fadeIn(duration: 400.ms, delay: 230.ms)
              .slideY(begin: 0.08, end: 0),
          const SizedBox(height: 16),
          _CustomLabelField(
                label: 'Confirm New Password*',
                hint: 'Re-enter new password',
                controller: _confirmPasswordController,
                obscureText: _obscureConfirmPassword,
                suffixIcon: IconButton(
                  icon: Icon(
                    _obscureConfirmPassword
                        ? Icons.visibility_off_outlined
                        : Icons.visibility_outlined,
                    color: const Color(0xFFA898C8),
                    size: 20,
                  ),
                  onPressed: () {
                    setState(() {
                      _obscureConfirmPassword = !_obscureConfirmPassword;
                    });
                  },
                ),
              )
              .animate()
              .fadeIn(duration: 400.ms, delay: 260.ms)
              .slideY(begin: 0.08, end: 0),
        ],

        // Remember Me & Forgot Password row
        if (_mode == AuthMode.signIn) ...[
          const SizedBox(height: 12),
          Row(
            children: [
              GestureDetector(
                onTap: () {
                  setState(() {
                    _rememberMe = !_rememberMe;
                  });
                },
                child: Row(
                  children: [
                    Container(
                      width: 20,
                      height: 20,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: _rememberMe
                              ? const Color(0xFFFFD700)
                              : const Color(0xFF38235E),
                          width: 1.5,
                        ),
                        color: _rememberMe
                            ? const Color(0xFFFFD700)
                            : Colors.transparent,
                      ),
                      child: _rememberMe
                          ? const Icon(
                              Icons.check,
                              size: 14,
                              color: Color(0xFF0F081C),
                            )
                          : null,
                    ),
                    const SizedBox(width: 10),
                    const Text(
                      'Remember me',
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              TextButton(
                onPressed: () => _switchMode(AuthMode.forgotPassword),
                style: TextButton.styleFrom(
                  padding: EdgeInsets.zero,
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: const Text(
                  'Forgot Password?',
                  style: TextStyle(
                    color: Color(0xFFFFD700),
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ).animate().fadeIn(duration: 400.ms, delay: 240.ms),
        ],

        SizedBox(height: isCompactHeight ? 20 : 28),

        // Primary Action Button
        _PrimaryNeonButton(
              label: switch (_mode) {
                AuthMode.signIn => 'Sign in',
                AuthMode.register => 'Register',
                AuthMode.forgotPassword => 'Send Reset Code',
                AuthMode.resetPasswordOtp => 'Reset Password',
              },
              isLoading: _isLoading,
              onTap: _handleSubmit,
            )
            .animate()
            .fadeIn(duration: 450.ms, delay: 280.ms)
            .shimmer(
              delay: 1.seconds,
              duration: 2.seconds,
              color: const Color(0xFFFFF7C2),
            ),

        const SizedBox(height: 12),

        // Continue as Guest Button
        TextButton(
          onPressed: _navigateToHome,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: const [
              Text(
                'Continue as Guest',
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
              SizedBox(width: 6),
              Icon(
                Icons.arrow_forward_rounded,
                size: 16,
                color: Color(0xFFFFD700),
              ),
            ],
          ),
        ).animate().fadeIn(duration: 400.ms, delay: 300.ms),

        // Social Sign In (Only on Sign In & Register)
        if (_mode == AuthMode.signIn || _mode == AuthMode.register) ...[
          const SizedBox(height: 16),
          const Row(
            children: [
              Expanded(child: Divider(color: Color(0xFF2C1A50), thickness: 1)),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 14),
                child: Text(
                  'Or continue with',
                  style: TextStyle(
                    color: Color(0xFFA898C8),
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              Expanded(child: Divider(color: Color(0xFF2C1A50), thickness: 1)),
            ],
          ).animate().fadeIn(duration: 400.ms, delay: 320.ms),
          const SizedBox(height: 16),
          Row(
                children: [
                  Expanded(
                    child: _SocialButton(
                      label: 'Google',
                      iconWidget: const _GoogleLogoWidget(),
                      onTap: _handleGoogleSignIn,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: _SocialButton(
                      label: 'Apple',
                      iconWidget: const Icon(
                        Icons.apple,
                        color: Colors.white,
                        size: 22,
                      ),
                      onTap: () {},
                    ),
                  ),
                ],
              )
              .animate()
              .fadeIn(duration: 400.ms, delay: 350.ms)
              .slideY(begin: 0.08, end: 0),
        ],

        const SizedBox(height: 24),

        // Footer Switch Mode
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(switch (_mode) {
              AuthMode.signIn => "Don't have an account? ",
              AuthMode.register => 'Already have an account? ',
              AuthMode.forgotPassword => 'Remembered your password? ',
              AuthMode.resetPasswordOtp => 'Remembered your password? ',
            }, style: const TextStyle(color: Color(0xFFA898C8), fontSize: 14)),
            GestureDetector(
              onTap: () {
                if (_mode == AuthMode.signIn) {
                  _switchMode(AuthMode.register);
                } else {
                  _switchMode(AuthMode.signIn);
                }
              },
              child: Text(
                switch (_mode) {
                  AuthMode.signIn => 'Sign up',
                  AuthMode.register => 'Sign In',
                  AuthMode.forgotPassword => 'Sign In',
                  AuthMode.resetPasswordOtp => 'Sign In',
                },
                style: const TextStyle(
                  color: Color(0xFFFFD700),
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ).animate().fadeIn(duration: 400.ms, delay: 380.ms),
        const SizedBox(height: 16),
      ],
    );
  }

  Widget _buildProgressiveResetIndicator() {
    final isStep2 = _mode == AuthMode.resetPasswordOtp;
    return Container(
      margin: const EdgeInsets.only(bottom: 18),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF1B1033),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF38235E)),
      ),
      child: Row(
        children: [
          _StepBadge(
            number: '1',
            title: 'Request Code',
            isActive: true,
            isDone: isStep2,
          ),
          Expanded(
            child: Container(
              height: 2,
              margin: const EdgeInsets.symmetric(horizontal: 10),
              color: isStep2
                  ? const Color(0xFFFFD700)
                  : const Color(0xFF38235E),
            ),
          ),
          _StepBadge(
            number: '2',
            title: 'Code & Password',
            isActive: isStep2,
            isDone: false,
          ),
        ],
      ),
    ).animate().fadeIn(duration: 400.ms);
  }
}

class _StepBadge extends StatelessWidget {
  const _StepBadge({
    required this.number,
    required this.title,
    required this.isActive,
    required this.isDone,
  });

  final String number;
  final String title;
  final bool isActive;
  final bool isDone;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 24,
          height: 24,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: isDone || isActive
                ? const Color(0xFFFFD700)
                : const Color(0xFF261D36),
            border: Border.all(
              color: isDone || isActive
                  ? const Color(0xFFFFD700)
                  : const Color(0xFF4A386D),
            ),
          ),
          child: Center(
            child: isDone
                ? const Icon(Icons.check, size: 14, color: Color(0xFF0F081C))
                : Text(
                    number,
                    style: TextStyle(
                      color: isActive
                          ? const Color(0xFF0F081C)
                          : Colors.white60,
                      fontWeight: FontWeight.w900,
                      fontSize: 12,
                    ),
                  ),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          title,
          style: TextStyle(
            color: isActive || isDone ? Colors.white : Colors.white54,
            fontSize: 12,
            fontWeight: isActive || isDone ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
      ],
    );
  }
}

class _OtpInputRow extends StatelessWidget {
  const _OtpInputRow({required this.controllers, required this.focusNodes});

  final List<TextEditingController> controllers;
  final List<FocusNode> focusNodes;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final itemWidth = ((constraints.maxWidth - 32) / 5).clamp(42.0, 62.0);
        final itemHeight = (itemWidth * 1.15).clamp(50.0, 68.0);
        return Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: List.generate(5, (index) {
            return SizedBox(
              width: itemWidth,
              height: itemHeight,
              child: TextField(
                controller: controllers[index],
                focusNode: focusNodes[index],
                keyboardType: TextInputType.number,
                textAlign: TextAlign.center,
                maxLength: 1,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                style: TextStyle(
                  color: Colors.white,
                  fontSize: (itemWidth * 0.42).clamp(18.0, 24.0),
                  fontWeight: FontWeight.w900,
                ),
                decoration: InputDecoration(
                  counterText: '',
                  filled: true,
                  fillColor: const Color(0xFF1B1033),
                  contentPadding: EdgeInsets.zero,
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: const BorderSide(
                      color: Color(0xFF38235E),
                      width: 1.5,
                    ),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: const BorderSide(
                      color: Color(0xFFFFD700),
                      width: 2.0,
                    ),
                  ),
                ),
                onChanged: (value) {
                  if (value.isNotEmpty) {
                    if (index < 4) {
                      focusNodes[index + 1].requestFocus();
                    } else {
                      focusNodes[index].unfocus();
                    }
                  } else if (value.isEmpty && index > 0) {
                    focusNodes[index - 1].requestFocus();
                  }
                },
              ),
            );
          }),
        );
      },
    );
  }
}

class _OrbHeaderGraphic extends StatelessWidget {
  const _OrbHeaderGraphic({this.maxSize = 96});
  final double maxSize;

  @override
  Widget build(BuildContext context) {
    final size = maxSize;
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
                width: size * 0.9,
                height: size * 0.9,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      const Color(0xFFFFD700).withValues(alpha: 0.25),
                      const Color(0xFFFFD700).withValues(alpha: 0.06),
                      Colors.transparent,
                    ],
                    stops: const [0.2, 0.65, 1.0],
                  ),
                ),
              )
              .animate(onPlay: (c) => c.repeat(reverse: true))
              .scale(
                begin: const Offset(0.94, 0.94),
                end: const Offset(1.06, 1.06),
                duration: 2000.ms,
              ),

          Container(
            width: size * 0.76,
            height: size * 0.76,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: const Color(0xFFFFD700).withValues(alpha: 0.3),
                width: 1,
              ),
            ),
          ),

          Container(
            width: size * 0.62,
            height: size * 0.62,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: const RadialGradient(
                center: Alignment(-0.3, -0.4),
                radius: 0.85,
                colors: [
                  Color(0xFFFFD700),
                  Color(0xFF8B25C6),
                  Color(0xFF4A1078),
                  Color(0xFF190632),
                ],
                stops: [0.0, 0.4, 0.75, 1.0],
              ),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFFFFD700).withValues(alpha: 0.35),
                  blurRadius: 20,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Colors.white.withValues(alpha: 0.4),
                    Colors.transparent,
                  ],
                  stops: const [0.0, 0.5],
                ),
              ),
            ),
          ).animate().shimmer(
            delay: 500.ms,
            duration: 2500.ms,
            color: const Color(0xFFFFEA79),
          ),
        ],
      ),
    );
  }
}

class _CustomLabelField extends StatelessWidget {
  const _CustomLabelField({
    required this.label,
    required this.hint,
    required this.controller,
    this.obscureText = false,
    this.keyboardType,
    this.suffixIcon,
    this.inputFormatters,
  });

  final String label;
  final String hint;
  final TextEditingController controller;
  final bool obscureText;
  final TextInputType? keyboardType;
  final Widget? suffixIcon;
  final List<TextInputFormatter>? inputFormatters;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: const Color(0xFF1B1033),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFF38235E), width: 1.2),
          ),
          child: TextField(
            controller: controller,
            obscureText: obscureText,
            keyboardType: keyboardType,
            inputFormatters: inputFormatters,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 15,
              fontWeight: FontWeight.w500,
            ),
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: const TextStyle(
                color: Color(0xFFA898C8),
                fontSize: 15,
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 18,
                vertical: 16,
              ),
              border: InputBorder.none,
              suffixIcon: suffixIcon,
            ),
          ),
        ),
      ],
    );
  }
}

class _PrimaryNeonButton extends StatefulWidget {
  const _PrimaryNeonButton({
    required this.label,
    required this.onTap,
    this.isLoading = false,
  });

  final String label;
  final VoidCallback onTap;
  final bool isLoading;

  @override
  State<_PrimaryNeonButton> createState() => _PrimaryNeonButtonState();
}

class _PrimaryNeonButtonState extends State<_PrimaryNeonButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) {
        setState(() => _pressed = false);
        if (!widget.isLoading) widget.onTap();
      },
      onTapCancel: () => setState(() => _pressed = false),
      child: AnimatedScale(
        scale: _pressed ? 0.98 : 1.0,
        duration: const Duration(milliseconds: 100),
        child: Container(
          height: 54,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFFFFEA79), Color(0xFFFFC82C)],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
            borderRadius: BorderRadius.circular(999),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFFFFD700).withValues(alpha: 0.35),
                blurRadius: 18,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: widget.isLoading
              ? const Center(
                  child: SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      color: Color(0xFF0F081C),
                    ),
                  ),
                )
              : Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(
                      Icons.auto_awesome,
                      size: 18,
                      color: Color(0xFF0F081C),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      widget.label,
                      style: const TextStyle(
                        color: Color(0xFF0F081C),
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -0.2,
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}

class _SocialButton extends StatelessWidget {
  const _SocialButton({
    required this.label,
    required this.iconWidget,
    required this.onTap,
  });

  final String label;
  final Widget iconWidget;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 50,
      decoration: BoxDecoration(
        color: const Color(0xFF1B1033),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF38235E), width: 1),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            iconWidget,
            const SizedBox(width: 10),
            Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GoogleLogoWidget extends StatelessWidget {
  const _GoogleLogoWidget();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 18,
      height: 18,
      child: CustomPaint(painter: _GoogleLogoPainter()),
    );
  }
}

class _GoogleLogoPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final double w = size.width;
    final double h = size.height;

    final paint = Paint()..style = PaintingStyle.fill;

    // Blue
    paint.color = const Color(0xFF4285F4);
    canvas.drawPath(
      Path()
        ..moveTo(w * 0.95, h * 0.5)
        ..cubicTo(w * 0.95, h * 0.44, w * 0.94, h * 0.38, w * 0.93, h * 0.33)
        ..lineTo(w * 0.5, h * 0.33)
        ..lineTo(w * 0.5, h * 0.52)
        ..lineTo(w * 0.76, h * 0.52)
        ..cubicTo(w * 0.75, h * 0.6, w * 0.7, h * 0.68, w * 0.62, h * 0.74)
        ..lineTo(w * 0.62, h * 0.88)
        ..lineTo(w * 0.77, h * 0.88)
        ..cubicTo(w * 0.86, h * 0.8, w * 0.95, h * 0.66, w * 0.95, h * 0.5),
      paint,
    );

    // Green
    paint.color = const Color(0xFF34A853);
    canvas.drawPath(
      Path()
        ..moveTo(w * 0.5, h * 0.95)
        ..cubicTo(w * 0.68, h * 0.95, w * 0.83, h * 0.89, w * 0.94, h * 0.79)
        ..lineTo(w * 0.79, h * 0.67)
        ..cubicTo(w * 0.72, h * 0.72, w * 0.62, h * 0.76, w * 0.5, h * 0.76)
        ..cubicTo(w * 0.34, h * 0.76, w * 0.2, h * 0.65, w * 0.15, h * 0.5)
        ..lineTo(w * 0.0, h * 0.62)
        ..lineTo(w * 0.0, h * 0.76)
        ..cubicTo(w * 0.11, h * 0.88, w * 0.29, h * 0.95, w * 0.5, h * 0.95),
      paint,
    );

    // Yellow
    paint.color = const Color(0xFFFBBC05);
    canvas.drawPath(
      Path()
        ..moveTo(w * 0.15, h * 0.5)
        ..cubicTo(w * 0.14, h * 0.45, w * 0.14, h * 0.4, w * 0.15, h * 0.35)
        ..lineTo(w * 0.15, h * 0.21)
        ..lineTo(w * 0.0, h * 0.21)
        ..cubicTo(-w * 0.05, h * 0.3, -w * 0.05, h * 0.55, w * 0.0, h * 0.64)
        ..lineTo(w * 0.15, h * 0.5),
      paint,
    );

    // Red
    paint.color = const Color(0xFFEA4335);
    canvas.drawPath(
      Path()
        ..moveTo(w * 0.5, h * 0.19)
        ..cubicTo(w * 0.63, h * 0.19, w * 0.74, h * 0.24, w * 0.83, h * 0.32)
        ..lineTo(w * 0.95, h * 0.2)
        ..cubicTo(w * 0.83, h * 0.09, w * 0.68, h * 0.02, w * 0.5, h * 0.02)
        ..cubicTo(w * 0.29, h * 0.02, w * 0.11, h * 0.1, w * 0.0, h * 0.23)
        ..lineTo(w * 0.15, h * 0.35)
        ..cubicTo(w * 0.2, h * 0.25, w * 0.34, h * 0.19, w * 0.5, h * 0.19),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
