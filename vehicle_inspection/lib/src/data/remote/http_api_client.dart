import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../../core/constants/app_constants.dart';
import '../../core/error/exceptions.dart';
import '../../core/network/api_client.dart';
import '../../core/utils/app_logger.dart';

/// Talks to the real backend.
///
/// This is the whole cost of moving off the mock: one class implementing the
/// same [ApiClient] interface, plus a one-line provider override. No
/// repository, controller, screen or test changes — which was the point of
/// putting an interface here in the first place.
///
/// It deliberately throws the same exception types the mock does
/// ([OfflineException], [ApiException]), because the sync engine's retry policy
/// is built on telling those apart: an [OfflineException] means "the request
/// never left the device", while an [ApiException] carries the status code that
/// decides retryable from terminal.
class HttpApiClient implements ApiClient {
  HttpApiClient({
    String baseUrl = AppConstants.apiBaseUrl,
    Duration timeout = AppConstants.apiTimeout,
    http.Client? client,
  })  : _baseUrl = baseUrl.endsWith('/')
            ? baseUrl.substring(0, baseUrl.length - 1)
            : baseUrl,
        _timeout = timeout,
        _client = client ?? http.Client();

  final String _baseUrl;
  final Duration _timeout;
  final http.Client _client;

  String? _authToken;

  @override
  void setAuthToken(String? token) => _authToken = token;

  Map<String, String> get _headers => {
        'Accept': 'application/json',
        if (_authToken != null) 'Authorization': 'Bearer $_authToken',
      };

  Uri _uri(String path, [Map<String, String>? query]) =>
      Uri.parse('$_baseUrl$path').replace(
        queryParameters: (query == null || query.isEmpty) ? null : query,
      );

  @override
  Future<Map<String, dynamic>> get(
    String path, {
    Map<String, String>? query,
  }) =>
      _send(() => _client.get(_uri(path, query), headers: _headers));

  @override
  Future<Map<String, dynamic>> post(
    String path, {
    Map<String, dynamic>? body,
  }) =>
      _send(() => _client.post(
            _uri(path),
            headers: {..._headers, 'Content-Type': 'application/json'},
            body: jsonEncode(body ?? const <String, dynamic>{}),
          ));

  @override
  Future<Map<String, dynamic>> uploadFile(
    String path, {
    required String filePath,
    Map<String, String>? fields,
  }) async {
    final file = File(filePath);
    if (!file.existsSync()) {
      // Terminal, not retryable: the bytes are gone, so resending cannot help.
      throw const ApiException(
        'The photo file is no longer on this device.',
        statusCode: 400,
      );
    }

    final request = http.MultipartRequest('POST', _uri(path))
      ..headers.addAll(_headers)
      ..fields.addAll(fields ?? const {})
      ..files.add(await http.MultipartFile.fromPath('file', filePath));

    return _send(() async {
      final streamed = await request.send();
      return http.Response.fromStream(streamed);
    });
  }

  /// Runs a request and turns transport and status failures into the
  /// exceptions the sync engine understands.
  Future<Map<String, dynamic>> _send(
    Future<http.Response> Function() perform,
  ) async {
    final http.Response response;
    try {
      response = await perform().timeout(_timeout);
    } on SocketException catch (error) {
      // No route to the host: indistinguishable from being offline, and
      // treated the same way — queue it and try again later.
      throw OfflineException(error.message);
    } on http.ClientException catch (error) {
      throw OfflineException(error.message);
    } on TimeoutException {
      throw const ApiException('The server took too long to respond.',
          statusCode: 504);
    }

    if (response.statusCode >= 200 && response.statusCode < 300) {
      return _decode(response);
    }

    // Error responses are JSON by contract, but never assume: a proxy or a
    // crash can return HTML, and failing to parse must not mask the status.
    String message = 'Request failed (${response.statusCode})';
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is Map<String, dynamic>) {
        final error = decoded['error'];
        if (error is Map<String, dynamic> && error['message'] is String) {
          message = error['message'] as String;
        }
      }
    } catch (_) {
      /* keep the status-based message */
    }

    AppLogger.warn('${response.statusCode} $message', scope: 'api');
    throw ApiException(message, statusCode: response.statusCode);
  }

  Map<String, dynamic> _decode(http.Response response) {
    if (response.body.isEmpty) return const {};
    final decoded = jsonDecode(utf8.decode(response.bodyBytes));
    if (decoded is Map<String, dynamic>) return decoded;
    // Every endpoint this app calls returns an object; a bare array or scalar
    // means the contract has drifted.
    throw const ApiException('Unexpected response shape from the server.',
        statusCode: 502);
  }

  void dispose() => _client.close();
}
