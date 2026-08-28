/// The signed-in inspector.
class Evaluator {
  const Evaluator({
    required this.id,
    required this.name,
    required this.email,
    this.role = 'evaluator',
    this.branch,
  });

  final String id;
  final String name;
  final String email;

  /// Reserved for the future admin dashboard, which will distinguish
  /// evaluators, reviewers and admins.
  final String role;
  final String? branch;

  /// Up to two letters for the dashboard avatar.
  String get initials {
    final parts =
        name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return _firstLetters(parts.first, 2);
    return _firstLetters(parts.first, 1) + _firstLetters(parts.last, 1);
  }

  static String _firstLetters(String value, int count) =>
      value.substring(0, count.clamp(0, value.length)).toUpperCase();

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'email': email,
        'role': role,
        'branch': branch,
      };

  factory Evaluator.fromJson(Map<String, dynamic> json) => Evaluator(
        id: json['id'] as String,
        name: json['name'] as String,
        email: json['email'] as String,
        role: json['role'] as String? ?? 'evaluator',
        branch: json['branch'] as String?,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Evaluator &&
          other.id == id &&
          other.name == name &&
          other.email == email &&
          other.role == role &&
          other.branch == branch;

  @override
  int get hashCode => Object.hash(id, name, email, role, branch);
}
