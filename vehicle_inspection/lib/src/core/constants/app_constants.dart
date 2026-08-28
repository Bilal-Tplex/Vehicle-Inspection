/// Values that tune app behaviour in one place.
///
/// Anything an admin dashboard would eventually own (grading bands, checklist
/// templates) lives in the domain layer instead — this file is limited to
/// client-side operational settings.
class AppConstants {
  const AppConstants._();

  static const String appName = 'Vehicle Inspection';

  // --- Backend --------------------------------------------------------------
  /// Base URL of the API and admin dashboard backend.
  ///
  /// `10.0.2.2` is how an Android emulator reaches the host machine's
  /// localhost. Override it for a physical handset, which needs the machine's
  /// LAN address:
  ///
  /// ```
  /// flutter run --dart-define=API_BASE_URL=http://192.168.1.20:4000/v1
  /// ```
  static const String apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://10.0.2.2:4000/v1',
  );

  /// Runs against the in-app mock backend instead of a real server.
  ///
  /// Useful for demoing the app with nothing else running:
  /// `flutter run --dart-define=USE_MOCK_API=true`.
  static const bool useMockApi = bool.fromEnvironment('USE_MOCK_API');

  static const Duration apiTimeout = Duration(seconds: 20);

  // --- Photo handling -------------------------------------------------------
  /// Longest edge of a stored photo, in pixels.
  static const int photoMaxDimension = 1600;
  static const int photoJpegQuality = 78;
  static const int photoMaxPerPoint = 5;
  static const String photoDirectoryName = 'inspection_photos';

  // --- Sync -----------------------------------------------------------------
  static const int syncMaxAttempts = 5;
  static const Duration syncBaseBackoff = Duration(seconds: 4);
  static const Duration syncMaxBackoff = Duration(minutes: 30);
  /// Guard against a burst of connectivity flaps triggering repeated drains.
  static const Duration syncDebounce = Duration(seconds: 2);

  // --- Storage keys ---------------------------------------------------------
  static const String sessionStorageKey = 'auth_session';
  static const String databaseName = 'vehicle_inspection.db';
  static const int databaseVersion = 1;
}
