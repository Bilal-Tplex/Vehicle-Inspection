import 'package:flutter/material.dart';

import '../../domain/entities/item_status.dart';
import '../../domain/entities/sync_status.dart';

/// Semantic colours the checklist depends on.
///
/// Registered as a [ThemeExtension] rather than hard-coded in widgets, so the
/// same status reads correctly in light and dark mode and a rebrand touches one
/// file. Every pair carries its own foreground colour to keep contrast legible
/// on a phone screen in daylight.
@immutable
class StatusColors extends ThemeExtension<StatusColors> {
  const StatusColors({
    required this.pass,
    required this.minorIssue,
    required this.fail,
    required this.notApplicable,
    required this.pending,
    required this.onStatus,
    required this.container,
  });

  final Color pass;
  final Color minorIssue;
  final Color fail;
  final Color notApplicable;
  final Color pending;

  /// Foreground used on top of a filled status colour.
  final Color onStatus;

  /// Subtle background used for the unselected state of a status chip.
  final Color container;

  Color forStatus(ItemStatus status) => switch (status) {
        ItemStatus.pass => pass,
        ItemStatus.minorIssue => minorIssue,
        ItemStatus.fail => fail,
        ItemStatus.notApplicable => notApplicable,
        ItemStatus.pending => pending,
      };

  Color forSync(SyncStatus status) => switch (status) {
        SyncStatus.synced => pass,
        SyncStatus.syncing => minorIssue,
        SyncStatus.pending => minorIssue,
        SyncStatus.failed => fail,
        SyncStatus.draftLocal => pending,
      };

  static const StatusColors light = StatusColors(
    pass: Color(0xFF1B873F),
    minorIssue: Color(0xFFB26A00),
    fail: Color(0xFFC62828),
    notApplicable: Color(0xFF5B6670),
    pending: Color(0xFF8A939B),
    onStatus: Colors.white,
    container: Color(0xFFF1F3F5),
  );

  static const StatusColors dark = StatusColors(
    pass: Color(0xFF4CAF6D),
    minorIssue: Color(0xFFE0A33E),
    fail: Color(0xFFEF6E6E),
    notApplicable: Color(0xFF9AA4AE),
    pending: Color(0xFF77828C),
    onStatus: Color(0xFF10151A),
    container: Color(0xFF23292F),
  );

  @override
  StatusColors copyWith({
    Color? pass,
    Color? minorIssue,
    Color? fail,
    Color? notApplicable,
    Color? pending,
    Color? onStatus,
    Color? container,
  }) =>
      StatusColors(
        pass: pass ?? this.pass,
        minorIssue: minorIssue ?? this.minorIssue,
        fail: fail ?? this.fail,
        notApplicable: notApplicable ?? this.notApplicable,
        pending: pending ?? this.pending,
        onStatus: onStatus ?? this.onStatus,
        container: container ?? this.container,
      );

  @override
  StatusColors lerp(ThemeExtension<StatusColors>? other, double t) {
    if (other is! StatusColors) return this;
    return StatusColors(
      pass: Color.lerp(pass, other.pass, t)!,
      minorIssue: Color.lerp(minorIssue, other.minorIssue, t)!,
      fail: Color.lerp(fail, other.fail, t)!,
      notApplicable: Color.lerp(notApplicable, other.notApplicable, t)!,
      pending: Color.lerp(pending, other.pending, t)!,
      onStatus: Color.lerp(onStatus, other.onStatus, t)!,
      container: Color.lerp(container, other.container, t)!,
    );
  }
}

/// Convenience accessor so widgets read `context.statusColors` instead of
/// reaching through `Theme.of(context).extension<...>()` every time.
extension StatusColorsX on BuildContext {
  StatusColors get statusColors =>
      Theme.of(this).extension<StatusColors>() ?? StatusColors.light;
}

/// Application themes.
class AppTheme {
  const AppTheme._();

  static const Color _seed = Color(0xFF12507B);

  static ThemeData get light => _build(Brightness.light, StatusColors.light);
  static ThemeData get dark => _build(Brightness.dark, StatusColors.dark);

  static ThemeData _build(Brightness brightness, StatusColors statusColors) {
    final scheme = ColorScheme.fromSeed(
      seedColor: _seed,
      brightness: brightness,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: brightness == Brightness.light
          ? const Color(0xFFF7F8FA)
          : const Color(0xFF12171C),
      extensions: [statusColors],
      appBarTheme: AppBarTheme(
        centerTitle: false,
        elevation: 0,
        scrolledUnderElevation: 2,
        backgroundColor: scheme.surface,
        foregroundColor: scheme.onSurface,
        titleTextStyle: TextStyle(
          fontSize: 19,
          fontWeight: FontWeight.w600,
          color: scheme.onSurface,
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.6)),
        ),
        color: scheme.surface,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surfaceContainerHighest.withValues(alpha: 0.4),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: scheme.outlineVariant),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: scheme.outlineVariant),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: scheme.primary, width: 1.6),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: scheme.error),
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          // Comfortably tappable with gloves on, which is the actual use case.
          // Height only: Size.fromHeight would demand infinite width and crush
          // any sibling when the button sits in a constrained slot.
          minimumSize: const Size(0, 52),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(0, 50),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
        ),
      ),
      dividerTheme: DividerThemeData(
        color: scheme.outlineVariant.withValues(alpha: 0.5),
        space: 1,
        thickness: 1,
      ),
      listTileTheme: const ListTileThemeData(
        contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      ),
    );
  }
}
