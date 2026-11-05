import 'dart:async';
import 'support/test_app_config.dart';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:predict/src/home_screen.dart';
import 'package:predict/src/match_detail_screen.dart';
import 'package:predict/src/models/user_model.dart';
import 'package:predict/src/services/session_manager.dart';
import 'package:predict/src/services/sports_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(initializeTestApi);
  testWidgets(
    'prediction tabs paginate, render General before slow Top, and surface prop failures',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      await SessionManager.instance.updateUser(
        UserModel.fromJson({
          'id': 'viewer',
          'username': 'viewer',
          'role': 'admin',
        }),
      );
      tester.view.physicalSize = const Size(430, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final requests = <Uri>[];
      final delayedTop = Completer<http.Response>();
      var topCalls = 0;
      var propCalls = 0;
      Map<String, dynamic> pick(String id) => {
        'id': id,
        'fixture_id': '9de626ac-15dd-40ab-9a72-eaa8a8d38dfb',
        'sport': 'Football',
        'sport_id': 1,
        'home_team': id,
        'away_team': 'Away',
        'league': 'League',
        'match_time': DateTime.now()
            .add(const Duration(hours: 1))
            .toIso8601String(),
        'market': 'Over/Under 1.5 Goals',
        'selection': 'Over 1.5',
        'probability': 90,
        'confidence': 90,
        'odds': 1.5,
        'status': 'pending',
      };
      final client = MockClient((request) async {
        requests.add(request.url);
        dynamic data = <String, dynamic>{};
        final path = request.url.path;
        if (path == '/api/v1/fixtures/9de626ac-15dd-40ab-9a72-eaa8a8d38dfb') {
          return http.Response(
            jsonEncode({'error': 'Fixture temporarily unavailable'}),
            503,
          );
        }
        if (path.endsWith('/sports')) {
          data = [
            {'id': 1, 'name': 'Football', 'key': 'football'},
          ];
        }
        if (path.endsWith('/fixtures') || path.endsWith('/fixtures/live')) {
          data = {'data': [], 'total_pages': 1};
        }
        if (path.endsWith('/predictions/popular')) {
          final page =
              int.tryParse(request.url.queryParameters['page'] ?? '1') ?? 1;
          data = {
            'items': [for (var i = 0; i < 20; i++) pick('Popular$page-$i')],
            'page': page,
            'total_pages': 2,
            'total': 40,
          };
        }
        if (path.endsWith('/predictions/player-props')) {
          propCalls++;
          if (propCalls > 1) {
            return http.Response(
              jsonEncode({
                'success': false,
                'message': 'Missing Authorization header',
              }),
              401,
            );
          }
          data = {
            'items': [],
            'total': 0,
            'loading': false,
            'message':
                'Player predictions are temporarily unavailable. Please retry shortly.',
          };
        }
        if (path.endsWith('/predictions/feed')) {
          final top = request.url.queryParameters['section'] == 'top';
          if (top) {
            topCalls++;
            if (topCalls == 1) return delayedTop.future;
            return http.Response(
              jsonEncode({
                'success': true,
                'data': {
                  'items': [pick('Top fixture')],
                  'total': 1,
                  'total_pages': 1,
                  'page': 1,
                  'loading': false,
                },
              }),
              200,
            );
          }
          final tag = request.url.queryParameters['tag'] ?? '';
          final under = tag.startsWith('Under ');
          data = {
            'items': [
              if (under)
                {
                  ...pick('$tag fixture'),
                  'market': 'Total Goals',
                  'selection': tag,
                  'odds': 0,
                  'sporty_event_id': 'sr:match:74173022',
                  'sporty_market_id': '18',
                  'sporty_outcome_id': '13',
                  'sporty_specifier': 'total=${tag.split(' ')[1]}',
                }
              else
                pick('General fixture'),
            ],
            'page': 1,
            'total_pages': 1,
            'total': 1,
          };
        }
        if (path.endsWith('/predictions')) data = {'data': []};
        return http.Response(jsonEncode({'success': true, 'data': data}), 200);
      });
      await tester.pumpWidget(
        MaterialApp(
          home: HomeScreen(
            sportsService: SportsService(
              baseUrl: 'https://backend.example',
              client: client,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('Predictions'),
        200,
        scrollable: find
            .byWidgetPredicate(
              (widget) =>
                  widget is Scrollable &&
                  widget.axisDirection == AxisDirection.right,
            )
            .first,
      );
      final predictions = find.text('Predictions').first;
      await Scrollable.ensureVisible(tester.element(predictions));
      await tester.pumpAndSettle();
      await tester.tap(predictions);
      await tester.pumpAndSettle();
      expect(find.textContaining('Popular1-0'), findsOneWidget);
      await tester.tap(find.textContaining('Popular1-0'));
      await tester.pumpAndSettle();
      expect(find.byType(MatchDetailScreen), findsOneWidget);
      expect(find.text('Popular1-0'), findsOneWidget);
      expect(find.text('Failed to load match details'), findsNothing);
      final detailRequest = requests.lastWhere(
        (uri) => uri.path.endsWith('/9de626ac-15dd-40ab-9a72-eaa8a8d38dfb'),
      );
      expect(detailRequest.queryParameters['refresh'], isNull);
      await tester.tap(find.byIcon(Icons.arrow_back));
      await tester.pumpAndSettle();
      expect(find.textContaining('Page 1 of'), findsNothing);
      await tester.drag(
        find.byType(SingleChildScrollView).last,
        const Offset(0, -10000),
      );
      await tester.pumpAndSettle();
      expect(
        requests.where(
          (url) =>
              url.path.endsWith('/predictions/popular') &&
              url.queryParameters['page'] == '2',
        ),
        hasLength(1),
      );
      expect(find.textContaining('Popular2-19'), findsOneWidget);
      await tester.drag(
        find.byType(SingleChildScrollView).last,
        const Offset(0, 10000),
      );
      await tester.pumpAndSettle();
      final football = find.byKey(const ValueKey('prediction-filter-Football'));
      final categories = find.byKey(const ValueKey('prediction-category-list'));
      await Scrollable.ensureVisible(tester.element(categories));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        football,
        150,
        scrollable: find
            .descendant(of: categories, matching: find.byType(Scrollable))
            .first,
      );

      await tester.pumpAndSettle();
      await tester.tap(football);
      await tester.pumpAndSettle();
      expect(find.textContaining('General fixture'), findsOneWidget);
      expect(find.textContaining('Top fixture'), findsNothing);
      delayedTop.complete(
        http.Response(
          jsonEncode({
            'success': true,
            'data': {
              'items': [],
              'total': 0,
              'total_pages': 1,
              'page': 1,
              'loading': false,
              'message': 'Top predictions are temporarily unavailable.',
            },
          }),
          200,
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.text('Top predictions are temporarily unavailable.'),
        findsOneWidget,
      );
      expect(find.textContaining('General fixture'), findsOneWidget);
      await tester.pump(const Duration(seconds: 11));
      await tester.pumpAndSettle();
      expect(topCalls, 2);
      expect(
        find.textContaining('Top fixture'),
        findsOneWidget,
        reason: requests
            .where((uri) => uri.path.contains('predictions'))
            .map((uri) => uri.toString())
            .join(' / '),
      );
      expect(find.textContaining('General fixture'), findsOneWidget);
      expect(
        tester.getTopLeft(find.textContaining('Top fixture')).dy,
        lessThan(tester.getTopLeft(find.textContaining('General fixture')).dy),
      );
      expect(find.text('Top'), findsOneWidget);
      for (final line in ['3.5', '4.5']) {
        final tab = find.text('Under $line');
        final marketTabs = find.byKey(const ValueKey('prediction-market-tabs'));
        await Scrollable.ensureVisible(tester.element(marketTabs));
        await tester.pumpAndSettle();
        await tester.scrollUntilVisible(
          tab,
          150,
          scrollable: find
              .descendant(of: marketTabs, matching: find.byType(Scrollable))
              .first,
        );
        await tester.pumpAndSettle();
        await Scrollable.ensureVisible(tester.element(tab));
        await tester.pumpAndSettle();
        await tester.tap(tab);
        await tester.pumpAndSettle();
        expect(
          find.textContaining('Under $line Goals fixture'),
          findsOneWidget,
        );
        final request = requests.lastWhere(
          (uri) => uri.path.endsWith('/predictions/feed'),
        );
        expect(request.queryParameters['tag'], 'Under $line Goals');
        expect(request.queryParameters['sport'], 'Football');
        expect(request.queryParameters['section'], 'general');
        expect(request.queryParameters['date'], isNotEmpty);
        final add = find.text('Add to Betslip');
        await Scrollable.ensureVisible(tester.element(add));
        await tester.pumpAndSettle();
        await tester.tap(add);
        await tester.pumpAndSettle();
        expect(find.text('Added to Betslip'), findsOneWidget);
      }
      final props = find.byKey(
        const ValueKey('prediction-filter-Player Props'),
      );
      await Scrollable.ensureVisible(tester.element(categories));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        props,
        -150,
        scrollable: find
            .descendant(of: categories, matching: find.byType(Scrollable))
            .first,
      );
      await tester.pumpAndSettle();
      await tester.tap(props);
      await tester.pumpAndSettle();
      expect(
        find.text(
          'Player predictions are temporarily unavailable. Please retry shortly.',
        ),
        findsOneWidget,
      );
      expect(find.text('Preparing daily predictions'), findsNothing);
      expect(propCalls, 1);
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      expect(find.text('Could not load predictions'), findsOneWidget);
      expect(find.text('Missing Authorization header'), findsOneWidget);
      expect(propCalls, 2);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
  );
}
