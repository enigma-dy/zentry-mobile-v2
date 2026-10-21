import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:predict/src/home_screen.dart';
import 'package:predict/src/services/sports_service.dart';

final responseBody = File(
  'test/fixtures/home_fixtures_response.json',
).readAsStringSync();

http.Response auxiliaryResponse(http.Request request) {
  final path = request.url.path;
  dynamic data = <String, dynamic>{};
  if (path == '/api/v1/sports') {
    data = [
      {'id': 1, 'name': 'Football', 'key': 'football'},
    ];
  } else if (path == '/api/v1/fixtures/live' || path == '/api/v1/leagues') {
    data = [];
  } else if (path == '/api/v1/predictions') {
    data = {'data': []};
  }
  return http.Response(jsonEncode({'success': true, 'data': data}), 200);
}

Map<String, dynamic> fixtureJson(String id, String home, String away) => {
  'id': id,
  'sport_id': 1,
  'league_name': 'Premier League',
  'country': 'England',
  'home_team': home,
  'away_team': away,
  'normalized_home': home.toLowerCase(),
  'normalized_away': away.toLowerCase(),
  'match_time': '2026-10-16T18:00:00Z',
  'status': 'prematch',
  'home_score': 0,
  'away_score': 0,
  'period_scores': <String, dynamic>{},
  'stats': <String, dynamic>{},
};

http.Response fixturePage(int page, List<Map<String, dynamic>> fixtures) =>
    http.Response(
      jsonEncode({
        'success': true,
        'count': fixtures.length,
        'total': 2,
        'page': page,
        'page_size': 1,
        'total_pages': 2,
        'data': fixtures,
      }),
      200,
    );

void main() {
  test(
    'captured API response parses fixtures with empty countries and partial markets',
    () async {
      final service = SportsService(
        client: MockClient((_) async => http.Response(responseBody, 200)),
      );
      final result = await service.getFixturesPaginated(
        sportId: 1,
        date: '2026-10-09',
      );
      expect(result.success, isTrue);
      expect(result.data.single.homeTeam, 'Be1 Nfa');
      expect(result.data.single.country, isEmpty);
      expect(result.data.single.displayOdds, ['2.09', '3.50', '3.08']);
      expect(result.totalPages, greaterThan(1));
    },
  );

  test(
    'fixture timeouts remain errors rather than successful empty schedules',
    () async {
      final service = SportsService(
        client: MockClient((_) async {
          await Future<void>.delayed(const Duration(milliseconds: 20));
          return http.Response(responseBody, 200);
        }),
      );
      await expectLater(
        service.getFixturesPaginated(timeout: const Duration(milliseconds: 1)),
        throwsA(
          isA<SportsException>().having(
            (error) => error.message,
            'message',
            contains('too long'),
          ),
        ),
      );
    },
  );

  testWidgets(
    'home renders returned fixtures when the request takes more than six seconds',
    (tester) async {
      tester.view.physicalSize = const Size(360, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final fixturesResponse = Completer<http.Response>();
      var fixturesRequested = false;
      final service = SportsService(
        client: MockClient((request) async {
          if (request.url.path == '/api/v1/fixtures') {
            fixturesRequested = true;
            return fixturesResponse.future;
          }
          return auxiliaryResponse(request);
        }),
      );
      await tester.pumpWidget(
        MaterialApp(home: HomeScreen(sportsService: service)),
      );
      await tester.pump();
      expect(fixturesRequested, isTrue);
      await tester.pump(const Duration(seconds: 7));
      fixturesResponse.complete(http.Response(responseBody, 200));
      await tester.pumpAndSettle();
      expect(find.text('No Scheduled Fixtures'), findsNothing);
      expect(find.text('Be1 Nfa'), findsWidgets);
      expect(find.text('Dfk Dainava Alytus'), findsWidgets);
      expect(find.text('2.09'), findsWidgets);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'failed loads show a retryable error instead of no scheduled fixtures',
    (tester) async {
      tester.view.physicalSize = const Size(360, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final service = SportsService(
        client: MockClient((request) async {
          if (request.url.path == '/api/v1/fixtures') {
            throw TimeoutException('slow fixtures');
          }
          return auxiliaryResponse(request);
        }),
      );
      await tester.pumpWidget(
        MaterialApp(home: HomeScreen(sportsService: service)),
      );
      await tester.pumpAndSettle();
      expect(find.text('No Scheduled Fixtures'), findsNothing);
      expect(find.text('Unable to Load Fixtures'), findsOneWidget);
      expect(
        find.text('Fixtures took too long to load. Please try again.'),
        findsOneWidget,
      );
      expect(find.text('Refresh Matches'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'background refresh does not cancel an in-flight load-more request',
    (tester) async {
      tester.view.physicalSize = const Size(360, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final secondPage = Completer<http.Response>();
      final service = SportsService(
        client: MockClient((request) async {
          if (request.url.path == '/api/v1/fixtures') {
            final page =
                int.tryParse(request.url.queryParameters['page'] ?? '') ?? 1;
            if (page == 2) return secondPage.future;
            return fixturePage(1, [
              fixtureJson('page-1', 'Page One Home', 'Page One Away'),
            ]);
          }
          return auxiliaryResponse(request);
        }),
      );

      await tester.pumpWidget(
        MaterialApp(home: HomeScreen(sportsService: service)),
      );
      await tester.pumpAndSettle();
      expect(find.text('Page One Home'), findsWidgets);

      await tester.ensureVisible(find.text('Load more matches'));
      await tester.tap(find.text('Load more matches'));
      await tester.pump();
      expect(find.byType(CircularProgressIndicator), findsWidgets);

      // The home timer refreshes page one every 20 seconds. This used to
      // invalidate page two and leave the footer spinner running forever.
      await tester.pump(const Duration(seconds: 20));
      secondPage.complete(
        fixturePage(2, [
          fixtureJson('page-2', 'Page Two Home', 'Page Two Away'),
        ]),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Page Two Home'), findsWidgets);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
