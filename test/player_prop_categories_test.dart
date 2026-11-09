import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:predict/src/models/player_prop_categories.dart';
import 'package:predict/src/services/sports_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('each category filters the complete paginated feed on the server', () async {
    final urls = <Uri>[];
    final service = SportsService(baseUrl: 'https://api.test', client: MockClient((request) async {
      urls.add(request.url);
      return http.Response(jsonEncode({'success': true, 'data': {'items': [], 'total': 0, 'loading': false}}), 200);
    }));
    for (final category in playerPropCategories) {
      await service.getPlayerProps(statType: category.statType, date: '2026-11-08', page: 2);
      expect(urls.last.path, '/api/v1/predictions/player-props');
      expect(urls.last.queryParameters['stat_type'], category.statType.isEmpty ? null : category.statType);
      expect(urls.last.queryParameters['date'], '2026-11-08');
      expect(urls.last.queryParameters['page'], '2');
    }
    expect(urls.length, playerPropCategories.length);
    expect(urls.toSet().length, playerPropCategories.length);
  });
}
