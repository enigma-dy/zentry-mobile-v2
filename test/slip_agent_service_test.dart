import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:predict/src/services/slip_agent_service.dart';

void main() {
  test(
    'agent API sends the exact version and idempotency key without automatic retries',
    () async {
      var calls = 0;
      final request = {
        'request_id': newSlipAgentRequestId(),
        'version': 3,
        'message': 'Split into two instead',
        'confirm_booking': false,
      };
      final api = SlipAgentService(
        baseUrl: 'https://example.test',
        client: MockClient((r) async {
          calls++;
          expect(
            r.url.path,
            '/api/v1/slip-analysis/agent/sessions/session-1/turns',
          );
          expect(jsonDecode(r.body), request);
          return http.Response(
            jsonEncode({
              'success': true,
              'data': {
                'session': {'id': 'session-1', 'version': 4},
                'answer': 'Done',
              },
            }),
            200,
          );
        }),
      );
      final result = await api.sendTurn('session-1', request);
      expect(result['session']['version'], 4);
      expect(calls, 1);
      expect(
        request['request_id'],
        matches(
          RegExp(
            r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
          ),
        ),
      );
    },
  );
  test(
    'agent API exposes conflict and unauthenticated errors without inventing empty success',
    () async {
      for (final code in [409, 401]) {
        var calls = 0;
        final api = SlipAgentService(
          baseUrl: 'https://example.test',
          client: MockClient((r) async {
            calls++;
            return http.Response(
              jsonEncode({
                'success': false,
                'message': 'Reload this conversation',
              }),
              code,
            );
          }),
        );
        await expectLater(
          api.sendTurn('id', {'request_id': 'same-id'}),
          throwsA(
            isA<SlipAgentException>().having((e) => e.status, 'status', code),
          ),
        );
        expect(calls, 1);
      }
    },
  );
  test('agent API rejects a malformed provider response', () async {
    final api = SlipAgentService(
      baseUrl: 'https://example.test',
      client: MockClient((r) async => http.Response('<html>error</html>', 502)),
    );
    await expectLater(api.listSessions(), throwsA(isA<SlipAgentException>()));
  });
}
