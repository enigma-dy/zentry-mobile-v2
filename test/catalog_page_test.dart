import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:predict/src/live_tv/catalog_page.dart';
import 'package:predict/src/live_tv/tv_catalog.dart';

void main() {
  final source = TvSource('HD', Uri.parse('https://example.com/embed/nhl'));
  final listings = [
    TvListing(
      id: 'nhl',
      name: 'NHL Network',
      category: 'hockey',
      league: 'NHL',
      status: 'live',
      alwaysLive: true,
      sources: [source],
    ),
    TvListing(
      id: 'football',
      name: 'Football match',
      category: 'football',
      league: 'League',
      status: 'live',
      sources: [TvSource('Main', Uri.parse('https://example.com/embed/match'))],
    ),
    TvListing(
      id: 'tomorrow',
      name: 'Tomorrow’s match',
      category: 'hockey',
      league: 'NHL',
      status: 'upcoming',
      startsAt: DateTime.utc(2026, 10, 24),
      sources: [source],
    ),
  ];

  testWidgets(
    'browses live listings, searches, and opens a channel without a URL field',
    (tester) async {
      TvListing? selected;
      TvSource? selectedSource;
      await tester.pumpWidget(
        MaterialApp(
          home: CatalogPage(
            loadCatalog: () async => listings,

            onWatch: (item, source) {
              selected = item;
              selectedSource = source;
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('On air now'), findsNothing);
      expect(find.text('YOUR FRONT ROW'), findsNothing);
      expect(find.text('Live TV'), findsNothing);
      expect(find.text('NHL Network'), findsOneWidget);
      expect(find.text('Tomorrow’s match'), findsNothing);
      expect(find.text('Video webpage URL'), findsNothing);
      await tester.enterText(find.byType(TextField), 'NHL');
      await tester.pumpAndSettle();
      expect(find.text('Football match'), findsNothing);
      await tester.tap(find.text('NHL Network'));
      expect(selected?.id, 'nhl');
      expect(selectedSource?.url, source.url);
      await tester.enterText(find.byType(TextField), '');
      await tester.tap(find.text('Schedule'));
      await tester.pumpAndSettle();
      expect(find.text('Tomorrow’s match'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('shows retry on guide failure and loads data after retry', (
    tester,
  ) async {
    var attempts = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: CatalogPage(
          loadCatalog: () async {
            if (attempts++ == 0) {
              throw const CatalogUnavailable('Guide unavailable');
            }
            return listings;
          },

          onWatch: (_, source) {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Guide unavailable'), findsOneWidget);
    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();
    expect(find.text('NHL Network'), findsOneWidget);
  });

  testWidgets('offers alternate servers before opening playback', (
    tester,
  ) async {
    TvSource? selected;
    final sd = TvSource('SD', Uri.parse('https://example.com/embed/nhl-sd'));
    await tester.pumpWidget(
      MaterialApp(
        home: CatalogPage(
          loadCatalog: () async => [
            TvListing(
              id: 'nhl',
              name: 'NHL Network',
              category: 'hockey',
              league: 'NHL',
              status: 'live',
              sources: [source, sd],
            ),
          ],

          onWatch: (_, source) => selected = source,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('NHL Network'));
    await tester.pumpAndSettle();
    expect(find.text('Choose a server'), findsOneWidget);
    await tester.tap(find.text('SD'));
    await tester.pumpAndSettle();
    expect(selected?.url, sd.url);
  });
}
