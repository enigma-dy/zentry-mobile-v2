import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:predict/src/live_tv/tv_catalog.dart';
import 'package:predict/src/live_tv/watch_page.dart';

void main() {
  final a = TvSource('Server A', Uri.parse('https://a.test'));
  final b = TvSource('Server B', Uri.parse('https://b.test'));
  final listing = TvListing(
    id: 'match',
    name: 'Match',
    category: 'football',
    league: '',
    status: 'live',
    sources: [a, b],
  );
  testWidgets(
    'real startup errors try all servers without reopening the route',
    (tester) async {
      const channel = MethodChannel('stream_browser');
      final urls = <String>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
        call,
      ) async {
        if (call.method == 'resolve') {
          urls.add((call.arguments as Map)['url'] as String);
          throw PlatformException(code: 'offline');
        }
        return null;
      });
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          channel,
          null,
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: WatchPage(listing: listing, initialSource: a),
        ),
      );
      await tester.pumpAndSettle();
      expect(urls, [a.url.toString(), b.url.toString()]);
      expect(find.text('Retry servers'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'switches during playback, ignores old errors, retries exhausted servers',
    (tester) async {
      final callbacks = <VoidCallback>[];
      await tester.pumpWidget(
        MaterialApp(
          home: WatchPage(
            listing: listing,
            initialSource: a,
            playerBuilder: (context, source, failed, control) {
              callbacks.add(failed);
              return Scaffold(
                appBar: AppBar(actions: [control]),
                body: Text('Playing ${source.name}'),
              );
            },
          ),
        ),
      );
      final stale = callbacks.last;
      await tester.tap(find.byTooltip('Switch server'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byWidgetPredicate(
          (widget) => widget is CheckedPopupMenuItem<int> && widget.value == 1,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Playing Server B'), findsOneWidget);
      stale();
      await tester.pump();
      expect(find.text('Playing Server B'), findsOneWidget);
      callbacks.last();
      await tester.pump();
      expect(find.text('Playing Server A'), findsOneWidget);
      callbacks.last();
      await tester.pump();
      expect(find.text('Retry servers'), findsOneWidget);
      await tester.tap(find.text('Retry servers'));
      await tester.pump();
      expect(find.text('Playing Server B'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('server menu remains available in landscape', (tester) async {
    tester.view.physicalSize = const Size(1200, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: WatchPage(
          listing: listing,
          initialSource: a,
          playerBuilder: (context, source, failed, control) => Scaffold(
            body: Align(alignment: Alignment.topRight, child: control),
          ),
        ),
      ),
    );
    await tester.tap(find.byTooltip('Switch server'));
    await tester.pumpAndSettle();
    expect(find.text('Server A'), findsOneWidget);
    expect(find.text('Server B'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
}
