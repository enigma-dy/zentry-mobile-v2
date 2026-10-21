class AceChannelModel {
  final String name;
  final String infoHash;
  final int pid;

  const AceChannelModel({
    required this.name,
    required this.infoHash,
    this.pid = 0,
  });

  factory AceChannelModel.fromJson(Map<String, dynamic> json) {
    return AceChannelModel(
      name: json['name']?.toString() ?? '',
      infoHash: json['info_hash']?.toString() ?? '',
      pid: json['pid'] is num
          ? (json['pid'] as num).toInt()
          : int.tryParse(json['pid']?.toString() ?? '') ?? 0,
    );
  }

  String localStreamUrl({String host = '127.0.0.1', int port = 6878}) {
    return Uri(
      scheme: 'http',
      host: host,
      port: port,
      path: '/ace/getstream',
      queryParameters: {
        'infohash': infoHash,
        if (pid > 0) 'pid': pid.toString(),
      },
    ).toString();
  }

  String get aceUri => 'acestream://$infoHash';
}
