class ApiException implements Exception {
  final String message;
  final int statusCode;

  const ApiException(this.message, {this.statusCode = 500});

  @override
  String toString() => 'ApiException($statusCode): $message';
}
