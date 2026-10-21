import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'services/fpl_duel_service.dart';

class CodeConvertSheet extends StatefulWidget {
  const CodeConvertSheet({super.key});

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => const CodeConvertSheet(),
    );
  }

  @override
  State<CodeConvertSheet> createState() => _CodeConvertSheetState();
}

class _CodeConvertSheetState extends State<CodeConvertSheet> {
  final FplDuelService _duelService = FplDuelService();
  final TextEditingController _codeController = TextEditingController();

  String _sourcePlatform = 'SportyBet';
  String _targetPlatform = 'MSport';
  bool _isConverting = false;
  Map<String, dynamic>? _result;
  String? _errorMessage;

  final List<String> _platforms = [
    'SportyBet',
    'MSport',
    '1xBet',
    'Bet9ja',
    'BetKing',
    '22Bet',
    'Paripesa',
    'MozzartBet',
  ];

  Future<void> _executeConvert() async {
    final code = _codeController.text.trim();
    if (code.isEmpty) return;

    setState(() {
      _isConverting = true;
      _errorMessage = null;
      _result = null;
    });

    try {
      // 1. Try real backend conversion
      final res = await _duelService.convertBetCode(
        from: _sourcePlatform.toLowerCase(),
        to: _targetPlatform.toLowerCase(),
        code: code,
      );

      final convertedCode = res['targetCode']?.toString().trim() ?? '';
      if (convertedCode.isEmpty) {
        throw Exception('The converter did not return a booking code.');
      }
      final totalGames = (res['totalGames'] as num?)?.toInt() ?? 0;
      final convertedOk = (res['convertedOk'] as num?)?.toInt() ?? 0;
      setState(() {
        _isConverting = false;
        _result = {
          'convertedCode': convertedCode,
          'totalGames': totalGames,
          'convertedOk': convertedOk,
          'gamesMapped': '$convertedOk/$totalGames selections converted',
        };
      });
    } catch (error) {
      if (mounted) {
        setState(() {
          _isConverting = false;
          _result = null;
          _errorMessage = error.toString().replaceFirst('Exception: ', '');
        });
      }
    }
  }

