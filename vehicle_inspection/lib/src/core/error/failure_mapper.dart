import 'dart:async';
import 'dart:io';

import 'exceptions.dart';
import 'failures.dart';

/// Translates anything thrown below the repository line into a [Failure].
///
/// Having exactly one place that does this is what keeps `catch (e)` blocks out
/// of controllers and widgets: by the time an error reaches the UI it already
/// carries a display message and an honest answer to "should we retry?".
Failure mapToFailure(Object error) {
  if (error is Failure) return error;

  if (error is OfflineException) {
    return NetworkFailure(
      message: 'You are offline. Your work is saved on this device.',
      cause: error,
    );
  }

  if (error is ApiException) {
    return switch (error.statusCode) {
      401 || 403 => AuthFailure(
          message: 'Your session has expired. Please sign in again.',
          cause: error,
        ),
      // 422 is a contract violation, not something the evaluator can fix by
      // tapping retry, so it is surfaced as validation rather than a server
      // error.
      422 => ValidationFailure(message: error.message),
      _ => ServerFailure(
          message: error.message,
          statusCode: error.statusCode,
          cause: error,
        ),
    };
  }

  if (error is LocalStorageException) {
    return StorageFailure(
      message: 'Could not save to this device. Free up space and try again.',
      cause: error,
    );
  }

  if (error is SocketException || error is HttpException) {
    return NetworkFailure(
      message: 'Could not reach the server. Your work is saved on this device.',
      cause: error,
    );
  }

  if (error is TimeoutException) {
    return NetworkFailure(
      message: 'The server took too long to respond.',
      cause: error,
    );
  }

  if (error is FileSystemException) {
    return MediaFailure(
      message: 'Could not read the photo file.',
      cause: error,
    );
  }

  return UnexpectedFailure(cause: error);
}
