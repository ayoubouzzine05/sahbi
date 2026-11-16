import 'package:permission_handler/permission_handler.dart';

enum MicStatus { granted, denied, permanentlyDenied, restricted }

/// Abstraction so widget tests don't need the platform plugin.
abstract class MicPermission {
  Future<MicStatus> status();
  Future<MicStatus> request();
  Future<bool> openSettings();
}

class PluginMicPermission implements MicPermission {
  const PluginMicPermission();

  MicStatus _map(PermissionStatus s) {
    if (s.isGranted || s.isLimited) return MicStatus.granted;
    if (s.isPermanentlyDenied) return MicStatus.permanentlyDenied;
    if (s.isRestricted) return MicStatus.restricted;
    return MicStatus.denied;
  }

  @override
  Future<MicStatus> status() async => _map(await Permission.microphone.status);

  @override
  Future<MicStatus> request() async => _map(await Permission.microphone.request());

  @override
  Future<bool> openSettings() => openAppSettings();
}