  void _swapPlatforms() {
    setState(() {
      final temp = _sourcePlatform;
      _sourcePlatform = _targetPlatform;
      _targetPlatform = temp;
      _result = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.88,
      ),
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      decoration: const BoxDecoration(
        color: Color(0xFF130A21),
        borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
        boxShadow: [
          BoxShadow(
            color: Colors.black87,
            blurRadius: 30,
            offset: Offset(0, -5),
          ),
        ],
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Drag handle
            Center(
              child: Container(
                width: 44,
                height: 5,
                margin: const EdgeInsets.only(bottom: 14),
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),

            // Header
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF00C6FF), Color(0xFF0072FF)],
                    ),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(
                    Icons.swap_horiz_rounded,
                    color: Colors.white,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Booking Code Converter',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      Text(
                        'Convert slips instantly between SportyBet, 1xBet, Bet9ja & MSport',
                        style: TextStyle(color: Colors.white60, fontSize: 11),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close_rounded, color: Colors.white60),
                ),
              ],
            ),

            const SizedBox(height: 20),

            // Platform Swap Row
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF1D0E32),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.white12),
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      // Source Bookmaker
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'FROM BOOKIE',
                              style: TextStyle(
                                color: Colors.white54,
                                fontSize: 10,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0xFF2B1449),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: Colors.white12),
                              ),
                              child: DropdownButtonHideUnderline(
                                child: DropdownButton<String>(
                                  value: _sourcePlatform,
                                  isExpanded: true,
                                  dropdownColor: const Color(0xFF23103D),
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w700,
                                  ),
                                  items: _platforms
                                      .map(
                                        (p) => DropdownMenuItem(
                                          value: p,
                                          child: Text(p),
                                        ),
                                      )
                                      .toList(),
                                  onChanged: (val) {
                                    if (val != null)
                                      setState(() => _sourcePlatform = val);
                                  },
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),

                      // Swap Button
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        child: InkWell(
                          onTap: _swapPlatforms,
                          borderRadius: BorderRadius.circular(20),
                          child: Container(
                            margin: const EdgeInsets.only(top: 16),
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: const Color(
                                0xFF00FF87,
                              ).withValues(alpha: 0.15),
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: const Color(
                                  0xFF00FF87,
                                ).withValues(alpha: 0.3),
                              ),
                            ),
                            child: const Icon(
                              Icons.swap_horiz_rounded,
                              color: Color(0xFF00FF87),
                              size: 20,
                            ),
                          ),
                        ),
                      ),

                      // Target Bookmaker
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'TO BOOKIE',
                              style: TextStyle(
                                color: Colors.white54,
                                fontSize: 10,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0xFF2B1449),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: Colors.white12),
                              ),
                              child: DropdownButtonHideUnderline(
                                child: DropdownButton<String>(
                                  value: _targetPlatform,
                                  isExpanded: true,
                                  dropdownColor: const Color(0xFF23103D),
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w700,
                                  ),
                                  items: _platforms
                                      .map(
                                        (p) => DropdownMenuItem(
                                          value: p,
                                          child: Text(p),
                                        ),
                                      )
                                      .toList(),
                                  onChanged: (val) {
                                    if (val != null)
                                      setState(() => _targetPlatform = val);
                                  },
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 16),

                  // Booking Code Input
                  TextField(
                    controller: _codeController,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.2,
                    ),
                    textCapitalization: TextCapitalization.characters,
                    decoration: InputDecoration(
                      labelText: 'Booking Code to Convert',
                      labelStyle: const TextStyle(
                        color: Colors.white54,
                        fontSize: 12,
                      ),
                      hintText: 'Enter a real booking code',
                      hintStyle: const TextStyle(color: Colors.white24),
                      prefixIcon: const Icon(
                        Icons.qr_code_rounded,
                        color: Color(0xFF00FF87),
                        size: 20,
                      ),
                      suffixIcon: IconButton(
                        icon: const Icon(
                          Icons.paste_rounded,
                          color: Color(0xFFFFD700),
                          size: 18,
                        ),
                        onPressed: () async {
                          final data = await Clipboard.getData('text/plain');
                          if (data?.text != null && data!.text!.isNotEmpty) {
                            setState(
                              () => _codeController.text = data.text!
                                  .trim()
                                  .toUpperCase(),
                            );
                          }
                        },
                      ),
                      filled: true,
                      fillColor: const Color(0xFF130922),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 12,
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: const BorderSide(color: Colors.white12),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: const BorderSide(color: Color(0xFF00FF87)),
                      ),
                    ),
                  ),

                  const SizedBox(height: 16),

                  // Convert Button
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: ElevatedButton.icon(
                      onPressed: _isConverting ? null : _executeConvert,
                      icon: _isConverting
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.black,
                              ),
                            )
                          : const Icon(Icons.transform_rounded, size: 18),
                      label: Text(
                        _isConverting
                            ? 'Converting Code...'
                            : 'Convert Booking Code Now',
                        style: const TextStyle(fontWeight: FontWeight.w900),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF00FF87),
                        foregroundColor: const Color(0xFF0D0B12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            if (_errorMessage != null) ...[
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.redAccent.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: Colors.redAccent.withValues(alpha: 0.3),
                  ),
                ),
                child: Text(
                  _errorMessage!,
                  style: const TextStyle(color: Colors.redAccent, fontSize: 12),
                ),
              ),
            ],

            // Result Display
            if (_result != null) ...[
              const SizedBox(height: 20),
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF281140), Color(0xFF160924)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: const Color(0xFF00FF87).withValues(alpha: 0.4),
                    width: 1.2,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'CONVERTED FOR $_targetPlatform'.toUpperCase(),
                          style: const TextStyle(
                            color: Color(0xFF00FF87),
                            fontSize: 11,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 0.5,
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(
                              0xFFFFD700,
                            ).withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            '${_result!['convertedOk']}/${_result!['totalGames']}',
                            style: const TextStyle(
                              color: Color(0xFFFFD700),
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'New Booking Code',
                                style: TextStyle(
                                  color: Colors.white54,
                                  fontSize: 11,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                _result!['convertedCode'] as String,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 22,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 1.2,
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton.filled(
                          onPressed: () {
                            Clipboard.setData(
                              ClipboardData(
                                text: _result!['convertedCode'] as String,
                              ),
                            );
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  'Code ${_result!['convertedCode']} copied!',
                                ),
                                backgroundColor: const Color(0xFF00FF87),
                              ),
                            );
                          },
                          icon: const Icon(
                            Icons.copy_rounded,
                            color: Colors.black,
                            size: 18,
                          ),
                          style: IconButton.styleFrom(
                            backgroundColor: const Color(0xFF00FF87),
                          ),
                        ),
                      ],
                    ),
                    const Divider(color: Colors.white12, height: 24),
                    Text(
                      _result!['gamesMapped'] as String,
                      style: const TextStyle(
                        color: Color(0xFF00FF87),
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
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
}
