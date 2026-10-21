import 'package:flutter/material.dart';
import 'models/user_model.dart';
import 'payment_checkout_screen.dart';
import 'services/auth_service.dart';
import 'services/session_manager.dart';
import 'edit_profile_dialog.dart';
import 'change_password_dialog.dart';
import 'coin_shop_screen.dart';

class ProfileScreen extends StatefulWidget {
  final UserModel user;
  final VoidCallback onLogout;
  final ValueChanged<UserModel>? onUserUpdated;

  const ProfileScreen({
    super.key,
    required this.user,
    required this.onLogout,
    this.onUserUpdated,
  });

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  late UserModel _currentUser;
  String _vipProvider = 'paystack';
  bool _isProcessing = false;
  final AuthService _authService = AuthService();

  List<Map<String, dynamic>> _vipPlans = [];

  @override
  void initState() {
    super.initState();
    _currentUser = widget.user;
    _refreshProfile();
    _loadVipPlans();
  }

  String _vipPriceLabel(dynamic value) {
    final amount = value is num ? value.toDouble() : double.tryParse('$value');
    if (amount == null) return 'Price unavailable';
    final decimals = amount.truncateToDouble() == amount ? 0 : 2;
    return 'NGN ${amount.toStringAsFixed(decimals)}';
  }

  Future<void> _loadVipPlans() async {
    try {
      final data = await _authService.getPackages();
      final raw = data['vip_plans'];
      if (!mounted || raw is! List) return;
      final plans = raw.whereType<Map>().map((item) {
        final plan = Map<String, dynamic>.from(item);
        final days = (plan['duration_days'] as num?)?.toInt() ?? 0;
        return <String, dynamic>{
          ...plan,
          'days': days,
          'price_ngn': _vipPriceLabel(plan['price_ngn']),
          'period': '/ $days days',
          'badge': plan['description']?.toString().toUpperCase() ?? 'VIP',
          'highlight': false,
        };
      }).toList();
      if (plans.isNotEmpty) {
        plans[plans.length > 1 ? 1 : 0]['highlight'] = true;
      }
      setState(() => _vipPlans = plans);
    } catch (_) {}
  }

  Future<void> _refreshProfile() async {
    final token = await SessionManager.getAccessToken();
    if (token != null) {
      try {
        final updated = await _authService.getProfile(token);
        if (mounted) {
          setState(() => _currentUser = updated);
          await SessionManager.instance.updateUser(updated);
          widget.onUserUpdated?.call(updated);
        }
      } catch (_) {}
    }
  }

  void _openEditProfile() {
    showDialog(
      context: context,
      builder: (ctx) => EditProfileDialog(
        user: _currentUser,
        onProfileUpdated: (updated) {
          setState(() => _currentUser = updated);
          widget.onUserUpdated?.call(updated);
        },
      ),
    );
  }

  void _openChangePassword() {
    showDialog(
      context: context,
      builder: (ctx) => const ChangePasswordDialog(),
    );
  }

