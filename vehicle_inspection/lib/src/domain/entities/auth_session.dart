import 'evaluator.dart';

/// A logged-in session, cached locally so the app opens straight into the
/// dashboard and keeps working with no connectivity.
class AuthSession {
  const AuthSession({
    required this.evaluator,
    required this.accessToken,
    required this.issuedAt,
    this.expiresAt,
  });

  final Evaluator evaluator;
  final String accessToken;
  final DateTime issuedAt;
  final DateTime? expiresAt;

  /// Sessions without an expiry never lapse. An expired session is still
  /// usable offline — the sync engine refreshes it when the device reconnects.
  bool isExpired({DateTime? now}) {
    final expiry = expiresAt;
    if (expiry == null) return false;
    return (now ?? DateTime.now()).isAfter(expiry);
  }

  Map<String, dynamic> toJson() => {
        'evaluator': evaluator.toJson(),
        'accessToken': accessToken,
        'issuedAt': issuedAt.toIso8601String(),
        'expiresAt': expiresAt?.toIso8601String(),
      };

  factory AuthSession.fromJson(Map<String, dynamic> json) => AuthSession(
        evaluator:
            Evaluator.fromJson(json['evaluator'] as Map<String, dynamic>),
        accessToken: json['accessToken'] as String,
        issuedAt: DateTime.parse(json['issuedAt'] as String),
        expiresAt: json['expiresAt'] == null
            ? null
            : DateTime.parse(json['expiresAt'] as String),
      );
}
