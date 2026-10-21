import 'package:flutter/material.dart';

class BrandLogo extends StatelessWidget {
  const BrandLogo({super.key, this.size = 128});
  final double size;

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      'assets/images/zentry_logo.jpg',
      width: size,
      height: size,
      fit: BoxFit.contain,
    );
  }
}

class RemoteOrFallbackImage extends StatelessWidget {
  const RemoteOrFallbackImage({
    super.key,
    required this.url,
    required this.fallback,
  });
  final String? url;
  final Widget fallback;

  @override
  Widget build(BuildContext context) {
    if (url == null || url!.isEmpty) return fallback;
    return Image.network(
      url!,
      fit: BoxFit.cover,
      width: double.infinity,
      height: double.infinity,
      errorBuilder: (_, _, _) => fallback,
      loadingBuilder: (_, child, progress) =>
          progress == null ? child : fallback,
    );
  }
}
