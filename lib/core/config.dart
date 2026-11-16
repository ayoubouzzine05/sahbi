/// Build-time configuration. Pass with `--dart-define=KEY=value`.
abstract final class AppConfig {
  /// Default backend base URL (user can change it in Settings).
  /// Empty means "not configured": the app shows that state honestly.
  static const backendUrl = String.fromEnvironment('SAHBI_BACKEND_URL');

  static const appVersion = String.fromEnvironment(
    'SAHBI_VERSION',
    defaultValue: '0.1.0',
  );

  /// Feature flags (all experimental features are off by default).
  static const wakeWordAvailable = false; // Porcupine not bundled in v1
  static const spotifyRemoteAvailable = false; // App Remote SDK not bundled
  static const bleAvailable = false; // no BLE plugin bundled in v1
}
