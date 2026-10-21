import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import 'auth_screen.dart';
import 'brand.dart';
import 'home_screen.dart';
import 'services/session_manager.dart';
import 'startup_content.dart';

class StartupGate extends StatefulWidget {
  const StartupGate({super.key, this.service = const StartupContentService()});
  final StartupContentService service;
  @override
  State<StartupGate> createState() => _StartupGateState();
}

class _StartupGateState extends State<StartupGate> {
  StartupContent _content = StartupContent.fallback;
  bool _showLogo = true;

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    final watch = Stopwatch()..start();
    final loaded = await widget.service.load();

    if (!mounted) return;
    setState(() => _content = loaded);
    final remaining = loaded.logoDuration - watch.elapsed;
    if (remaining > Duration.zero) await Future<void>.delayed(remaining);
    if (!mounted) return;
    setState(() {
      _showLogo = false;
    });
  }

  @override
  Widget build(BuildContext context) => AnimatedSwitcher(
    duration: const Duration(milliseconds: 500),
    child: _showLogo
        ? const LogoSplash(key: ValueKey('logo'))
        : SessionManager.instance.isLoggedIn
        ? const HomeScreen(key: ValueKey('home'))
        : OnboardingScreen(
            key: const ValueKey('onboarding'),
            content: _content,
          ),
  );
}

class LogoSplash extends StatelessWidget {
  const LogoSplash({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: const Color(0xFF0F081C),
    body: SafeArea(
      child: LayoutBuilder(
        builder: (_, constraints) {
          final size = (constraints.biggest.shortestSide * .34).clamp(
            112.0,
            190.0,
          );
          return Center(
            child: BrandLogo(size: size)
                .animate(onPlay: (c) => c.repeat(reverse: true))
                .scale(
                  begin: const Offset(0.95, 0.95),
                  end: const Offset(1.05, 1.05),
                  duration: 1800.ms,
                )
                .shimmer(
                  delay: 400.ms,
                  duration: 2.seconds,
                  color: const Color(0xFFFFEA79),
                ),
          );
        },
      ),
    ),
  );
}

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key, required this.content});
  final StartupContent content;
  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _controller = PageController();
  int _page = 0;

  void _finish() => Navigator.of(context).pushReplacement(
    PageRouteBuilder<void>(
      pageBuilder: (_, _, _) => const AuthScreen(),
      transitionsBuilder: (_, animation, _, child) =>
          FadeTransition(opacity: animation, child: child),
    ),
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final slides = widget.content.slides;
    return Scaffold(
      backgroundColor: const Color(0xFF0F081C),
      body: SafeArea(
        child: Column(
          children: [
            Align(
              alignment: Alignment.centerRight,
              child: Padding(
                padding: const EdgeInsets.only(right: 12),
                child: TextButton(
                  onPressed: _finish,
                  child: const Text(
                    'Skip',
                    style: TextStyle(
                      color: Color(0xFFFFD700),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ),
            Expanded(
              child: PageView.builder(
                controller: _controller,
                itemCount: slides.length,
                onPageChanged: (value) => setState(() => _page = value),
                itemBuilder: (_, index) => _SlideView(slide: slides[index]),
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(
                slides.length,
                (index) => AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: index == _page ? 24 : 8,
                  height: 8,
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  decoration: BoxDecoration(
                    color: index == _page
                        ? const Color(0xFFFFD700)
                        : Colors.white24,
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: SizedBox(
                  width: double.infinity,
                  height: 54,
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFFFFD700),
                      foregroundColor: const Color(0xFF0F081C),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(99),
                      ),
                    ),
                    onPressed: _page == slides.length - 1
                        ? _finish
                        : () => _controller.nextPage(
                            duration: const Duration(milliseconds: 350),
                            curve: Curves.easeOutCubic,
                          ),
                    child: Text(
                      _page == slides.length - 1 ? 'Get started' : 'Next',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SlideView extends StatelessWidget {
  const _SlideView({required this.slide});
  final StartupSlide slide;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final wide = constraints.maxWidth >= 700;
      final visual =
          ClipRRect(
                borderRadius: BorderRadius.circular(32),
                child: RemoteOrFallbackImage(
                  url: slide.imageUrl,
                  fallback: DecoratedBox(
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        colors: [Color(0xFF561A99), Color(0xFF220B44)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                    ),
                    child: Center(
                      child: Icon(
                        slide.icon,
                        size: wide ? 180 : 110,
                        color: const Color(0xFFFFD700),
                      ),
                    ),
                  ),
                ),
              )
              .animate()
              .fadeIn(duration: 500.ms)
              .scale(begin: const Offset(0.96, 0.96), end: const Offset(1, 1));
      final copy =
          Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: wide
                    ? CrossAxisAlignment.start
                    : CrossAxisAlignment.center,
                children: [
                  Text(
                    slide.title,
                    textAlign: wide ? TextAlign.left : TextAlign.center,
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.w900,
                      height: 1.1,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    slide.subtitle,
                    textAlign: wide ? TextAlign.left : TextAlign.center,
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: const Color(0xFFA898C8),
                      height: 1.5,
                    ),
                  ),
                ],
              )
              .animate()
              .fadeIn(duration: 500.ms, delay: 150.ms)
              .slideY(begin: 0.1, end: 0);
      return Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1000),
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: wide ? 48 : 24,
              vertical: 12,
            ),
            child: wide
                ? Row(
                    children: [
                      Expanded(child: visual),
                      const SizedBox(width: 52),
                      Expanded(child: copy),
                    ],
                  )
                : Column(
                    children: [
                      Expanded(child: visual),
                      const SizedBox(height: 26),
                      copy,
                    ],
                  ),
          ),
        ),
      );
    },
  );
}
