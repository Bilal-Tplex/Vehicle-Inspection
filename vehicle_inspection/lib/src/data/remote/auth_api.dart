import '../../core/network/api_client.dart';
import '../../domain/entities/auth_session.dart';
import '../../domain/entities/evaluator.dart';

/// Identity endpoints.
///
/// Thin by design: it owns the request shape and the response parsing, nothing
/// else. Retry policy, caching and error translation belong to the repository.
class AuthApi {
  const AuthApi(this._client);

  final ApiClient _client;

  Future<AuthSession> login({
    required String email,
    required String password,
  }) async {
    final response = await _client.post(
      '/auth/login',
      body: {'email': email, 'password': password},
    );

    final issuedAt = DateTime.now();
    final expiresIn = (response['expiresIn'] as num?)?.toInt();

    return AuthSession(
      evaluator: Evaluator.fromJson(
        response['evaluator']! as Map<String, dynamic>,
      ),
      accessToken: response['accessToken']! as String,
      issuedAt: issuedAt,
      expiresAt:
          expiresIn == null ? null : issuedAt.add(Duration(seconds: expiresIn)),
    );
  }
}
