import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:predict/src/slip_agent_screen.dart';
import 'package:predict/src/services/slip_agent_service.dart';

Map<String, dynamic> conversation({
  bool ticket = false,
  bool booked = false,
}) => {
  'id': '12345678-abcd-4000-8000-123456789012',
  'version': 2,
  'state': {
    'messages': [
      {'role': 'assistant', 'text': 'Your ticket is ready for a follow-up.'},
    ],
    'active_ticket_ids': ticket ? ['ticket-1'] : <String>[],
    'tickets': [
      if (ticket)
        {
          'id': 'ticket-1',
          'title': 'My ticket',
          'total_odds': 1.35,
          'picks': [
            {
              'id': 'pick-1',
              'sport_id': 1,
              'home_team': 'Esbjerg',
              'away_team': 'Hvidovre',
              'market': 'Over/Under',
              'selection': 'Over 1.5',
              'odds': 1.35,
              'probability': null,
              'warning': 'Probability unavailable',
            },
          ],
          if (booked)
            'booking': {
              'booking_code': 'VERIFIED123',
              'platform': 'sportybetng',
              'item_count': 1,
              'requested_count': 1,
              'partial': false,
            },
        },
    ],
  },
};

class FakeAgentService extends SlipAgentService {
  Map<String, dynamic>? current;
  final requests = <Map<String, dynamic>>[];
  bool failNext = false;
  FakeAgentService({this.current}) : super(baseUrl: 'https://example.test');
  @override
  Future<List<Map<String, dynamic>>> listSessions() async => [?current];
  @override
  Future<Map<String, dynamic>> createSession() async =>
      current = conversation();
  @override
  Future<Map<String, dynamic>> getSession(String id) async => current!;
  @override
  Future<Map<String, dynamic>> sendTurn(
    String id,
    Map<String, dynamic> request,
  ) async {
    requests.add(
      Map<String, dynamic>.from(jsonDecode(jsonEncode(request)) as Map),
    );
    if (failNext) {
      failNext = false;
      throw const SlipAgentException(
        'Connection interrupted. Retry the same request.',
      );
    }
    current = conversation(
      ticket: true,
      booked: request['confirm_booking'] == true,
    );
    return {
      'session': current,
      'answer': 'Done',
      'needs_booking_confirmation': false,
    };
  }
}

void main() {
  testWidgets(
    'SlipIQ retains conversation context and shows unknown probability as a dash',
    (tester) async {
      final service = FakeAgentService(current: conversation(ticket: true));
      addTearDown(service.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: SlipAgentScreen(service: service)),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.text('Your ticket is ready for a follow-up.'),
        findsOneWidget,
      );
      expect(find.textContaining('Probability: \u2014'), findsOneWidget);
      expect(find.textContaining('Probability: 0%'), findsNothing);
      expect(find.textContaining('100 coins per AI request'), findsOneWidget);
      await tester.enterText(
        find.byKey(const Key('slipiq-message')),
        'Change over 1.5 to under 1.5',
      );
      await tester.tap(find.byKey(const Key('slipiq-send')));
      await tester.pumpAndSettle();
      expect(service.requests.single['version'], 2);
      expect(
        service.requests.single['message'],
        'Change over 1.5 to under 1.5',
      );
      expect(service.requests.single['confirm_booking'], false);
    },
  );
  testWidgets('Generate code confirms only the reviewed ticket', (
    tester,
  ) async {
    final service = FakeAgentService(current: conversation(ticket: true));
    addTearDown(service.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: SlipAgentScreen(service: service)),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Generate code (200 coins)'));
    await tester.pumpAndSettle();
    expect(service.requests.single['confirm_booking'], true);
    expect(service.requests.single['booking_ticket_ids'], ['ticket-1']);
    expect(find.text('SportyBet code: VERIFIED123'), findsOneWidget);
  });
  testWidgets(
    'A lost response retries the identical request without a second booking command',
    (tester) async {
      final service = FakeAgentService(current: conversation(ticket: true))
        ..failNext = true;
      addTearDown(service.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: SlipAgentScreen(service: service)),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Generate code (200 coins)'));
      await tester.pumpAndSettle();
      expect(find.text('Retry same request'), findsOneWidget);
      await tester.tap(find.text('Retry same request'));
      await tester.pumpAndSettle();
      expect(service.requests.length, 2);
      expect(service.requests[0], service.requests[1]);
      expect(find.text('SportyBet code: VERIFIED123'), findsOneWidget);
    },
  );
  testWidgets(
    'An attached screenshot is sent as image data and never grants booking permission',
    (tester) async {
      final service = FakeAgentService();
      addTearDown(service.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SlipAgentScreen(
              service: service,
              selectImage: () async => Uint8List.fromList([1, 2, 3]),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('slipiq-attach')));
      await tester.pumpAndSettle();
      expect(find.text('Screenshot attached'), findsOneWidget);
      await tester.tap(find.byKey(const Key('slipiq-send')));
      await tester.pumpAndSettle();
      expect(service.requests.single['image_base64'], base64Encode([1, 2, 3]));
      expect(service.requests.single['confirm_booking'], false);
      expect(service.requests.single.containsKey('booking_ticket_ids'), false);
      expect(find.text('Screenshot attached'), findsNothing);
    },
  );
}
