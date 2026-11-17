import 'dart:convert';

import '../../core/config.dart';

enum SttMode { auto, cloud, device, typed }

enum TtsMode { auto, cloud, device, off }

/// Every user setting, persisted as JSON in shared_preferences.
class AppSettings {
  const AppSettings({
    this.uiLocale = 'ar',
    this.replyLanguage = 'darija',
    this.darijaScript = 'arabic',
    this.sttMode = SttMode.auto,
    this.ttsMode = TtsMode.auto,
    this.deviceVoiceName,
    this.deviceVoiceLocale,
    this.cloudVoice = 'ar-MA-JamalNeural',
    this.speechRate = 0.5,
    this.pitch = 1.0,
    this.backendUrl = AppConfig.backendUrl,
    this.humor = 0.6,
    this.formality = 'casual',
    this.userName = '',
    this.idleEnabled = true,
    this.sendToAi = true,
    this.cloudVoiceEnabled = true,
    this.tapFaceToTalk = true,
    this.wakeWordEnabled = false,
    this.robotExperimental = false,
    this.debugUnlocked = false,
    this.micRationaleSeen = false,
  });

  final String uiLocale; // ar | fr | en
  final String replyLanguage; // darija | ar | fr | en
  final String darijaScript; // arabic | latin
  final SttMode sttMode;
  final TtsMode ttsMode;
  final String? deviceVoiceName;
  final String? deviceVoiceLocale;
  final String cloudVoice;

  /// flutter_tts rate: 0..1, 0.5 = normal on Android.
  final double speechRate;

  /// 0.5..2.0
  final double pitch;
  final String backendUrl;
  final double humor; // 0..1
  final String formality; // casual | polite
  final String userName;
  final bool idleEnabled;

  /// Privacy: allow sending chat text to the AI backend.
  final bool sendToAi;

  /// Privacy: allow cloud STT/TTS (audio/text sent to the backend).
  final bool cloudVoiceEnabled;
  final bool tapFaceToTalk;
  final bool wakeWordEnabled;
  final bool robotExperimental;
  final bool debugUnlocked;
  final bool micRationaleSeen;

  bool get latinDarija => darijaScript == 'latin';

  AppSettings copyWith({
    String? uiLocale,
    String? replyLanguage,
    String? darijaScript,
    SttMode? sttMode,
    TtsMode? ttsMode,
    String? deviceVoiceName,
    String? deviceVoiceLocale,
    String? cloudVoice,
    double? speechRate,
    double? pitch,
    String? backendUrl,
    double? humor,
    String? formality,
    String? userName,
    bool? idleEnabled,
    bool? sendToAi,
    bool? cloudVoiceEnabled,
    bool? tapFaceToTalk,
    bool? wakeWordEnabled,
    bool? robotExperimental,
    bool? debugUnlocked,
    bool? micRationaleSeen,
    bool clearDeviceVoice = false,
  }) {
    return AppSettings(
      uiLocale: uiLocale ?? this.uiLocale,
      replyLanguage: replyLanguage ?? this.replyLanguage,
      darijaScript: darijaScript ?? this.darijaScript,
      sttMode: sttMode ?? this.sttMode,
      ttsMode: ttsMode ?? this.ttsMode,
      deviceVoiceName: clearDeviceVoice
          ? null
          : (deviceVoiceName ?? this.deviceVoiceName),
      deviceVoiceLocale: clearDeviceVoice
          ? null
          : (deviceVoiceLocale ?? this.deviceVoiceLocale),
      cloudVoice: cloudVoice ?? this.cloudVoice,
      speechRate: speechRate ?? this.speechRate,
      pitch: pitch ?? this.pitch,
      backendUrl: backendUrl ?? this.backendUrl,
      humor: humor ?? this.humor,
      formality: formality ?? this.formality,
      userName: userName ?? this.userName,
      idleEnabled: idleEnabled ?? this.idleEnabled,
      sendToAi: sendToAi ?? this.sendToAi,
      cloudVoiceEnabled: cloudVoiceEnabled ?? this.cloudVoiceEnabled,
      tapFaceToTalk: tapFaceToTalk ?? this.tapFaceToTalk,
      wakeWordEnabled: wakeWordEnabled ?? this.wakeWordEnabled,
      robotExperimental: robotExperimental ?? this.robotExperimental,
      debugUnlocked: debugUnlocked ?? this.debugUnlocked,
      micRationaleSeen: micRationaleSeen ?? this.micRationaleSeen,
    );
  }

