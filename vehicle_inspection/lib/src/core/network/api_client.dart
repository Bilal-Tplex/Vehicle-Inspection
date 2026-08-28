/// Transport contract for the backend.
///
/// The app is written against this interface, never against a concrete HTTP
/// library. Today it is satisfied by an in-memory mock; pointing the app at a
/// real server means writing one `HttpApiClient` and changing a single
/// provider — no repository, controller or widget changes.
abstract interface class ApiClient {
  Future<Map<String, dynamic>> get(
    String path, {
    Map<String, String>? query,
  });

  Future<Map<String, dynamic>> post(
    String path, {
    Map<String, dynamic>? body,
  });

  /// Multipart upload of a single file.
  ///
  /// Kept separate from [post] because uploads need different timeouts, retry
  /// behaviour and — in production — progress reporting.
  Future<Map<String, dynamic>> uploadFile(
    String path, {
    required String filePath,
    Map<String, String>? fields,
  });

  /// Sets or clears the bearer token used for subsequent calls.
  void setAuthToken(String? token);
}
