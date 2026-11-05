import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:predict/src/services/app_config.dart';

Future<void> initializeTestApi() async {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  rootBundle.evict('.env');
  messenger.setMockMessageHandler('flutter/assets', (message) async {
    if (message != null &&
        utf8.decode(
              message.buffer.asUint8List(
                message.offsetInBytes,
                message.lengthInBytes,
              ),
            ) ==
            '.env') {
      return ByteData.sublistView(
        Uint8List.fromList(utf8.encode('API_BASE_URL=https://backend.example')),
      );
    }
    return null;
  });
  try {
    await AppConfig.load();
  } finally {
    messenger.setMockMessageHandler('flutter/assets', null);
    rootBundle.evict('.env');
  }
}
