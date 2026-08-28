import 'dart:io';
import 'dart:math';

import '../../../core/error/exceptions.dart';
import '../../../core/network/api_client.dart';
import '../../../core/utils/app_logger.dart';
import 'network_simulator.dart';

/// In-memory stand-in for the future backend.
///
/// It speaks the same [ApiClient] contract a real HTTP client would, including
/// latency, auth headers, 4xx/5xx responses and multipart uploads, so the
/// repositories and the sync engine are exercising realistic failure modes
/// rather than a happy path that only works because there is no server.
///
/// Replacing this with a real client is a one-line provider change.
class MockApiClient implements ApiClient {
  MockApiClient({required NetworkSimulator simulator, Random? random})
      : _simulator = simulator,
        _random = random ?? Random();

  final NetworkSimulator _simulator;
  final Random _random;

  String? _authToken;

  /// Stands in for the server's database.
  final Map<String, Map<String, dynamic>> _inspections = {};
  final Map<String, String> _photoUrls = {};

  int _sequence = 0;

  static const String _testEmail = 'evaluator@test.com';
  static const String _testPassword = 'password123';

  @override
  void setAuthToken(String? token) => _authToken = token;

  @override
  Future<Map<String, dynamic>> get(
    String path, {
    Map<String, String>? query,
  }) async {
    await _simulateRoundTrip();

    if (path == '/templates') {
      // The bundled asset is the source of truth for now. A real backend would
      // return the current published templates here.
      return {'templates': <Map<String, dynamic>>[]};
    }
    if (path == '/inspections') {
      _requireAuth();
      return {'inspections': _inspections.values.toList()};
    }
    throw ApiException('Unknown endpoint: $path', statusCode: 404);
  }

  @override
  Future<Map<String, dynamic>> post(
    String path, {
    Map<String, dynamic>? body,
  }) async {
    await _simulateRoundTrip();

    switch (path) {
      case '/auth/login':
        return _login(body ?? const {});
      case '/inspections':
        return _submitInspection(body ?? const {});
      default:
        throw ApiException('Unknown endpoint: $path', statusCode: 404);
    }
  }

  @override
  Future<Map<String, dynamic>> uploadFile(
    String path, {
    required String filePath,
    Map<String, String>? fields,
  }) async {
    _requireAuth();
    // Uploads are slower than JSON calls; scale the delay with file size so the
    // progress states in the UI have something realistic to show.
    final file = File(filePath);
    if (!file.existsSync()) {
      throw ApiException('File no longer exists on device', statusCode: 400);
    }
    final bytes = await file.length();
    await _simulateRoundTrip(
      extra: Duration(milliseconds: (bytes / 12000).round().clamp(120, 2500)),
    );

    final photoId = fields?['photoId'] ?? _nextId('photo');
    final url = 'https://cdn.vehicle-inspection.example/photos/$photoId.jpg';
    _photoUrls[photoId] = url;
    AppLogger.debug('Mock upload complete: $url ($bytes bytes)', scope: 'api');
    return {'id': photoId, 'url': url, 'bytes': bytes};
  }

  // ---------------------------------------------------------------------------
  // Endpoints
  // ---------------------------------------------------------------------------

  Map<String, dynamic> _login(Map<String, dynamic> body) {
    final email = (body['email'] as String? ?? '').trim().toLowerCase();
    final password = body['password'] as String? ?? '';

    if (email != _testEmail || password != _testPassword) {
      throw const ApiException(
        'Invalid email or password.',
        statusCode: 401,
      );
    }

    return {
      'accessToken': 'mock-token-${_nextId('tok')}',
      'expiresIn': 60 * 60 * 24 * 30,
      'evaluator': {
        'id': 'ev-1001',
        'name': 'Ahmed Tariq',
        'email': _testEmail,
        'role': 'evaluator',
        'branch': 'Lahore Central',
      },
    };
  }

  Map<String, dynamic> _submitInspection(Map<String, dynamic> body) {
    _requireAuth();

    final localId = body['id'] as String?;
    if (localId == null || localId.isEmpty) {
      throw const ApiException('Missing inspection id', statusCode: 422);
    }

    // Idempotency: re-submitting after a timeout must not create a duplicate.
    // A real API would enforce this on the local id or an Idempotency-Key.
    final existing = _inspections[localId];
    if (existing != null) {
      return {'id': existing['remoteId'], 'status': 'accepted', 'duplicate': true};
    }

    final remoteId = 'srv-${_nextId('ins')}';
    _inspections[localId] = {...body, 'remoteId': remoteId};
    AppLogger.debug('Mock accepted inspection $localId -> $remoteId',
        scope: 'api');
    return {'id': remoteId, 'status': 'accepted', 'duplicate': false};
  }

  // ---------------------------------------------------------------------------
  // Simulation
  // ---------------------------------------------------------------------------

  void _requireAuth() {
    if (_authToken == null || _authToken!.isEmpty) {
      throw const ApiException('Not authenticated', statusCode: 401);
    }
  }

  Future<void> _simulateRoundTrip({Duration extra = Duration.zero}) async {
    final conditions = _simulator.value;
    if (conditions.offline) {
      // Fail fast: a device with no route to the host does not wait for a
      // timeout before giving up.
      throw const OfflineException();
    }

    await Future<void>.delayed(conditions.latency + extra);

    if (conditions.failureRate > 0 &&
        _random.nextDouble() < conditions.failureRate) {
      throw const ApiException(
        'The server is temporarily unavailable.',
        statusCode: 503,
      );
    }
  }

  String _nextId(String prefix) {
    _sequence++;
    return '$prefix${_sequence.toString().padLeft(4, '0')}';
  }
}
