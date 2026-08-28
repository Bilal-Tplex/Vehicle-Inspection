/// Domain-level description of something that went wrong.
///
/// Presentation code never sees raw exceptions or platform errors; the data
/// layer translates everything into one of these so the UI can render a
/// stable, user-facing message and decide whether a retry is worthwhile.
sealed class Failure implements Exception {
  const Failure({required this.message, this.cause});

  /// Message safe to display to the evaluator.
  final String message;

  /// Original error, kept for logging only.
  final Object? cause;

  /// Whether retrying the same operation could plausibly succeed.
  bool get isRetryable => false;

  @override
  String toString() => '$runtimeType($message)';
}

/// The device has no usable connection, or the request timed out.
class NetworkFailure extends Failure {
  const NetworkFailure({
    super.message = 'No internet connection.',
    super.cause,
  });

  @override
  bool get isRetryable => true;
}

/// The server was reached but answered with an error.
class ServerFailure extends Failure {
  const ServerFailure({
    required super.message,
    this.statusCode,
    super.cause,
  });

  final int? statusCode;

  /// 5xx and 429 are worth retrying; other 4xx responses are not — resending
  /// a malformed payload will fail exactly the same way.
  @override
  bool get isRetryable =>
      statusCode == null || statusCode! >= 500 || statusCode == 429;
}

/// Credentials were rejected, or the session expired.
class AuthFailure extends Failure {
  const AuthFailure({
    super.message = 'Invalid email or password.',
    super.cause,
  });
}

/// Local database or file-system operation failed.
class StorageFailure extends Failure {
  const StorageFailure({
    super.message = 'Could not save data on this device.',
    super.cause,
  });
}

/// User-supplied data did not pass validation.
class ValidationFailure extends Failure {
  const ValidationFailure({
    required super.message,
    this.fieldErrors = const {},
  });

  /// Field name to message, so a form can highlight the offending inputs.
  final Map<String, String> fieldErrors;
}

/// Camera, gallery or compression problem.
class MediaFailure extends Failure {
  const MediaFailure({
    super.message = 'Could not process the photo.',
    super.cause,
  });
}

/// Anything we did not anticipate.
class UnexpectedFailure extends Failure {
  const UnexpectedFailure({
    super.message = 'Something went wrong.',
    super.cause,
  });
}
