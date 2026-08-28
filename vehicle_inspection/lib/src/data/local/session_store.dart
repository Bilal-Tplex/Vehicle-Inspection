import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../core/constants/app_constants.dart';
import '../../core/utils/app_logger.dart';
import '../../domain/entities/auth_session.dart';

/// Persists the signed-in session between launches.
///
/// The token goes into the platform keystore rather than shared preferences,
/// because an inspector's phone is a shared, field-used device. The evaluator
/// profile rides along in the same record so the dashboard can greet them by
/// name with no network call.
class SessionStore {
  const SessionStore(this._storage);

  final FlutterSecureStorage _storage;

  Future<AuthSession?> read() async {
    try {
      final raw = await _storage.read(key: AppConstants.sessionStorageKey);
      if (raw == null || raw.isEmpty) return null;
      return AuthSession.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (error, stackTrace) {
      // A corrupt or undecryptable record (e.g. after a device restore) must
      // not brick the app — treat it as "signed out" and move on.
      AppLogger.warn(
        'Discarding unreadable session',
        scope: 'auth',
        error: error,
      );
      AppLogger.debug('$stackTrace', scope: 'auth');
      await clear();
      return null;
    }
  }

  Future<void> write(AuthSession session) async {
    await _storage.write(
      key: AppConstants.sessionStorageKey,
      value: jsonEncode(session.toJson()),
    );
  }

  Future<void> clear() async {
    await _storage.delete(key: AppConstants.sessionStorageKey);
  }
}
