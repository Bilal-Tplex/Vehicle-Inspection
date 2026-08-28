import '../entities/auth_session.dart';

/// Sign-in and session persistence.
///
/// Implementations throw an [AuthFailure] for bad credentials and a
/// [NetworkFailure] when the device cannot reach the identity service.
abstract interface class AuthRepository {
  /// Session cached from a previous launch, or `null` if nobody is signed in.
  ///
  /// Must not touch the network: the app has to open straight into the
  /// dashboard in a basement with no signal.
  Future<AuthSession?> restoreSession();

  /// Authenticates and persists the resulting session.
  Future<AuthSession> signIn({
    required String email,
    required String password,
  });

  /// Clears the cached session.
  ///
  /// Local inspections are deliberately left intact — signing out must never
  /// destroy work that has not reached the backend.
  Future<void> signOut();
}
