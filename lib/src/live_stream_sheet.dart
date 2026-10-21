import 'package:flutter/material.dart';

import 'models/stream_model.dart';
import 'services/sports_service.dart';
import 'widgets/in_app_stream_player.dart';

class LiveStreamSheet extends StatelessWidget {
  final LiveStreamEventModel streamEvent;
  final String? matchTitle;
  final List<LiveStreamEventModel> allEvents;

  const LiveStreamSheet({
    super.key,
    required this.streamEvent,
    this.matchTitle,
    this.allEvents = const [],
  });

  static Future<void> show(
    BuildContext context, {
    required LiveStreamEventModel streamEvent,
    String? matchTitle,
    List<LiveStreamEventModel> allEvents = const [],
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => LiveStreamSheet(
        streamEvent: streamEvent,
        matchTitle: matchTitle,
        allEvents: allEvents,
      ),
    );
  }

  void _openInAppPlayer(BuildContext context) {
    Navigator.of(context).pop();
    InAppPlayerScreen.open(
      context,
      streamEvent: streamEvent,
      allEvents: allEvents,
      apiBaseUrl: SportsService().baseUrl,
    );
  }

  @override
  Widget build(BuildContext context) {
    final title = matchTitle?.isNotEmpty == true
        ? matchTitle!
        : streamEvent.displayTitle;
    final servers = streamEvent.playbackSources;
    final hasServers = servers.isNotEmpty;

    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF140F1D),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        border: Border(top: BorderSide(color: Color(0xFFFFD700), width: 1.5)),
      ),
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 14,
        bottom: MediaQuery.of(context).viewInsets.bottom + 28,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Drag Handle
          Center(
            child: Container(
              width: 44,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Header with Live Badge & Category
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: Colors.redAccent,
                  borderRadius: BorderRadius.circular(6),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.redAccent.withValues(alpha: 0.35),
                      blurRadius: 8,
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.circle, size: 8, color: Colors.white),
                    const SizedBox(width: 5),
                    Text(
                      streamEvent.live ? 'LIVE BROADCAST' : 'SCHEDULED STREAM',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              if (streamEvent.category.isNotEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    streamEvent.category.toUpperCase(),
                    style: const TextStyle(
                      color: Color(0xFFFFD700),
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.close_rounded, color: Colors.white60),
                onPressed: () => Navigator.of(context).pop(),
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Match Title
          Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          if (streamEvent.channels.isNotEmpty) ...[
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.live_tv_rounded,
                  size: 15,
                  color: Colors.white54,
                ),
                const SizedBox(width: 7),
                Expanded(
                  child: Text(
                    streamEvent.channels.join(' • '),
                    style: const TextStyle(
                      color: Colors.white60,
                      fontSize: 12,
                      height: 1.35,
                    ),
                  ),
                ),
              ],
            ),
          ],
          if (streamEvent.streamStatus.isNotEmpty) ...[
            const SizedBox(height: 4),
            Row(
              children: [
                Icon(
                  Icons.sensors_rounded,
                  size: 14,
                  color: streamEvent.streamStatus == 'hls_observed'
                      ? const Color(0xFF00E676)
                      : const Color(0xFFFFD700),
                ),
                const SizedBox(width: 6),
                Text(
                  'Feed Status: ${streamEvent.streamStatus.replaceAll('_', ' ').toUpperCase()}',
                  style: TextStyle(
                    color: streamEvent.streamStatus == 'hls_observed'
                        ? const Color(0xFF00E676)
                        : Colors.white70,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ],

          const SizedBox(height: 20),

          // Stream Sources Section
          if (!hasServers) ...[
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: const Color(0xFF1E142B),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFF352752)),
              ),
              child: const Row(
                children: [
                  Icon(Icons.info_outline, color: Color(0xFFFFD700), size: 24),
                  SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Live feed links are currently preparing. Please check back in a moment.',
                      style: TextStyle(color: Colors.white70, fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () => _openInAppPlayer(context),
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: const Text('Find Available Servers'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFFFD700),
                  foregroundColor: const Color(0xFF0D0B12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  textStyle: const TextStyle(fontWeight: FontWeight.bold),
                  padding: const EdgeInsets.symmetric(vertical: 13),
                ),
              ),
            ),
          ] else ...[
            if (hasServers) ...[
              Text(
                '${servers.length} playback ${servers.length == 1 ? 'server' : 'servers'} available',
                style: TextStyle(
                  color: Color(0xFFFFD700),
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.3,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Choose another server inside the player if the current one is slow.',
                style: TextStyle(color: Colors.white60, fontSize: 12),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () => _openInAppPlayer(context),
                  icon: const Icon(Icons.tv_rounded, size: 18),
                  label: const Text('Watch In App'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFFFD700),
                    foregroundColor: const Color(0xFF0D0B12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    textStyle: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                  ),
                ),
              ),
              const SizedBox(height: 8),
            ],
          ],
        ],
      ),
    );
  }
}
