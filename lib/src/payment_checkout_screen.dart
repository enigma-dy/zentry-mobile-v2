import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:url_launcher/url_launcher.dart';

class PaymentCheckoutScreen extends StatefulWidget {
  final String checkoutUrl;
  final String title;

  const PaymentCheckoutScreen({
    super.key,
    required this.checkoutUrl,
    this.title = 'Secure Checkout',
  });

  static Future<bool?> open(
    BuildContext context, {
    required String checkoutUrl,
    String title = 'Secure Checkout',
  }) {
    return Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) =>
            PaymentCheckoutScreen(checkoutUrl: checkoutUrl, title: title),
      ),
    );
  }

  @override
  State<PaymentCheckoutScreen> createState() => _PaymentCheckoutScreenState();
}

class _PaymentCheckoutScreenState extends State<PaymentCheckoutScreen> {
  InAppWebViewController? _controller;
  double _progress = 0;
  String? _error;

  Uri? get _checkoutUri {
    final uri = Uri.tryParse(widget.checkoutUrl.trim());
    if (uri == null || !uri.hasAuthority) return null;
    if (uri.scheme != 'https' && uri.scheme != 'http') return null;
    return uri;
  }

  Future<NavigationActionPolicy> _handleNavigation(
    NavigationAction action,
  ) async {
    final target = action.request.url;
    final scheme = target?.scheme.toLowerCase() ?? '';
    if (scheme == 'https' || scheme == 'http' || scheme == 'about') {
      return NavigationActionPolicy.ALLOW;
    }

    if (target != null) {
      final uri = Uri.tryParse(target.toString());
      if (uri != null && await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    }
    return NavigationActionPolicy.CANCEL;
  }

  Future<bool> _handleBack() async {
    final controller = _controller;
    if (controller != null && await controller.canGoBack()) {
      await controller.goBack();
      return false;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final checkoutUri = _checkoutUri;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        if (await _handleBack() && context.mounted) {
          Navigator.of(context).pop(false);
        }
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF0F081C),
        appBar: AppBar(
          backgroundColor: const Color(0xFF190F2E),
          foregroundColor: Colors.white,
          leading: IconButton(
            tooltip: 'Back',
            icon: const Icon(Icons.arrow_back_rounded),
            onPressed: () async {
              if (await _handleBack() && context.mounted) {
                Navigator.of(context).pop(false);
              }
            },
          ),
          title: Text(widget.title),
          actions: [
            IconButton(
              tooltip: 'Reload',
              onPressed: () => _controller?.reload(),
              icon: const Icon(Icons.refresh_rounded),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text(
                'Done',
                style: TextStyle(
                  color: Color(0xFFFFD700),
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
          bottom: _progress < 1
              ? PreferredSize(
                  preferredSize: const Size.fromHeight(3),
                  child: LinearProgressIndicator(
                    value: _progress == 0 ? null : _progress,
                    minHeight: 3,
                    color: const Color(0xFFFFD700),
                    backgroundColor: Colors.white12,
                  ),
                )
              : null,
        ),
        body: checkoutUri == null
            ? const _CheckoutError(message: 'The checkout URL is invalid.')
            : Stack(
                fit: StackFit.expand,
                children: [
                  InAppWebView(
                    initialUrlRequest: URLRequest(
                      url: WebUri(checkoutUri.toString()),
                    ),
                    initialSettings: InAppWebViewSettings(
                      javaScriptEnabled: true,
                      domStorageEnabled: true,
                      databaseEnabled: true,
                      thirdPartyCookiesEnabled: true,
                      useShouldOverrideUrlLoading: true,
                      supportMultipleWindows: true,
                      javaScriptCanOpenWindowsAutomatically: true,
                      safeBrowsingEnabled: true,
                      mixedContentMode:
                          MixedContentMode.MIXED_CONTENT_NEVER_ALLOW,
                    ),
                    onWebViewCreated: (controller) => _controller = controller,
                    shouldOverrideUrlLoading: (controller, action) =>
                        _handleNavigation(action),
                    onCreateWindow: (controller, request) async {
                      final target = request.request.url;
                      if (target == null) return false;
                      final scheme = target.scheme.toLowerCase();
                      if (scheme == 'https' || scheme == 'http') {
                        await controller.loadUrl(
                          urlRequest: URLRequest(url: target),
                        );
                        return true;
                      }
                      final uri = Uri.tryParse(target.toString());
                      if (uri != null && await canLaunchUrl(uri)) {
                        await launchUrl(
                          uri,
                          mode: LaunchMode.externalApplication,
                        );
                        return true;
                      }
                      return false;
                    },
                    onProgressChanged: (controller, progress) {
                      if (!mounted) return;
                      setState(() => _progress = progress / 100);
                    },
                    onLoadStart: (controller, url) {
                      if (!mounted) return;
                      setState(() => _error = null);
                    },
                    onReceivedError: (controller, request, error) {
                      if (!mounted || request.isForMainFrame != true) return;
                      setState(() {
                        _progress = 1;
                        _error = 'Checkout could not load. Please retry.';
                      });
                    },
                  ),
                  if (_error != null)
                    _CheckoutError(
                      message: _error!,
                      onRetry: () {
                        setState(() => _error = null);
                        _controller?.reload();
                      },
                    ),
                ],
              ),
      ),
    );
  }
}

class _CheckoutError extends StatelessWidget {
  final String message;
  final VoidCallback? onRetry;

  const _CheckoutError({required this.message, this.onRetry});

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: const Color(0xFF0F081C),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.lock_outline_rounded,
                color: Color(0xFFFFD700),
                size: 44,
              ),
              const SizedBox(height: 14),
              Text(
                message,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white70),
              ),
              if (onRetry != null) ...[
                const SizedBox(height: 16),
                OutlinedButton.icon(
                  onPressed: onRetry,
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('Retry'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
