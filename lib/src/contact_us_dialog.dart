import 'package:flutter/material.dart';

import 'models/support_model.dart';
import 'services/support_service.dart';
import 'services/session_manager.dart';

class ContactUsDialog extends StatefulWidget {
  const ContactUsDialog({super.key});

  static Future<void> show(BuildContext context) {
    return showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (_) => const ContactUsDialog(),
    );
  }

  @override
  State<ContactUsDialog> createState() => _ContactUsDialogState();
}

class _ContactUsDialogState extends State<ContactUsDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _subjectController = TextEditingController();
  final _messageController = TextEditingController();

  final _supportService = SupportService();
  bool _isLoading = false;
  String? _errorMessage;
  ContactResponse? _successResponse;

  @override
  void initState() {
    super.initState();
    // Auto-fill logged in user info if available
    final user = SessionManager.instance.currentUser;
    if (user != null) {
      _nameController.text = user.username;
      _emailController.text = user.email;
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _subjectController.dispose();
    _messageController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final req = ContactRequest(
        name: _nameController.text.trim(),
        email: _emailController.text.trim(),
        subject: _subjectController.text.trim(),
        message: _messageController.text.trim(),
      );

      final res = await _supportService.submitContactForm(req);

      if (mounted) {
        setState(() {
          _isLoading = false;
          _successResponse = res;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = e.toString();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 440),
        decoration: BoxDecoration(
          color: const Color(0xFF191226),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: const Color(0xFFFFD700).withValues(alpha: 0.35),
            width: 1.2,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.6),
              blurRadius: 24,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header
              Container(
                padding: const EdgeInsets.fromLTRB(20, 16, 12, 16),
                decoration: const BoxDecoration(
                  color: Color(0xFF231836),
                  border: Border(
                    bottom: BorderSide(color: Color(0xFF382954), width: 1),
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFD700).withValues(alpha: 0.15),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.headset_mic_rounded,
                        color: Color(0xFFFFD700),
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Contact Us',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          Text(
                            'We\'re here to help you 24/7',
                            style: TextStyle(
                              color: Colors.white54,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close_rounded,
                          color: Colors.white54, size: 20),
                    ),
                  ],
                ),
              ),

              // Content Body
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: _successResponse != null
                      ? _buildSuccessContent()
                      : _buildFormContent(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFormContent() {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Quick Support Channels
          Container(
            padding: const EdgeInsets.all(12),
            margin: const EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(
              color: const Color(0xFF211733),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFF382954)),
            ),
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _ContactChip(
                  icon: Icons.email_rounded,
                  label: 'Email',
                  subtitle: 'support@zentry.com',
                ),
                _ContactChip(
                  icon: Icons.chat_bubble_rounded,
                  label: 'WhatsApp',
                  subtitle: '+234 812 345',
                ),
                _ContactChip(
                  icon: Icons.access_time_filled_rounded,
                  label: 'Availability',
                  subtitle: '24/7 Active',
                ),
              ],
            ),
          ),

          if (_errorMessage != null) ...[
            Container(
              padding: const EdgeInsets.all(10),
              margin: const EdgeInsets.only(bottom: 14),
              decoration: BoxDecoration(
                color: const Color(0xFF3B151C),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFF8C1D2F)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.error_outline_rounded,
                      color: Color(0xFFFF8A80), size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _errorMessage!,
                      style: const TextStyle(
                          color: Color(0xFFFF8A80), fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
          ],

          _buildInputLabel('Your Name'),
          const SizedBox(height: 6),
          TextFormField(
            controller: _nameController,
            style: const TextStyle(color: Colors.white, fontSize: 13),
            decoration: _inputDecoration('Enter your full name', Icons.person_rounded),
            validator: (v) =>
                (v == null || v.trim().isEmpty) ? 'Name is required' : null,
          ),

          const SizedBox(height: 14),
          _buildInputLabel('Email Address'),
          const SizedBox(height: 6),
          TextFormField(
            controller: _emailController,
            keyboardType: TextInputType.emailAddress,
            style: const TextStyle(color: Colors.white, fontSize: 13),
            decoration:
                _inputDecoration('Enter your email', Icons.alternate_email_rounded),
            validator: (v) {
              if (v == null || v.trim().isEmpty) return 'Email is required';
              if (!v.contains('@') || !v.contains('.')) {
                return 'Enter a valid email address';
              }
              return null;
            },
          ),

          const SizedBox(height: 14),
          _buildInputLabel('Subject'),
          const SizedBox(height: 6),
          TextFormField(
            controller: _subjectController,
            style: const TextStyle(color: Colors.white, fontSize: 13),
            decoration: _inputDecoration('e.g., Prediction Question, Bug Report', Icons.subject_rounded),
            validator: (v) =>
                (v == null || v.trim().isEmpty) ? 'Subject is required' : null,
          ),

          const SizedBox(height: 14),
          _buildInputLabel('Message'),
          const SizedBox(height: 6),
          TextFormField(
            controller: _messageController,
            maxLines: 4,
            style: const TextStyle(color: Colors.white, fontSize: 13),
            decoration: _inputDecoration('Describe your issue or question...', Icons.message_rounded),
            validator: (v) {
              if (v == null || v.trim().isEmpty) return 'Message is required';
              if (v.trim().length < 5) return 'Message must be at least 5 characters';
              return null;
            },
          ),

          const SizedBox(height: 20),

          // Submit Button
          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton(
              onPressed: _isLoading ? null : _submit,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFFD700),
                foregroundColor: const Color(0xFF0D0B12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                elevation: 0,
              ),
              child: _isLoading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Color(0xFF0D0B12),
                      ),
                    )
                  : const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.send_rounded, size: 18),
                        SizedBox(width: 8),
                        Text(
                          'Submit Message',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w900,
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

  Widget _buildSuccessContent() {
    final res = _successResponse!;
    return Column(
      children: [
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: const BoxDecoration(
            color: Color(0xFF1E3A2B),
            shape: BoxShape.circle,
          ),
          child: const Icon(
            Icons.check_circle_rounded,
            color: Color(0xFF4CAF50),
            size: 48,
          ),
        ),
        const SizedBox(height: 16),
        const Text(
          'Message Sent Successfully!',
          style: TextStyle(
            color: Colors.white,
            fontSize: 17,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          res.message,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Colors.white70,
            fontSize: 12,
            height: 1.4,
          ),
        ),
        const SizedBox(height: 16),

        // Ticket ID Card
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: const Color(0xFF231836),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFFFFD700).withValues(alpha: 0.4)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text(
                'Support Ticket Reference: ',
                style: TextStyle(color: Colors.white54, fontSize: 12),
              ),
              Text(
                res.ticketId,
                style: const TextStyle(
                  color: Color(0xFFFFD700),
                  fontWeight: FontWeight.w900,
                  fontSize: 14,
                  letterSpacing: 1,
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 24),
        SizedBox(
          width: double.infinity,
          height: 44,
          child: ElevatedButton(
            onPressed: () => Navigator.of(context).pop(),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF2C2042),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text('Close'),
          ),
        ),
      ],
    );
  }

  Widget _buildInputLabel(String label) {
    return Text(
      label,
      style: const TextStyle(
        color: Colors.white70,
        fontSize: 12,
        fontWeight: FontWeight.w700,
      ),
    );
  }

  InputDecoration _inputDecoration(String hint, IconData icon) {
    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(color: Colors.white38, fontSize: 12),
      prefixIcon: Icon(icon, color: Colors.white38, size: 18),
      filled: true,
      fillColor: const Color(0xFF231836),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFF3B2C57)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFF3B2C57)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFFFFD700), width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFFFF5252)),
      ),
    );
  }
}

class _ContactChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final String subtitle;

  const _ContactChip({
    required this.icon,
    required this.label,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Icon(icon, color: const Color(0xFFFFD700), size: 18),
        const SizedBox(height: 4),
        Text(
          label,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w800,
            fontSize: 11,
          ),
        ),
        Text(
          subtitle,
          style: const TextStyle(
            color: Colors.white54,
            fontSize: 9,
          ),
        ),
      ],
    );
  }
}
