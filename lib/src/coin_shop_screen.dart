import 'package:flutter/material.dart';
import 'models/user_model.dart';
import 'payment_checkout_screen.dart';
import 'services/auth_service.dart';
import 'services/session_manager.dart';

class CoinShopScreen extends StatefulWidget {
  final UserModel user;
  final ValueChanged<UserModel>? onUserUpdated;

  const CoinShopScreen({super.key, required this.user, this.onUserUpdated});

  @override
  State<CoinShopScreen> createState() => _CoinShopScreenState();
}

class _CoinShopScreenState extends State<CoinShopScreen> {
  String _selectedProvider = 'paystack';
  late UserModel _currentUser;
  bool _isProcessing = false;
  final AuthService _authService = AuthService();

  List<Map<String, dynamic>> _coinPackages = [];

  @override
  void initState() {
    super.initState();
    _currentUser = widget.user;
    _refreshProfile();
    _loadPackages();
  }

  String _priceLabel(dynamic value) {
    final amount = value is num ? value.toDouble() : double.tryParse('$value');
    if (amount == null) return 'Price unavailable';
    final decimals = amount.truncateToDouble() == amount ? 0 : 2;
    return 'NGN ${amount.toStringAsFixed(decimals)}';
  }

  Future<void> _loadPackages() async {
    try {
      final data = await _authService.getPackages();
      final raw = data['coin_packages'];
      if (!mounted || raw is! List) return;
      final packages = raw.whereType<Map>().map((item) {
        final pkg = Map<String, dynamic>.from(item);
        return <String, dynamic>{
          ...pkg,
          'price_ngn': _priceLabel(pkg['price_ngn']),
          'badge': pkg['description']?.toString().toUpperCase() ?? 'COINS',
          'popular': false,
        };
      }).toList();
      if (packages.isNotEmpty) {
        packages[packages.length > 1 ? 1 : 0]['popular'] = true;
      }
      setState(() => _coinPackages = packages);
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

  Future<void> _handleBuyCoins(Map<String, dynamic> pkg) async {
    final token = await SessionManager.getAccessToken();
    if (!mounted) return;
    if (token == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please login to purchase coins')),
      );
      return;
    }

    setState(() => _isProcessing = true);

    try {
      final res = await _authService.createCheckout(
        token,
        provider: _selectedProvider,
        itemType: 'coin_package',
        itemId: pkg['id'] as String,
      );

      final checkoutUrl = res['checkout_url'] as String? ?? '';
      final reference = res['reference'] as String? ?? '';

      if (mounted) {
        setState(() => _isProcessing = false);
        _showCheckoutDialog(
          pkg['coins'].toString(),
          pkg['price_ngn'] as String,
          checkoutUrl,
          reference,
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isProcessing = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Checkout error: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  void _showCheckoutDialog(
    String coins,
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
            const Icon(Icons.stars_rounded, color: Color(0xFFFFB800), size: 28),
            const SizedBox(width: 10),
            const Text(
              'Payment Checkout',
              style: TextStyle(color: Colors.white, fontSize: 18),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Package: $coins Coins',
              style: const TextStyle(color: Colors.white70, fontSize: 14),
            ),
            const SizedBox(height: 4),
            Text(
              'Amount: $price',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Provider: ${_selectedProvider.toUpperCase()}',
              style: const TextStyle(color: Color(0xFFA855F7), fontSize: 13),
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
                      title: 'Coin Payment',
                    );
                    if (completed == true && mounted) {
                      await _refreshProfile();
                    }
                  },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF6C5CE7),
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
          'Coin Shop',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 20,
          ),
        ),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Balance Card
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF26134B), Color(0xFF180B33)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: const Color(0xFF6C5CE7).withOpacity(0.3),
                  width: 1.5,
                ),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF6C5CE7).withOpacity(0.15),
                    blurRadius: 20,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFB800).withOpacity(0.15),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: const Color(0xFFFFB800).withOpacity(0.4),
                      ),
                    ),
                    child: const Icon(
                      Icons.monetization_on,
                      color: Color(0xFFFFB800),
                      size: 36,
                    ),
                  ),
                  const SizedBox(width: 18),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'YOUR BALANCE',
                        style: TextStyle(
                          color: Colors.white54,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 1.2,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.baseline,
                        textBaseline: TextBaseline.alphabetic,
                        children: [
                          Text(
                            '${_currentUser.coins}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 32,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(width: 6),
                          const Text(
                            'Coins',
                            style: TextStyle(
                              color: Color(0xFFFFB800),
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 28),

            // Provider Selector
            const Text(
              'SELECT PAYMENT METHOD',
              style: TextStyle(
                color: Colors.white70,
                fontSize: 13,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.1,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    onTap: () => setState(() => _selectedProvider = 'paystack'),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        vertical: 14,
                        horizontal: 12,
                      ),
                      decoration: BoxDecoration(
                        color: _selectedProvider == 'paystack'
                            ? const Color(0xFF6C5CE7).withOpacity(0.2)
                            : Colors.white.withOpacity(0.04),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: _selectedProvider == 'paystack'
                              ? const Color(0xFF6C5CE7)
                              : Colors.white12,
                          width: _selectedProvider == 'paystack' ? 2 : 1,
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.credit_card_rounded,
                            color: _selectedProvider == 'paystack'
                                ? const Color(0xFF6C5CE7)
                                : Colors.white54,
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Paystack',
                            style: TextStyle(
                              color: _selectedProvider == 'paystack'
                                  ? Colors.white
                                  : Colors.white54,
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: GestureDetector(
                    onTap: () =>
                        setState(() => _selectedProvider = 'nowpayments'),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        vertical: 14,
                        horizontal: 12,
                      ),
                      decoration: BoxDecoration(
                        color: _selectedProvider == 'nowpayments'
                            ? const Color(0xFF6C5CE7).withOpacity(0.2)
                            : Colors.white.withOpacity(0.04),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: _selectedProvider == 'nowpayments'
                              ? const Color(0xFF6C5CE7)
                              : Colors.white12,
                          width: _selectedProvider == 'nowpayments' ? 2 : 1,
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.currency_bitcoin_rounded,
                            color: _selectedProvider == 'nowpayments'
                                ? const Color(0xFF6C5CE7)
                                : Colors.white54,
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'NOWPayments',
                            style: TextStyle(
                              color: _selectedProvider == 'nowpayments'
                                  ? Colors.white
                                  : Colors.white54,
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 28),

            // Packages Header
            const Text(
              'COIN PACKAGES',
              style: TextStyle(
                color: Colors.white70,
                fontSize: 13,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.1,
              ),
            ),
            const SizedBox(height: 14),

            // Packages Grid
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                childAspectRatio: 0.85,
                crossAxisSpacing: 14,
                mainAxisSpacing: 14,
              ),
              itemCount: _coinPackages.length,
              itemBuilder: (context, index) {
                final pkg = _coinPackages[index];
                final isPopular = pkg['popular'] == true;

                return Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: isPopular
                        ? const Color(0xFF231644)
                        : Colors.white.withOpacity(0.05),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                      color: isPopular
                          ? const Color(0xFF8B5CF6)
                          : Colors.white12,
                      width: isPopular ? 1.5 : 1,
                    ),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: isPopular
                                  ? const Color(0xFF8B5CF6)
                                  : Colors.white10,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              pkg['badge'] as String,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          const Icon(
                            Icons.stars_rounded,
                            color: Color(0xFFFFB800),
                            size: 20,
                          ),
                        ],
                      ),
                      Column(
                        children: [
                          Text(
                            '${pkg['coins']}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 28,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const Text(
                            'COINS',
                            style: TextStyle(
                              color: Colors.white54,
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: _isProcessing
                              ? null
                              : () => _handleBuyCoins(pkg),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: isPopular
                                ? const Color(0xFF6C5CE7)
                                : Colors.white.withOpacity(0.1),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                            elevation: 0,
                          ),
                          child: Text(
                            pkg['price_ngn'] as String,
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