  Map<String, dynamic> toJson() => {
    'uiLocale': uiLocale,
    'replyLanguage': replyLanguage,
    'darijaScript': darijaScript,
    'sttMode': sttMode.name,
    'ttsMode': ttsMode.name,
    'deviceVoiceName': deviceVoiceName,
    'deviceVoiceLocale': deviceVoiceLocale,
    'cloudVoice': cloudVoice,
    'speechRate': speechRate,
    'pitch': pitch,
    'backendUrl': backendUrl,
    'humor': humor,
    'formality': formality,
    'userName': userName,
    'idleEnabled': idleEnabled,
    'sendToAi': sendToAi,
    'cloudVoiceEnabled': cloudVoiceEnabled,
    'tapFaceToTalk': tapFaceToTalk,
    'wakeWordEnabled': wakeWordEnabled,
    'robotExperimental': robotExperimental,
    'debugUnlocked': debugUnlocked,
    'micRationaleSeen': micRationaleSeen,
  };

  static AppSettings fromJson(Map<String, dynamic> j) {
    const d = AppSettings();
    T pick<T>(String k, T fallback) => j[k] is T ? j[k] as T : fallback;
    double num_(String k, double fallback) =>
        j[k] is num ? (j[k] as num).toDouble() : fallback;
    T enumOf<T extends Enum>(List<T> values, String k, T fallback) =>
        values.firstWhere((e) => e.name == j[k], orElse: () => fallback);
    String oneOf(String k, List<String> allowed, String fallback) =>
        allowed.contains(j[k]) ? j[k] as String : fallback;
    return AppSettings(
      uiLocale: oneOf('uiLocale', ['ar', 'fr', 'en'], d.uiLocale),
      replyLanguage: oneOf('replyLanguage', [
        'darija',
        'ar',
        'fr',
        'en',
      ], d.replyLanguage),
      darijaScript: oneOf('darijaScript', ['arabic', 'latin'], d.darijaScript),
      sttMode: enumOf(SttMode.values, 'sttMode', d.sttMode),
      ttsMode: enumOf(TtsMode.values, 'ttsMode', d.ttsMode),
      deviceVoiceName: j['deviceVoiceName'] as String?,
      deviceVoiceLocale: j['deviceVoiceLocale'] as String?,
      cloudVoice: oneOf('cloudVoice', [
        'ar-MA-JamalNeural',
        'ar-MA-MounaNeural',
      ], d.cloudVoice),
      speechRate: num_('speechRate', d.speechRate).clamp(0.1, 1.0),
      pitch: num_('pitch', d.pitch).clamp(0.5, 2.0),
      backendUrl: pick('backendUrl', d.backendUrl),
      humor: num_('humor', d.humor).clamp(0.0, 1.0),
      formality: oneOf('formality', ['casual', 'polite'], d.formality),
      userName: pick('userName', d.userName),
      idleEnabled: pick('idleEnabled', d.idleEnabled),
      sendToAi: pick('sendToAi', d.sendToAi),
      cloudVoiceEnabled: pick('cloudVoiceEnabled', d.cloudVoiceEnabled),
      tapFaceToTalk: pick('tapFaceToTalk', d.tapFaceToTalk),
      wakeWordEnabled: pick('wakeWordEnabled', d.wakeWordEnabled),
      robotExperimental: pick('robotExperimental', d.robotExperimental),
      debugUnlocked: pick('debugUnlocked', d.debugUnlocked),
      micRationaleSeen: pick('micRationaleSeen', d.micRationaleSeen),
    );
  }

  String encode() => jsonEncode(toJson());
  static AppSettings decode(String? s) {
    if (s == null || s.isEmpty) return const AppSettings();
    try {
      return fromJson(jsonDecode(s) as Map<String, dynamic>);
    } catch (_) {
      return const AppSettings();
    }
  }
}
