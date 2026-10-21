import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:predict/src/models/stream_model.dart';
import 'package:predict/src/widgets/in_app_player_stub.dart';
import 'package:predict/src/widgets/in_app_stream_player.dart';

void main() {
  test('stream source reads an explicit adaptive format', () {
    final source = StreamSourceModel.fromJson({
      'url': 'https://media.example/manifest.mpd',
      'format': 'dash',
    });

    expect(source.format, 'dash');
  });

  test('event combines native and embed feeds as anonymous servers', () {
    final event = LiveStreamEventModel.fromJson({
      'id': 'event-1',
      'title': 'Home vs Away',
      'channels': ['Sports One', 'Sports Two'],
      'streams': [
        {'url': 'https://media.example/live.m3u8', 'format': 'hls'},
      ],
      'players': [
        {'embed_url': 'https://player.example/embed'},
      ],
    });

    expect(event.playbackSources, hasLength(2));
    expect(event.playbackSources.first.format, 'hls');
    expect(event.playbackSources.last.format, 'embed');
    expect(event.channels, ['Sports One', 'Sports Two']);
    expect(event.hasStreams, isTrue);
  });

  test('stream phases distinguish live, upcoming, and ended fixtures', () {
    final live = LiveStreamEventModel.fromJson({
      'id': 'live',
      'live': true,
      'stream_status': 'pending',
    });
    final upcoming = LiveStreamEventModel.fromJson({
      'id': 'upcoming',
      'live': false,
      'stream_status': 'upcoming',
    });
    final ended = LiveStreamEventModel.fromJson({
      'id': 'ended',
      'live': false,
      'stream_status': 'ended',
    });

    expect(live.phase, LiveStreamPhase.live);
    expect(upcoming.phase, LiveStreamPhase.upcoming);
    expect(ended.phase, LiveStreamPhase.ended);
    expect(ended.hasEnded, isTrue);
  });

  test('failed stream sources advance to the next untried server', () {
    expect(
      nextAvailableStreamSourceIndex(
        currentIndex: 0,
        sourceCount: 3,
        failedIndexes: {0},
      ),
      1,
    );
    expect(
      nextAvailableStreamSourceIndex(
        currentIndex: 1,
        sourceCount: 3,
        failedIndexes: {0, 1},
      ),
      2,
    );
    expect(
      nextAvailableStreamSourceIndex(
        currentIndex: 2,
        sourceCount: 3,
        failedIndexes: {0, 1, 2},
      ),
      -1,
    );
  });

  testWidgets('native adaptive player keeps waiting state without a feed', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: buildWebPlatformStreamView(
            streamUrl: '',
            viewId: 'test',
            isDirectStream: false,
            streamFormat: '',
            headers: const {},
          ),
        ),
      ),
    );

    expect(find.text('Preparing the in-app live feed'), findsOneWidget);
  });
}
