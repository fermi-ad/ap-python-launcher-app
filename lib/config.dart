/// Compile-time configuration for the app.
///
/// Use `--dart-define` to inject values at build/run time.
///
/// Example:
/// `flutter run -d web-server --dart-define=API_BASE_URL=http://localhost:8000/ ...`
class Config {
  /// Base URL for the launcher API.
  ///
  /// If empty, API requests are made relative to the current origin.
  static const String apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
  );
}
