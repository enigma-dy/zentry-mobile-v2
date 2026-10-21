import 'package:flutter/material.dart';

import 'models/support_model.dart';
import 'services/support_service.dart';
import 'contact_us_dialog.dart';

class HelpScreen extends StatefulWidget {
  const HelpScreen({super.key});

  static void show(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const HelpScreen()),
    );
  }

  @override
  State<HelpScreen> createState() => _HelpScreenState();
}

class _HelpScreenState extends State<HelpScreen> {
  final _supportService = SupportService();
  final _searchController = TextEditingController();

  HelpInfo? _helpInfo;
  bool _isLoading = true;
  String? _errorMessage;
  String _selectedCategory = 'All';
  String _searchQuery = '';
  final Set<int> _expandedFaqIds = {};

  @override
  void initState() {
    super.initState();
    _loadHelpInfo();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadHelpInfo() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final info = await _supportService.getHelpInfo();
      if (mounted) {
        setState(() {
          _helpInfo = info;
          _isLoading = false;
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

  List<FAQItem> get _filteredFaqs {
    if (_helpInfo == null) return [];
    return _helpInfo!.faqs.where((faq) {
      final matchesCategory = _selectedCategory == 'All' ||
          faq.category.toLowerCase().contains(_selectedCategory.toLowerCase());
      final matchesSearch = _searchQuery.isEmpty ||
          faq.question.toLowerCase().contains(_searchQuery.toLowerCase()) ||
          faq.answer.toLowerCase().contains(_searchQuery.toLowerCase()) ||
          faq.category.toLowerCase().contains(_searchQuery.toLowerCase());
      return matchesCategory && matchesSearch;
    }).toList();
  }

  List<String> get _categories {
    if (_helpInfo == null) return ['All'];
    final cats = _helpInfo!.faqs.map((f) => f.category).toSet().toList();
    return ['All', ...cats];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0B12),
      appBar: AppBar(
        backgroundColor: const Color(0xFF140F1D),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_rounded, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text(
          'Help & Support Center',
          style: TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Search Bar & Filter Header
            Container(
              padding: const EdgeInsets.all(16),
              color: const Color(0xFF140F1D),
              child: Column(
                children: [
                  // Search Input
                  Container(
                    height: 46,
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    decoration: BoxDecoration(
                      color: const Color(0xFF231836),
                      borderRadius: BorderRadius.circular(23),
                      border: Border.all(color: const Color(0xFF382954)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.search_rounded,
                            color: Colors.white54, size: 20),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextField(
                            controller: _searchController,
                            style: const TextStyle(
                                color: Colors.white, fontSize: 13),
                            onChanged: (val) {
                              setState(() => _searchQuery = val.trim());
                            },
                            decoration: const InputDecoration(
                              hintText: 'Search help articles, questions...',
                              hintStyle: TextStyle(
                                  color: Colors.white38, fontSize: 12),
                              border: InputBorder.none,
                              isDense: true,
                            ),
                          ),
                        ),
                        if (_searchQuery.isNotEmpty)
                          GestureDetector(
                            onTap: () {
                              _searchController.clear();
                              setState(() => _searchQuery = '');
                            },
                            child: const Icon(Icons.close_rounded,
                                color: Colors.white54, size: 18),
                          ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 12),

                  // Category Filter Pills
                  if (!_isLoading && _helpInfo != null)
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: _categories.map((cat) {
                          final isSelected = cat == _selectedCategory;
                          return Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: ChoiceChip(
                              label: Text(cat),
                              selected: isSelected,
                              onSelected: (_) {
                                setState(() => _selectedCategory = cat);
                              },
                              selectedColor: const Color(0xFFFFD700),
                              backgroundColor: const Color(0xFF231836),
                              labelStyle: TextStyle(
                                color: isSelected
                                    ? const Color(0xFF0D0B12)
                                    : Colors.white70,
                                fontWeight: isSelected
                                    ? FontWeight.w900
                                    : FontWeight.w600,
                                fontSize: 12,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                                side: BorderSide(
                                  color: isSelected
                                      ? const Color(0xFFFFD700)
                                      : const Color(0xFF382954),
                                ),
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                ],
              ),
            ),

            // Main Body Content
            Expanded(
              child: _isLoading
                  ? const Center(
                      child: CircularProgressIndicator(
                        color: Color(0xFFFFD700),
                      ),
                    )
                  : _errorMessage != null
                      ? _buildErrorView()
                      : ListView(
                          padding: const EdgeInsets.all(16),
                          children: [
                            // Support Contact Info Banner
                            if (_helpInfo != null) _buildContactBanner(),

                            const SizedBox(height: 16),

                            const Padding(
                              padding: EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                              child: Text(
                                'Frequently Asked Questions',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ),

                            const SizedBox(height: 8),

                            if (_filteredFaqs.isEmpty)
                              _buildEmptyFaqView()
                            else
                              ..._filteredFaqs.map((faq) => _buildFaqItemCard(faq)),

                            const SizedBox(height: 24),

                            // Need more help banner
                            _buildNeedMoreHelpCard(),
                          ],
                        ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContactBanner() {
    final info = _helpInfo!.contactInfo;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1F172E),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFF352752)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: const BoxDecoration(
                  color: Color(0xFFFFD700),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.support_agent_rounded,
                    color: Color(0xFF0D0B12), size: 18),
              ),
              const SizedBox(width: 10),
              const Text(
                'Customer Support Channels',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                  fontSize: 14,
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFF4CAF50).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  info.hours,
                  style: const TextStyle(
                    color: Color(0xFF4CAF50),
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _buildSupportChannelItem(
                  Icons.email_rounded,
                  'Email Support',
                  info.email,
                ),
              ),
              Expanded(
                child: _buildSupportChannelItem(
                  Icons.phone_rounded,
                  'Phone Helpline',
                  info.phone,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSupportChannelItem(IconData icon, String title, String subtitle) {
    return Row(
      children: [
        Icon(icon, color: const Color(0xFFFFD700), size: 16),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(color: Colors.white54, fontSize: 10),
              ),
              Text(
                subtitle,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 11,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildFaqItemCard(FAQItem faq) {
    final isExpanded = _expandedFaqIds.contains(faq.id);
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF191226),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isExpanded ? const Color(0xFFFFD700).withValues(alpha: 0.5) : const Color(0xFF33264B),
        ),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          key: Key('faq-${faq.id}'),
          initiallyExpanded: isExpanded,
          onExpansionChanged: (expanded) {
            setState(() {
              if (expanded) {
                _expandedFaqIds.add(faq.id);
              } else {
                _expandedFaqIds.remove(faq.id);
              }
            });
          },
          tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          iconColor: const Color(0xFFFFD700),
          collapsedIconColor: Colors.white54,
          title: Text(
            faq.question,
            style: TextStyle(
              color: isExpanded ? const Color(0xFFFFD700) : Colors.white,
              fontWeight: FontWeight.w800,
              fontSize: 13,
            ),
          ),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              faq.category,
              style: const TextStyle(color: Colors.white38, fontSize: 10),
            ),
          ),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Text(
                faq.answer,
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 12,
                  height: 1.5,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNeedMoreHelpCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF261D3B), Color(0xFF45196A)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFFFD700).withValues(alpha: 0.3)),
      ),
      child: Column(
        children: [
          const Icon(Icons.support_agent_rounded,
              color: Color(0xFFFFD700), size: 36),
          const SizedBox(height: 8),
          const Text(
            'Still Have Questions?',
            style: TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Can\'t find what you\'re looking for? Send a message directly to our support team.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white70, fontSize: 12),
          ),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: () => ContactUsDialog.show(context),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFFFD700),
              foregroundColor: const Color(0xFF0D0B12),
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.mail_rounded, size: 18),
                SizedBox(width: 8),
                Text(
                  'Contact Support Team',
                  style: TextStyle(fontWeight: FontWeight.w900, fontSize: 13),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyFaqView() {
    return Container(
      padding: const EdgeInsets.all(32),
      alignment: Alignment.center,
      child: Column(
        children: [
          const Icon(Icons.search_off_rounded, color: Colors.white38, size: 40),
          const SizedBox(height: 12),
          const Text(
            'No matching FAQ articles found',
            style: TextStyle(color: Colors.white70, fontSize: 14, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          const Text(
            'Try searching for different keywords or select another category.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white38, fontSize: 11),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorView() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.error_outline_rounded, color: Colors.redAccent, size: 36),
          const SizedBox(height: 12),
          Text(
            _errorMessage ?? 'Failed to load help info',
            style: const TextStyle(color: Colors.white70, fontSize: 13),
          ),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: _loadHelpInfo,
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFFFD700)),
            child: const Text('Retry', style: TextStyle(color: Colors.black)),
          ),
        ],
      ),
    );
  }
}
