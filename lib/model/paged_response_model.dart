class PagedResponseModel<T> {
  final List<T> items;
  final int page;
  final int totalPages;

  const PagedResponseModel({
    required this.items,
    required this.page,
    required this.totalPages,
  });

  factory PagedResponseModel.fromJson(
    Map<String, dynamic> json,
    T Function(Map<String, dynamic>) itemParser,
  ) {
    return PagedResponseModel(
      items: (json['items'] as List<dynamic>? ?? [])
          .map((e) => itemParser(e as Map<String, dynamic>))
          .toList(),
      page: json['page'] as int? ?? 1,
      totalPages: json['totalPages'] as int? ?? 1,
    );
  }

  bool get hasMore => page < totalPages;
}
