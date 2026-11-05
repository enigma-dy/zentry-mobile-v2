import 'dart:async';

bool predictionFeedHasContent(Map<String, dynamic> data) => [
  'items',
  'groups',
  'top_items',
].any((key) => data[key] is List && (data[key] as List).isNotEmpty);

/// Empty is a valid response. The server's loading flag controls background
/// polling; do not turn a sport without predictions into an endless spinner.
Future<Map<String, dynamic>> loadPredictionFeed(
  Future<Map<String, dynamic>> Function() request, {
  bool Function()? shouldContinue,
  bool Function(Object)? shouldRetryError,
  Future<void> Function(Duration)? wait,
}) async {
  final delay = wait ?? Future<void>.delayed;
  for (var attempt = 0; attempt < 2; attempt++) {
    if (shouldContinue?.call() == false) {
      return {'items': <dynamic>[], 'loading': false};
    }
    try {
      return await request();
    } catch (error) {
      if (attempt == 1 ||
          shouldContinue?.call() == false ||
          shouldRetryError?.call(error) == false) {
        rethrow;
      }
    }
    await delay(const Duration(milliseconds: 300));
  }
  return {'items': <dynamic>[], 'loading': false};
}

Map<String, dynamic> mergePredictionSections(
  Map<String, dynamic> general,
  Map<String, dynamic>? top, {
  required bool hasTop,
}) {
  final generalLoading =
      general['general_loading'] == true ||
      !general.containsKey('general_loading') && general['loading'] == true;
  final topLoading = hasTop && (top == null || top['loading'] == true);
  return {
    ...general,
    'general_loading': generalLoading,
    'top_items': top?['items'] ?? <dynamic>[],
    'top_loading': topLoading,
    'top_load_error': top?['top_load_error'] ?? top?['message'],
    'loading': generalLoading || topLoading,
    'retry_pending':
        generalLoading ||
        topLoading ||
        hasTop &&
            (top?['top_load_error'] != null ||
                top?['message'] != null && top?['message'] != ''),
  };
}

/// Optional Top data never delays or discards the general prediction list.
Future<Map<String, dynamic>> loadPredictionSections({
  required Future<Map<String, dynamic>> general,
  Future<Map<String, dynamic>>? top,
  void Function(Map<String, dynamic>)? onTopReady,
}) async {
  Map<String, dynamic>? topData;
  if (top != null) {
    final safeTop = top.then(
      (value) => value,
      onError: (Object error) => <String, dynamic>{
        'items': <dynamic>[],
        'loading': false,
        'top_load_error': error.toString(),
      },
    );
    unawaited(
      safeTop.then((value) {
        topData = value;
        onTopReady?.call(value);
      }),
    );
  }
  final data = await general;
  return mergePredictionSections(data, topData, hasTop: top != null);
}
