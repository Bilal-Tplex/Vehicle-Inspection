/// Thrown by the remote layer when the backend answers with a non-2xx status.
class ApiException implements Exception {
  const ApiException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => 'ApiException($statusCode, $message)';
}

/// Thrown by the remote layer when the device is offline.
class OfflineException implements Exception {
  const OfflineException([this.message = 'Device is offline']);

  final String message;

  @override
  String toString() => 'OfflineException($message)';
}

/// Thrown by the local layer when a database operation fails.
class LocalStorageException implements Exception {
  const LocalStorageException(this.message, {this.cause});

  final String message;
  final Object? cause;

  @override
  String toString() => 'LocalStorageException($message)';
}
