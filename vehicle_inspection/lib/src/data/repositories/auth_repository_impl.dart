import '../../core/error/failure_mapper.dart';
import '../../core/network/api_client.dart';
import '../../core/utils/app_logger.dart';
import '../../domain/entities/auth_session.dart';
import '../../domain/repositories/auth_repository.dart';
import '../local/session_store.dart';
import '../remote/auth_api.dart';

/// Sign-in backed by the API, with the session cached locally.
class AuthRepositoryImpl implements AuthRepository {
  const AuthRepositoryImpl({
    required AuthApi api,
    required SessionStore sessionStore,
    required ApiClient apiClient,
  })  : _api = api,
        _sessionStore = sessionStore,
        _apiClient = apiClient;

  final AuthApi _api;
  final SessionStore _sessionStore;
  final ApiClient _apiClient;

  @override
  Future<AuthSession?> restoreSession() async {
    final session = await _sessionStore.read();
    if (session == null) return null;

    // Re-arm the client so queued sync work can authenticate without waiting
    // for the evaluator to sign in again.
    _apiClient.setAuthToken(session.accessToken);

    if (session.isExpired()) {
      // Deliberately still returned: an expired token must not lock an
      // evaluator out of work already on the device. The sync engine will get
      // a 401 and surface a re-authentication prompt when it next runs.
      AppLogger.info('Restored an expired session', scope: 'auth');
    }
    return session;
  }

  @override
  Future<AuthSession> signIn({
    required String email,
    required String password,
  }) async {
    try {
      final session = await _api.login(
        email: email.trim().toLowerCase(),
        password: password,
      );
      await _sessionStore.write(session);
      _apiClient.setAuthToken(session.accessToken);
      AppLogger.info('Signed in as ${session.evaluator.email}', scope: 'auth');
      return session;
    } catch (error) {
      throw mapToFailure(error);
    }
  }

  @override
  Future<void> signOut() async {
    await _sessionStore.clear();
    _apiClient.setAuthToken(null);
    AppLogger.info('Signed out', scope: 'auth');
  }
}
