class PaginatedResponse<T> {
  final bool success;
  final int count;
  final int total;
  final int page;
  final int pageSize;
  final int totalPages;
  final List<T> data;

  const PaginatedResponse({
    required this.success,
    required this.count,
    required this.total,
    required this.page,
    required this.pageSize,
    required this.totalPages,
    required this.data,
  });

  factory PaginatedResponse.fromJson(
    Map<String, dynamic> json,
    T Function(Map<String, dynamic>) itemFromJson,
  ) {
    final list = json['data'];
    List<T> items = [];
    if (list is List) {
      for (final item in list) {
        if (item is Map) {
          try {
            items.add(itemFromJson(Map<String, dynamic>.from(item)));
          } catch (_) {
            // Tolerate individual malformed items without failing the entire page
          }
        }
      }
    }

    int? asInt(dynamic val) {
      if (val is int) return val;
      if (val is num) return val.toInt();
      if (val is String) return int.tryParse(val);
      return null;
    }

    final countVal = asInt(json['count']) ?? items.length;
    final totalVal = asInt(json['total']) ?? countVal;
    final pageVal = asInt(json['page']) ?? 1;
    final pageSizeVal = asInt(json['page_size']) ?? (countVal > 0 ? countVal : 20);
    final totalPagesVal = asInt(json['total_pages']) ?? (pageSizeVal > 0 ? (totalVal / pageSizeVal).ceil() : 1);

    return PaginatedResponse<T>(
      success: json['success'] as bool? ?? true,
      count: countVal,
      total: totalVal,
      page: pageVal,
      pageSize: pageSizeVal,
      totalPages: totalPagesVal,
      data: items,
    );
  }
}
