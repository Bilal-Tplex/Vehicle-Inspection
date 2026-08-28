import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'src/app/app.dart';
import 'src/core/utils/app_logger.dart';

void main() {
  // Binding must exist before the error handlers and orientation lock below.
  WidgetsFlutterBinding.ensureInitialized();

  // Anything that escapes a widget still reaches the log rather than vanishing.
  // In production this is where Crashlytics or Sentry would be installed.
  FlutterError.onError = (details) {
    AppLogger.error(
      details.exceptionAsString(),
      scope: 'flutter',
      error: details.exception,
      stackTrace: details.stack,
    );
    FlutterError.presentError(details);
  };

  // Inspectors work one-handed around a vehicle; landscape adds nothing.
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  runApp(
    const ProviderScope(
      child: VehicleInspectionApp(),
    ),
  );
}
