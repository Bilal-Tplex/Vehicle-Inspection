import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';

/// Minimal logging facade.
///
/// Kept behind an interface so it can be swapped for Crashlytics/Sentry in
/// production without touching call sites.
class AppLogger {
  const AppLogger._();

  static void debug(String message, {String scope = 'app'}) {
    if (kDebugMode) {
      developer.log(message, name: scope, level: 500);
    }
  }

  static void info(String message, {String scope = 'app'}) {
    developer.log(message, name: scope, level: 800);
  }

  static void warn(String message, {String scope = 'app', Object? error}) {
    developer.log(message, name: scope, level: 900, error: error);
  }

  static void error(
    String message, {
    String scope = 'app',
    Object? error,
    StackTrace? stackTrace,
  }) {
    developer.log(
      message,
      name: scope,
      level: 1000,
      error: error,
      stackTrace: stackTrace,
    );
  }
}