  void _openCoinShop() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (ctx) => CoinShopScreen(
          user: _currentUser,
          onUserUpdated: (updated) {
            setState(() => _currentUser = updated);
            widget.onUserUpdated?.call(updated);
          },
        ),
      ),
    );
  }

  Future<void> _handleVipSubscribe(Map<String, dynamic> plan) async {
    final token = await SessionManager.getAccessToken();
    if (!mounted) return;
    if (token == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please login to subscribe')),
      );
      return;
    }

    setState(() => _isProcessing = true);

    try {
      final res = await _authService.createCheckout(
        token,
        provider: _vipProvider,
        itemType: 'vip_plan',
        itemId: plan['id'] as String,
      );

      final checkoutUrl = res['checkout_url'] as String? ?? '';
      final reference = res['reference'] as String? ?? '';

      if (mounted) {
        setState(() => _isProcessing = false);
        _showVipCheckoutDialog(
          plan['tier'] as String,
          plan['price_ngn'] as String,
          checkoutUrl,
          reference,
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isProcessing = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('VIP Checkout error: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  void _showVipCheckoutDialog(
    String planName,
    String price,
    String checkoutUrl,
    String reference,
  ) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF190F2E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            const Icon(
              Icons.workspace_premium,
              color: Color(0xFFA855F7),
              size: 28,
            ),
            const SizedBox(width: 10),
            const Text(
              'VIP Subscription',
              style: TextStyle(color: Colors.white, fontSize: 18),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Plan: $planName',
              style: const TextStyle(color: Colors.white70, fontSize: 14),
            ),
            const SizedBox(height: 4),
            Text(
              'Price: $price',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Provider: ${_vipProvider.toUpperCase()}',
              style: const TextStyle(color: Color(0xFF6C5CE7), fontSize: 13),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.05),
                borderRadius: BorderRadius.circular(8),
              ),
              child: SelectableText(
                'Ref: $reference\nURL: $checkoutUrl',
                style: const TextStyle(color: Colors.white54, fontSize: 11),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Close', style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            onPressed: checkoutUrl.isEmpty
                ? null
                : () async {
                    Navigator.of(ctx).pop();
                    final completed = await PaymentCheckoutScreen.open(
                      context,
                      checkoutUrl: checkoutUrl,
                      title: 'VIP Payment',
                    );
                    if (completed == true && mounted) {
                      await _refreshProfile();
                    }
                  },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFA855F7),
              foregroundColor: Colors.white,
            ),
            child: const Text('Open Secure Checkout'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final displayName = _currentUser.fullName.isNotEmpty
        ? _currentUser.fullName
        : _currentUser.username;

    return Scaffold(
      backgroundColor: const Color(0xFF0F081C),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text(
          'MY PROFILE',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 18,
            letterSpacing: 1.2,
          ),
        ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.lock_reset, color: Colors.white70),
            onPressed: _openChangePassword,
            tooltip: 'Change Password',
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        child: Column(
          children: [
            // User Header Card
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF21133B), Color(0xFF150A2A)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.white12),
              ),
              child: Column(
                children: [
                  Stack(
                    alignment: Alignment.bottomRight,
                    children: [
                      CircleAvatar(
                        radius: 42,
                        backgroundColor: const Color(
                          0xFF6C5CE7,
                        ).withOpacity(0.3),
                        child: Text(
                          displayName.isNotEmpty
                              ? displayName[0].toUpperCase()
                              : 'U',
                          style: const TextStyle(
                            fontSize: 34,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                      ),
                      if (_currentUser.isVerified)
                        Container(
                          padding: const EdgeInsets.all(3),
                          decoration: const BoxDecoration(
                            color: Color(0xFF10B981),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.check,
                            color: Colors.white,
                            size: 14,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    displayName,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '@${_currentUser.username}',
                    style: const TextStyle(
                      color: Color(0xFFA855F7),
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _currentUser.email,
                    style: const TextStyle(color: Colors.white54, fontSize: 13),
                  ),
                  const SizedBox(height: 16),

                  // Quick Action Buttons (Edit, Change Password, Shop)
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      OutlinedButton.icon(
                        onPressed: _openEditProfile,
                        icon: const Icon(
                          Icons.edit,
                          size: 16,
                          color: Colors.white,
                        ),
                        label: const Text(
                          'Edit Profile',
                          style: TextStyle(color: Colors.white, fontSize: 13),
                        ),
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: Colors.white24),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 8,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      OutlinedButton.icon(
                        onPressed: _openCoinShop,
                        icon: const Icon(
                          Icons.shopping_bag,
                          size: 16,
                          color: Color(0xFFFFB800),
                        ),
                        label: const Text(
                          'Shop',
                          style: TextStyle(
                            color: Color(0xFFFFB800),
                            fontSize: 13,
                          ),
                        ),
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: Color(0xFFFFB800)),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 8,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // Stats Row Card (Coins, Tickets, Accuracy)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.04),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: Colors.white12),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _buildStatItem(
                    icon: Icons.monetization_on_rounded,
                    iconColor: const Color(0xFFFFB800),
                    label: 'Coins',
                    value: '${_currentUser.coins}',
                  ),
                  Container(width: 1, height: 36, color: Colors.white12),
                  _buildStatItem(
                    icon: Icons.confirmation_number_rounded,
                    iconColor: const Color(0xFF3B82F6),
                    label: 'Tickets',
                    value: '${_currentUser.tickets}',
                  ),
                  Container(width: 1, height: 36, color: Colors.white12),
                  _buildStatItem(
                    icon: Icons.track_changes_rounded,
                    iconColor: const Color(0xFF10B981),
                    label: 'Accuracy',
                    value: '${_currentUser.accuracy.toStringAsFixed(1)}%',
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // Wallet & Coin Shop CTA Card
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF2C1B4E), Color(0xFF1C0D38)],
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                ),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: const Color(0xFFFFB800).withOpacity(0.3),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      const Icon(
                        Icons.stars_rounded,
                        color: Color(0xFFFFB800),
                        size: 36,
                      ),
                      const SizedBox(width: 14),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'COIN BALANCE',
                            style: TextStyle(
                              color: Colors.white54,
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            '${_currentUser.coins} COINS',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  ElevatedButton(
                    onPressed: _openCoinShop,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFFFB800),
                      foregroundColor: Colors.black,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 10,
                      ),
                    ),
                    child: const Text(
                      'OPEN SHOP',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 28),

            // VIP Membership Section
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'VIP MEMBERSHIP',
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.1,
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: _currentUser.vipTier != 'none'
                        ? const Color(0xFFA855F7).withOpacity(0.2)
                        : Colors.white10,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: _currentUser.vipTier != 'none'
                          ? const Color(0xFFA855F7)
                          : Colors.white24,
                    ),
                  ),
                  child: Text(
                    _currentUser.vipTier != 'none'
                        ? 'VIP: ${_currentUser.vipTier.toUpperCase()}'
                        : 'STATUS: FREE',
                    style: TextStyle(
                      color: _currentUser.vipTier != 'none'
                          ? const Color(0xFFA855F7)
                          : Colors.white54,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Provider Selector for VIP
            Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    onTap: () => setState(() => _vipProvider = 'paystack'),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        vertical: 10,
                        horizontal: 8,
                      ),
                      decoration: BoxDecoration(
                        color: _vipProvider == 'paystack'
                            ? const Color(0xFF6C5CE7).withOpacity(0.2)
                            : Colors.white.withOpacity(0.04),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: _vipProvider == 'paystack'
                              ? const Color(0xFF6C5CE7)
                              : Colors.white12,
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.credit_card,
                            size: 16,
                            color: _vipProvider == 'paystack'
                                ? const Color(0xFF6C5CE7)
                                : Colors.white54,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'Paystack',
                            style: TextStyle(
                              color: _vipProvider == 'paystack'
                                  ? Colors.white
                                  : Colors.white54,
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: GestureDetector(
                    onTap: () => setState(() => _vipProvider = 'nowpayments'),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        vertical: 10,
                        horizontal: 8,
                      ),
                      decoration: BoxDecoration(
                        color: _vipProvider == 'nowpayments'
                            ? const Color(0xFF6C5CE7).withOpacity(0.2)
                            : Colors.white.withOpacity(0.04),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: _vipProvider == 'nowpayments'
                              ? const Color(0xFF6C5CE7)
                              : Colors.white12,
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.currency_bitcoin,
                            size: 16,
                            color: _vipProvider == 'nowpayments'
                                ? const Color(0xFF6C5CE7)
                                : Colors.white54,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'NOWPayments',
                            style: TextStyle(
                              color: _vipProvider == 'nowpayments'
                                  ? Colors.white
                                  : Colors.white54,
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // VIP Membership Cards List
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _vipPlans.length,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (context, index) {
                final plan = _vipPlans[index];
                final isHighlighted = plan['highlight'] == true;

                return Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    gradient: isHighlighted
                        ? const LinearGradient(
                            colors: [Color(0xFF2C1952), Color(0xFF1E103B)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          )
                        : null,
                    color: isHighlighted
                        ? null
                        : Colors.white.withOpacity(0.04),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                      color: isHighlighted
                          ? const Color(0xFFA855F7)
                          : Colors.white12,
                      width: isHighlighted ? 1.5 : 1,
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(
                                plan['tier'] as String,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 17,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: isHighlighted
                                      ? const Color(0xFFA855F7)
                                      : Colors.white12,
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  plan['badge'] as String,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 9,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              Text(
                                plan['price_ngn'] as String,
                                style: const TextStyle(
                                  color: Color(0xFFA855F7),
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              Text(
                                plan['period'] as String,
                                style: const TextStyle(
                                  color: Colors.white54,
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                      ElevatedButton(
                        onPressed: _isProcessing
                            ? null
                            : () => _handleVipSubscribe(plan),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: isHighlighted
                              ? const Color(0xFFA855F7)
                              : const Color(0xFF6C5CE7),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 10,
                          ),
                        ),
                        child: const Text(
                          'Subscribe',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
            const SizedBox(height: 32),

            // Logout Button
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () {
                  SessionManager.clearSession();
                  widget.onLogout();
                  Navigator.of(context).pop();
                },
                icon: const Icon(Icons.logout_rounded, color: Colors.redAccent),
                label: const Text(
                  'Log Out',
                  style: TextStyle(
                    color: Colors.redAccent,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                style: OutlinedButton.styleFrom(
                  side: BorderSide(color: Colors.redAccent.withOpacity(0.4)),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildStatItem({
    required IconData icon,
    required Color iconColor,
    required String label,
    required String value,
  }) {
    return Column(
      children: [
        Icon(icon, color: iconColor, size: 24),
        const SizedBox(height: 6),
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        Text(
          label,
          style: const TextStyle(color: Colors.white54, fontSize: 11),
        ),
      ],
    );
  }
}
