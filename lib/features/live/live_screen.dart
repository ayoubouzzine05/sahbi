import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter_pcm_sound/flutter_pcm_sound.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:record/record.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../core/backend_client.dart';
import '../../core/providers.dart';
import '../../core/theme.dart';
import '../../l10n/app_localizations.dart';
import '../face/robot_face.dart';
import '../personality/emotion.dart';
import '../voice/wake_name.dart';
import 'live_session.dart';

enum LivePhase {
  permission,
  connecting,
  live,
  reconnecting,
  notConfigured,
  noCamera,
  offline,
  error,
  ended,
  timeLimit,
}

/// Live camera mode: the camera (≈1 frame/s) and the mic stream to Gemini
/// Live, which answers with voice. The phone is the robot's eyes.
class LiveScreen extends ConsumerStatefulWidget {
  const LiveScreen({super.key});

  /// Free-tier guard: sessions end after this long.
  static const maxSession = Duration(minutes: 10);

  @override
  ConsumerState<LiveScreen> createState() => _LiveScreenState();
}

class _LiveScreenState extends ConsumerState<LiveScreen>
    with WidgetsBindingObserver {
  LivePhase phase = LivePhase.connecting;
  CameraController? _cam;
  List<CameraDescription> _cameras = const [];
  int _camIndex = 0;
  LiveSession? _session;
  StreamSubscription<LiveEvent>? _events;
  final AudioRecorder _rec = AudioRecorder();
  StreamSubscription<Uint8List>? _micSub;
  Timer? _frameTimer;
  Timer? _limitTimer;
  Timer? _clock;
  bool _capturing = false;
  bool _muted = false;
  bool _speaking = false;
  bool _pcmReady = false;
  String _robotText = '';
  String _userText = '';
  bool _newRobotTurn = true;
  bool _newUserTurn = true;
  final Stopwatch _elapsed = Stopwatch();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final wake = ref.read(wakeNameProvider)..suspend();
    _wake = wake;
    unawaited(WakelockPlus.enable().catchError((_) {}));
    WidgetsBinding.instance.addPostFrameCallback((_) => _begin());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_teardown());
    unawaited(WakelockPlus.disable().catchError((_) {}));
    // ref is unusable after dispose; resume wake listening via the container.
    _wake?.resume();
    _rec.dispose();
    super.dispose();
  }

  WakeNameController? _wake;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      // Never keep the camera or mic in the background.
      if (phase == LivePhase.live || phase == LivePhase.reconnecting) {
        unawaited(_teardown());
        if (mounted) setState(() => phase = LivePhase.ended);
      }
    }
  }

  Future<void> _begin() async {
    if (!mounted) return;
    setState(() {
      phase = LivePhase.connecting;
      _robotText = '';
      _userText = '';
    });
    final net = ref.read(connectivityProvider).value;
    if (!net.hasNetwork) {
      setState(() => phase = LivePhase.offline);
      return;
    }
    if (!await _permissions()) return;
    try {
      _cameras = await availableCameras();
    } catch (_) {
      _cameras = const [];
    }
    if (_cameras.isEmpty) {
      if (mounted) setState(() => phase = LivePhase.noCamera);
      return;
    }
    final back = _cameras.indexWhere(
      (c) => c.lensDirection == CameraLensDirection.back,
    );
    _camIndex = back < 0 ? 0 : back;
    final camOk = await _openCamera();
    if (!camOk) {
      if (mounted) setState(() => phase = LivePhase.error);
      return;
    }
    final s = ref.read(settingsProvider);
    final LiveTokenInfo info;
    try {
      info = await ref
          .read(backendClientProvider)
          .liveToken(
            robotName: s.robotName.isEmpty ? null : s.robotName,
            userName: s.userName.trim().isEmpty ? null : s.userName.trim(),
            gender: s.voiceGender,
            replyLanguage: s.replyLanguage,
          );
    } on BackendException catch (e) {
      ref.read(errorLogProvider).add('live', '${e.code.name}: ${e.message}');
      if (mounted) {
        setState(
          () => phase = e.code == BackendErrorCode.notConfigured
              ? LivePhase.notConfigured
              : LivePhase.error,
        );
      }
      return;
    } catch (e) {
      ref.read(errorLogProvider).add('live', '$e');
      if (mounted) setState(() => phase = LivePhase.error);
      return;
    }
    if (!mounted) return;
    final session = LiveSession(
      wsUrl: info.wsUrl,
      token: info.token,
      model: info.model,
    );
    _session = session;
    _events = session.events.listen(_onEvent);
    await session.start();
  }

  Future<bool> _permissions() async {
    final l = L10n.of(context);
    final cam = await Permission.camera.status;
    final mic = await Permission.microphone.status;
    if (cam.isGranted && mic.isGranted) return true;
    if (!mounted) return false;
    setState(() => phase = LivePhase.permission);
    final s = ref.read(settingsProvider);
    if (!s.cameraRationaleSeen ||
        !(cam.isPermanentlyDenied || mic.isPermanentlyDenied)) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(l.cameraRationaleTitle),
          content: Text(l.cameraRationaleBody),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(l.micNotNow),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(l.micAllow),
            ),
          ],
        ),
      );
      ref
          .read(settingsProvider.notifier)
          .update((x) => x.copyWith(cameraRationaleSeen: true));
      if (ok != true) return _denied();
    }
    final res = await [Permission.camera, Permission.microphone].request();
    if (res.values.every((r) => r.isGranted)) return true;
    return _denied();
  }

  bool _denied() {
    if (mounted) setState(() => phase = LivePhase.permission);
    return false;
  }

  Future<bool> _openCamera() async {
    final old = _cam;
    _cam = null;
    if (mounted) setState(() {});
    await old?.dispose();
    final c = CameraController(
      _cameras[_camIndex],
      ResolutionPreset.medium,
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.jpeg,
    );
    try {
      await c.initialize();
    } catch (e) {
      ref.read(errorLogProvider).add('live.camera', '$e');
      await c.dispose();
      return false;
    }
    if (!mounted) {
      await c.dispose();
      return false;
    }
    setState(() => _cam = c);
    return true;
  }

  void _onEvent(LiveEvent e) {
    if (!mounted) return;
    switch (e) {
      case LiveReady():
        final wasReconnect = phase == LivePhase.reconnecting;
        setState(() => phase = LivePhase.live);
        if (!wasReconnect) unawaited(_startStreaming());
      case LiveAudio(:final pcm):
        unawaited(_play(pcm));
      case LiveTranscript(:final text, :final fromUser):
        setState(() {
          if (fromUser) {
            _userText = _newUserTurn ? text : '$_userText$text';
            _newUserTurn = false;
            _newRobotTurn = true;
          } else {
            _robotText = _newRobotTurn ? text : '$_robotText$text';
            _newRobotTurn = false;
            _newUserTurn = true;
          }
        });
      case LiveInterrupted():
        unawaited(_flushAudio());
      case LiveTurnComplete():
        _newRobotTurn = true;
      case LiveReconnecting():
        setState(() => phase = LivePhase.reconnecting);
      case LiveInternal():
        break;
      case LiveClosed(:final error, :final code, :final reason):
        if (phase == LivePhase.timeLimit || phase == LivePhase.ended) return;
        if (error != null || (code != null && code != 1000)) {
          ref
              .read(errorLogProvider)
              .add(
                'live',
                'closed ${code ?? ''} ${reason ?? ''} ${error ?? ''}',
              );
        }
        unawaited(_teardown(keepCamera: true));
        setState(
          () => phase = (error == null && (code == null || code == 1000))
              ? LivePhase.ended
              : LivePhase.error,
        );
    }
  }

  Future<void> _startStreaming() async {
    _elapsed
      ..reset()
      ..start();
    _clock = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
    _limitTimer = Timer(LiveScreen.maxSession, () async {
      await _teardown(keepCamera: true);
      if (mounted) setState(() => phase = LivePhase.timeLimit);
    });
    // Speaker output: 24 kHz mono PCM.
    try {
      await FlutterPcmSound.setup(sampleRate: 24000, channelCount: 1);
      await FlutterPcmSound.setFeedThreshold(2400);
      FlutterPcmSound.setFeedCallback((remaining) {
        if (remaining == 0 && _speaking && mounted) {
          setState(() => _speaking = false);
        }
      });
      _pcmReady = true;
    } catch (e) {
      ref.read(errorLogProvider).add('live.audio', '$e');
    }
    // Mic: 16 kHz mono PCM with echo cancellation so the robot does not
    // hear itself through the speaker.
    try {
      final stream = await _rec.startStream(
        const RecordConfig(
          encoder: AudioEncoder.pcm16bits,
          sampleRate: 16000,
          numChannels: 1,
          echoCancel: true,
          noiseSuppress: true,
          autoGain: true,
          androidConfig: AndroidRecordConfig(
            audioSource: AndroidAudioSource.voiceCommunication,
          ),
        ),
      );
      _micSub = stream.listen((chunk) {
        if (!_muted) _session?.sendAudio(chunk);
      });
    } catch (e) {
      ref.read(errorLogProvider).add('live.mic', '$e');
    }
    // Camera: one JPEG per second (the documented maximum).
    _frameTimer = Timer.periodic(const Duration(seconds: 1), (_) => _frame());
    unawaited(_frame());
  }

  Future<void> _frame() async {
    final c = _cam;
    final s = _session;
    if (_capturing || c == null || s == null || !s.ready) return;
    if (!c.value.isInitialized || c.value.isTakingPicture) return;
    _capturing = true;
    try {
      final x = await c.takePicture();
      final bytes = await x.readAsBytes();
      try {
        await File(x.path).delete();
      } catch (_) {}
      s.sendImage(bytes);
    } catch (e) {
      ref.read(errorLogProvider).add('live.frame', '$e');
    } finally {
      _capturing = false;
    }
  }

  Future<void> _play(Uint8List pcm) async {
    if (!_pcmReady || pcm.length < 2) return;
    final even = pcm.length.isEven ? pcm : pcm.sublist(0, pcm.length - 1);
    final copy = Uint8List.fromList(even);
    try {
      await FlutterPcmSound.feed(
        PcmArrayInt16(bytes: ByteData.view(copy.buffer)),
      );
      FlutterPcmSound.start();
      if (!_speaking && mounted) setState(() => _speaking = true);
    } catch (e) {
      ref.read(errorLogProvider).add('live.audio', '$e');
    }
  }

  /// Barge-in: drop whatever is still queued in the speaker.
  Future<void> _flushAudio() async {
    if (!_pcmReady) return;
    try {
      _pcmReady = false;
      await FlutterPcmSound.release();
      await FlutterPcmSound.setup(sampleRate: 24000, channelCount: 1);
      await FlutterPcmSound.setFeedThreshold(2400);
      _pcmReady = true;
    } catch (e) {
      ref.read(errorLogProvider).add('live.audio', '$e');
    }
    if (mounted) setState(() => _speaking = false);
  }

  Future<void> _teardown({bool keepCamera = false}) async {
    _frameTimer?.cancel();
    _frameTimer = null;
    _limitTimer?.cancel();
    _limitTimer = null;
    _clock?.cancel();
    _clock = null;
    _elapsed.stop();
    final mic = _micSub;
    _micSub = null;
    await mic?.cancel();
    try {
      if (await _rec.isRecording()) await _rec.stop();
    } catch (_) {}
    final ev = _events;
    _events = null;
    await ev?.cancel();
    final s = _session;
    _session = null;
    await s?.close();
    if (_pcmReady) {
      _pcmReady = false;
      FlutterPcmSound.setFeedCallback(null);
      try {
        await FlutterPcmSound.release();
      } catch (_) {}
    }
    _speaking = false;
    if (!keepCamera) {
      final c = _cam;
      _cam = null;
      await c?.dispose();
    }
  }

  Future<void> _switchCamera() async {
    if (_cameras.length < 2) return;
    _camIndex = (_camIndex + 1) % _cameras.length;
    await _openCamera();
  }

  void _toggleMute() {
    setState(() => _muted = !_muted);
    if (_muted) _session?.audioStreamEnd();
  }

  Future<void> _restart() async {
    await _teardown();
    await _begin();
  }

  String _mmss(Duration d) =>
      '${d.inMinutes.toString().padLeft(2, '0')}:'
      '${(d.inSeconds % 60).toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final settings = ref.watch(settingsProvider);
    final name = settings.displayRobotName(l.appTitle);
    final cam = _cam;
    final message = switch (phase) {
      LivePhase.permission => l.cameraDenied,
      LivePhase.connecting => l.liveConnecting,
      LivePhase.reconnecting => l.liveReconnecting,
      LivePhase.notConfigured => l.liveNotConfigured,
      LivePhase.noCamera => l.liveNoCamera,
      LivePhase.offline => l.liveNeedsInternet,
      LivePhase.error => l.liveError,
      LivePhase.ended => l.liveEnded,
      LivePhase.timeLimit => l.liveTimeLimit,
      LivePhase.live => null,
    };
    final canRetry =
        phase != LivePhase.live &&
        phase != LivePhase.connecting &&
        phase != LivePhase.reconnecting;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          if (cam != null && cam.value.isInitialized)
            FittedBox(
              fit: BoxFit.cover,
              clipBehavior: Clip.hardEdge,
              child: SizedBox(
                width: cam.value.previewSize?.height ?? 480,
                height: cam.value.previewSize?.width ?? 720,
                child: CameraPreview(cam),
              ),
            )
          else
            const ColoredBox(color: SahbiColors.visor),
          // Top bar.
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Row(
                children: [
                  IconButton.filledTonal(
                    tooltip: l.liveEnd,
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () => Navigator.of(context).maybePop(),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '$name · ${l.liveTitle}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 16,
                            shadows: [Shadow(blurRadius: 6)],
                          ),
                        ),
                        Text(
                          phase == LivePhase.live
                              ? '${l.liveAiLabel} · ${_mmss(_elapsed.elapsed)}'
                              : l.liveAiLabel,
                          style: const TextStyle(
                            fontSize: 12,
                            color: SahbiColors.mint,
                            shadows: [Shadow(blurRadius: 6)],
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (_cameras.length > 1 && cam != null)
                    IconButton.filledTonal(
                      tooltip: l.liveSwitchCamera,
                      icon: const Icon(Icons.cameraswitch_rounded),
                      onPressed: _switchCamera,
                    ),
                ],
              ),
            ),
          ),
          // Status / error card.
          if (message != null)
            Center(
              child: Container(
                margin: const EdgeInsets.all(28),
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: SahbiColors.surface.withValues(alpha: 0.92),
                  borderRadius: BorderRadius.circular(24),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (!canRetry)
                      const Padding(
                        padding: EdgeInsets.only(bottom: 12),
                        child: CircularProgressIndicator(),
                      ),
                    Text(
                      message,
                      textAlign: TextAlign.center,
                      style: const TextStyle(height: 1.5),
                    ),
                    if (canRetry) ...[
                      const SizedBox(height: 14),
                      Wrap(
                        spacing: 8,
                        alignment: WrapAlignment.center,
                        children: [
                          if (phase == LivePhase.permission)
                            OutlinedButton(
                              onPressed: openAppSettings,
                              child: Text(l.openAppSettings),
                            ),
                          FilledButton(
                            onPressed: _restart,
                            child: Text(l.liveRetry),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
          // Bottom: captions, face, controls.
          Align(
            alignment: Alignment.bottomCenter,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (phase == LivePhase.live &&
                        _robotText.isEmpty &&
                        _userText.isEmpty)
                      _Caption(text: l.liveHint, dim: true),
                    if (_userText.isNotEmpty)
                      _Caption(text: _userText, dim: true),
                    if (_robotText.isNotEmpty) _Caption(text: _robotText),
                    const SizedBox(height: 10),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        IconButton.filledTonal(
                          iconSize: 28,
                          tooltip: _muted ? l.liveUnmute : l.liveMute,
                          onPressed: phase == LivePhase.live
                              ? _toggleMute
                              : null,
                          icon: Icon(
                            _muted ? Icons.mic_off_rounded : Icons.mic_rounded,
                          ),
                        ),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(24),
                          child: SizedBox(
                            width: 112,
                            height: 88,
                            child: RobotFace(
                              fullScreen: true,
                              semanticLabel: name,
                              inputs: FaceInputs(
                                emotion: phase == LivePhase.live
                                    ? (_speaking
                                          ? Emotion.happy
                                          : Emotion.curious)
                                    : Emotion.neutral,
                                intensity: 0.6,
                                speaking: _speaking,
                                listening:
                                    phase == LivePhase.live &&
                                    !_speaking &&
                                    !_muted,
                                listenLevel: 0.3,
                              ),
                            ),
                          ),
                        ),
                        IconButton.filled(
                          iconSize: 28,
                          style: IconButton.styleFrom(
                            backgroundColor: SahbiColors.coral,
                          ),
                          tooltip: l.liveEnd,
                          onPressed: () => Navigator.of(context).maybePop(),
                          icon: const Icon(Icons.call_end_rounded),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Caption extends StatelessWidget {
  const _Caption({required this.text, this.dim = false});
  final String text;
  final bool dim;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 6),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Text(
        text,
        textAlign: TextAlign.center,
        maxLines: 4,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: dim ? 14 : 17,
          height: 1.4,
          color: dim ? SahbiColors.textSecondary : SahbiColors.textPrimary,
        ),
      ),
    );
  }
}
