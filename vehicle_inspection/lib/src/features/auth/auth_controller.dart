import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../domain/entities/auth_session.dart';
import '../../domain/entities/evaluator.dart';

/// Owns the signed-in session.
///
/// [build] restores from secure storage without touching the network, so a
/// cold start with no signal lands on the dashboard rather than the login
/// screen — an evaluator who signed in yesterday must not be locked out of
/// their own drafts today.
class AuthController extends AsyncNotifier<AuthSession?> {
  @override
  Future<AuthSession?> build() {
    return ref.watch(authRepositoryProvider).restoreSession();
  }

  /// Returns `true` on success. The error, if any, is exposed through [state]
  /// so the form can render it inline.
  Future<bool> signIn({
    required String email,
    required String password,
  }) async {
    state = const AsyncValue<AuthSession?>.loading();
    final result = await AsyncValue.guard<AuthSession?>(
      () => ref.read(authRepositoryProvider).signIn(
            email: email,
            password: password,
          ),
    );
    state = result;
    return !result.hasError;
  }

  Future<void> signOut() async {
    await ref.read(authRepositoryProvider).signOut();
    state = const AsyncValue<AuthSession?>.data(null);
  }
}

final authControllerProvider =
    AsyncNotifierProvider<AuthController, AuthSession?>(AuthController.new);

/// The signed-in evaluator, or `null` when signed out.
final currentEvaluatorProvider = Provider<Evaluator?>(
  (ref) => ref.watch(authControllerProvider).value?.evaluator,
);
