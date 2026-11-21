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
import '../chat/chat_models.dart';
import '../face/robot_face.dart';
import '../personality/emotion.dart';
import '../personality/voice_state.dart';
import '../voice/wake_name.dart';
import 'live_player.dart';
import 'live_session.dart';
import 'pointing.dart';
import 'scene_watcher.dart';

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

  /// Live video is unavailable: one photo at a time through /v1/chat.
  photo,
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
  Timer? _speakTick;

  /// Ordered, pre-buffered playback + mic muting while the robot talks.
  late final LivePlayer _player = LivePlayer(
    feed: (pcm) => FlutterPcmSound.feed(
      PcmArrayInt16(bytes: ByteData.view(Uint8List.fromList(pcm).buffer)),
    ),
  );
  String _robotText = '';
  String _userText = '';
  bool _newRobotTurn = true;
  bool _newUserTurn = true;
  final Stopwatch _elapsed = Stopwatch();
  bool _snapping = false;
  int? _photoAt;

  /// Explains what the camera points at without being asked.
  final SceneWatcher _scene = SceneWatcher();

  /// A LOOK was sent and the model has not finished its answer yet.
  DateTime? _lookSentAt;

  // Pointing: the object the user tapped or pointed at is outlined in green
  // on a frozen copy of the frame it was found in (so the box always lines
  // up), then the robot is told to talk about that object only.
  Uint8List? _lastJpeg;
  DateTime? _lastJpegAt;
  Uint8List? _focusJpeg;
  UprightFrame? _focusFrame;
  LocatedObject? _focusObj;
  Offset? _focusTap;
  bool _locating = false;
  DateTime? _lastPointCheck;
  Timer? _focusTimer;
  Timer? _pulseTimer;
  double _pulse = 0;
  String? _pointNote;

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
    _focusTimer?.cancel();
    _pulseTimer?.cancel();
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
      _photoAt = null;
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
          () => phase = switch (e.code) {
            BackendErrorCode.notConfigured => LivePhase.notConfigured,
            BackendErrorCode.noInternet => LivePhase.offline,
            // Live refused (e.g. the key cannot open live sessions): fall
            // back to explaining one photo at a time.
            _ => LivePhase.photo,
          },
        );
      }
      return;
    } catch (e) {
      ref.read(errorLogProvider).add('live', '$e');
      if (mounted) setState(() => phase = LivePhase.photo);
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
        if (fromUser && text.trim().isNotEmpty) {
          // The user's own question about the view comes first.
          _scene
            ..userSpoke()
            ..markDescribed();
          // "hada / chno hadi / ça": they are probably pointing at something.
          final said = _newUserTurn ? text : '$_userText$text';
          final last = _lastPointCheck;
          final jpeg = _lastJpeg;
          if (jpeg != null &&
              mentionsThis(said) &&
              (last == null ||
                  DateTime.now().difference(last).inSeconds >= 4)) {
            unawaited(
              _checkPointing(
                jpeg,
                // Only steer the robot if it has not started answering yet.
                sendCue: () => _newRobotTurn && !_player.playing,
              ),
            );
          }
        }
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
        _player.turnComplete();
        _newRobotTurn = true;
        _lookSentAt = null;
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
              : (_cam != null ? LivePhase.photo : LivePhase.error),
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
      // The plugin prints every feed call by default: too slow for streaming.
      await FlutterPcmSound.setLogLevel(LogLevel.none);
      await FlutterPcmSound.setup(sampleRate: 24000, channelCount: 1);
      await FlutterPcmSound.setFeedThreshold(2400);
      _pcmReady = true;
      // "Speaking" follows the audio actually queued, not the network.
      _speakTick = Timer.periodic(const Duration(milliseconds: 150), (_) {
        final s = _player.playing;
        if (s != _speaking && mounted) setState(() => _speaking = s);
      });
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
        if (_muted) return;
        // Half-duplex: while the robot's voice is playing (and a moment
        // after), send silence instead of the mic so the model does not hear
        // itself through the speaker, cut itself off and start again.
        _session?.sendAudio(
          _player.micShouldBeMuted ? Uint8List(chunk.length) : chunk,
        );
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
    // Taking a picture is heavy on many phones: skip frames while the robot
    // talks so its voice does not stutter.
    if (_player.playing) return;
    if (!c.value.isInitialized || c.value.isTakingPicture) return;
    _capturing = true;
    try {
      final x = await c.takePicture();
      final bytes = await x.readAsBytes();
      try {
        await File(x.path).delete();
      } catch (_) {}
      s.sendImage(bytes);
      _lastJpeg = bytes;
      _lastJpegAt = DateTime.now();
      await _maybeLook(s, bytes);
    } catch (e) {
      ref.read(errorLogProvider).add('live.frame', '$e');
    } finally {
      _capturing = false;
    }
  }

  /// When the camera settles on something new, ask the robot to explain it
  /// (the frame was just sent, so the model sees what the user sees).
  Future<void> _maybeLook(LiveSession s, Uint8List jpeg) async {
    if (!ref.read(settingsProvider).liveAutoDescribe || _muted) return;
    if (_locating || _focusFrame != null) return;
    final sig = await sceneSignature(jpeg);
    if (sig == null || !mounted) return;
    final sent = _lookSentAt;
    final waiting =
        sent != null && DateTime.now().difference(sent).inSeconds < 10;
    if (_scene.onFrame(sig, robotBusy: _player.playing || waiting)) {
      _lookSentAt = DateTime.now();
      // A finger pointing at something wins over "explain the view".
      unawaited(() async {
        final pointed = await _checkPointing(jpeg, sendCue: () => true);
        if (!pointed && mounted && _session == s && s.ready) {
          s.sendText(liveLookCue);
        }
      }());
    }
  }

  BackendClient get _client => ref.read(backendClientProvider);
  String get _locateLang =>
      locateLanguage(ref.read(settingsProvider).replyLanguage);

  /// The newest camera frame: the one just streamed, or a fresh picture.
  Future<Uint8List?> _grabJpeg() async {
    final last = _lastJpeg, at = _lastJpegAt;
    if (last != null &&
        at != null &&
        DateTime.now().difference(at) < const Duration(milliseconds: 1500)) {
      return last;
    }
    final c = _cam;
    if (c == null || !c.value.isInitialized) return null;
    for (var i = 0; i < 20 && (_capturing || c.value.isTakingPicture); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    if (_capturing || c.value.isTakingPicture) return _lastJpeg;
    _capturing = true;
    try {
      final x = await c.takePicture();
      final bytes = await x.readAsBytes();
      try {
        await File(x.path).delete();
      } catch (_) {}
      _lastJpeg = bytes;
      _lastJpegAt = DateTime.now();
      return bytes;
    } catch (e) {
      ref.read(errorLogProvider).add('live.point', '$e');
      return null;
    } finally {
      _capturing = false;
    }
  }

  void _setPulse(bool on) {
    if (!on) {
      _pulseTimer?.cancel();
      _pulseTimer = null;
      return;
    }
    _pulseTimer ??= Timer.periodic(const Duration(milliseconds: 50), (_) {
      if (mounted) setState(() => _pulse = (_pulse + 0.05) % 1);
    });
  }

  void _clearFocus() {
    _focusTimer?.cancel();
    if (!mounted) return;
    setState(() {
      _focusFrame = null;
      _focusJpeg = null;
      _focusObj = null;
      _focusTap = null;
      _pointNote = null;
    });
  }

  void _holdFocus(Duration d) {
    _focusTimer?.cancel();
    _focusTimer = Timer(d, _clearFocus);
  }

  Duration get _focusHold => phase == LivePhase.photo
      ? const Duration(seconds: 14)
      : const Duration(seconds: 7);

  /// Tells the robot which object is meant (live: POINT cue; photo: a chat
  /// question about that object).
  void _talkAbout(LocatedObject obj, Uint8List jpeg) {
    if (phase == LivePhase.live) {
      final s = _session;
      if (s == null || !s.ready) return;
      s.sendImage(jpeg);
      _scene.markDescribed();
      _lookSentAt = DateTime.now();
      s.sendText(obj.liveCue);
    } else if (phase == LivePhase.photo) {
      unawaited(_askPhoto(jpeg, obj));
    }
  }

  /// Tap on the picture: find the object under the finger.
  Future<void> _onTap(Offset pos, Size screen) async {
    if (_locating || _snapping) return;
    if (phase != LivePhase.live && phase != LivePhase.photo) return;
    final cam = _cam;
    if (cam == null || !cam.value.isInitialized) return;
    final l = L10n.of(context);
    var frame = _focusFrame;
    var jpeg = _focusJpeg;
    final ({double x, double y})? tap;
    if (frame != null && jpeg != null) {
      tap = screenToImage(pos, screen, frame.aspect);
    } else {
      final ps = cam.value.previewSize;
      tap = screenToImage(
        pos,
        screen,
        ps == null ? 3 / 4 : ps.height / ps.width,
        mirror: cam.description.lensDirection == CameraLensDirection.front,
      );
    }
    if (tap == null) return;
    _focusTimer?.cancel();
    setState(() {
      _locating = true;
      _focusTap = pos;
      _focusObj = null;
      _pointNote = l.pointLooking;
    });
    _setPulse(true);
    LocatedObject? obj;
    try {
      if (frame == null || jpeg == null) {
        jpeg = await _grabJpeg();
        if (jpeg == null) return;
        frame = await uprightFrame(jpeg);
        if (frame == null || !mounted) return;
        final f = frame;
        setState(() {
          _focusFrame = f;
          _focusJpeg = jpeg;
          // Same spot on the (un-mirrored) frozen frame.
          _focusTap = imageBoxToScreen(
            Rect.fromLTWH(tap!.x, tap.y, 0, 0),
            screen,
            f.aspect,
          ).topLeft;
        });
      }
      obj = await locateOn(_client, frame, tap: tap, language: _locateLang);
    } catch (e) {
      ref.read(errorLogProvider).add('live.point', '$e');
    } finally {
      _locating = false;
      _setPulse(false);
    }
    if (!mounted) return;
    if (obj == null || jpeg == null) {
      setState(() => _pointNote = l.pointNotFound);
      _holdFocus(const Duration(milliseconds: 2200));
      return;
    }
    final found = obj;
    setState(() {
      _focusObj = found;
      _pointNote = null;
    });
    _holdFocus(_focusHold);
    _talkAbout(found, jpeg);
  }

  /// Is a finger pointing at something in [jpeg]? Highlights it and, when
  /// [sendCue] says so, tells the robot. True when an object was found.
  Future<bool> _checkPointing(
    Uint8List jpeg, {
    required bool Function() sendCue,
  }) async {
    if (_locating || _focusFrame != null || !mounted) return false;
    _locating = true;
    _lastPointCheck = DateTime.now();
    try {
      final frame = await uprightFrame(jpeg);
      if (frame == null) return false;
      final obj = await locateOn(
        _client,
        frame,
        language: _locateLang,
      ).timeout(const Duration(seconds: 6));
      if (obj == null || !mounted) return false;
      setState(() {
        _focusFrame = frame;
        _focusJpeg = jpeg;
        _focusObj = obj;
        _focusTap = null;
        _pointNote = null;
      });
      _holdFocus(_focusHold);
      if (sendCue()) _talkAbout(obj, jpeg);
      return true;
    } catch (e) {
      // Busy quota / no network: just carry on without the highlight.
      return false;
    } finally {
      _locating = false;
    }
  }

  /// Photo mode: ask the normal chat about the highlighted object.
  Future<void> _askPhoto(Uint8List jpeg, LocatedObject? obj) async {
    final l = L10n.of(context);
    final question = obj == null || obj.display.isEmpty
        ? l.photoQuestion
        : l.pointQuestion(obj.display);
    final chat = ref.read(chatControllerProvider);
    setState(() => _photoAt = chat.messages.length);
    await chat.sendPhoto(jpeg, question);
  }

  Future<void> _play(Uint8List pcm) async {
    if (!_pcmReady || pcm.length < 2) return;
    _player.add(pcm);
  }

  /// Barge-in: drop whatever is still queued in the speaker.
  Future<void> _flushAudio() async {
    _player.clear();
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
    _speakTick?.cancel();
    _speakTick = null;
    _player.clear();
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

  /// Photo mode: one picture → the normal AI chat (which can see images)
  /// → spoken answer through the usual voice chain.
  Future<void> _snap() async {
    final c = _cam;
    if (_snapping || c == null || !c.value.isInitialized) return;
    if (c.value.isTakingPicture) return;
    _clearFocus();
    setState(() => _snapping = true);
    try {
      final x = await c.takePicture();
      final bytes = await x.readAsBytes();
      try {
        await File(x.path).delete();
      } catch (_) {}
      if (!mounted) return;
      // A finger on the photo picks the object to talk about.
      await _checkPointing(bytes, sendCue: () => false);
      if (!mounted) return;
      await _askPhoto(bytes, _focusObj);
    } catch (e) {
      ref.read(errorLogProvider).add('live.photo', '$e');
    } finally {
      if (mounted) setState(() => _snapping = false);
    }
  }

  /// Text of the reply to the last photo, or null while waiting.
  String? _photoReply(L10n l) {
    final at = _photoAt;
    if (at == null) return null;
    final msgs = ref.watch(chatControllerProvider).messages;
    for (var i = at; i < msgs.length; i++) {
      final m = msgs[i];
      if (m.role != ChatRole.sahbi) continue;
      if (m.kind == ChatKind.error) return l.photoError;
      if (m.text.isEmpty) return null;
      return m.text;
    }
    return null;
  }

  Future<void> _switchCamera() async {
    if (_cameras.length < 2) return;
    _camIndex = (_camIndex + 1) % _cameras.length;
    _scene.reset();
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
      LivePhase.live || LivePhase.photo => null,
    };
    final photo = phase == LivePhase.photo;
    final photoReply = photo ? _photoReply(l) : null;
    final voiceSpeaking =
        photo &&
        ref.watch(voiceControllerProvider).state == VoiceState.speaking;
    final canRetry =
        phase != LivePhase.live &&
        !photo &&
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
          // Frozen frame + green outline of the tapped / pointed-at object.
          if (_focusFrame case final f?)
            Image.memory(f.png, fit: BoxFit.cover, gaplessPlayback: true),
          if (cam != null && (phase == LivePhase.live || photo))
            LayoutBuilder(
              builder: (ctx, box) {
                final size = box.biggest;
                final ps = cam.value.previewSize;
                return GestureDetector(
                  key: const Key('live_tap_layer'),
                  behavior: HitTestBehavior.opaque,
                  onTapUp: (d) => _onTap(d.localPosition, size),
                  child: CustomPaint(
                    size: size,
                    painter: PointHighlightPainter(
                      aspect:
                          _focusFrame?.aspect ??
                          (ps == null ? 3 / 4 : ps.height / ps.width),
                      box: _focusObj?.box,
                      tap: _focusTap,
                      label: _focusObj?.display,
                      busy: _locating,
                      pulse: _pulse,
                      textDirection: Directionality.of(ctx),
                    ),
                  ),
                );
              },
            ),
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
                        if (phase == LivePhase.live)
                          Text(
                            _mmss(_elapsed.elapsed),
                            style: const TextStyle(
                              fontSize: 12,
                              color: SahbiColors.mint,
                              shadows: [Shadow(blurRadius: 6)],
                            ),
                          ),
                      ],
                    ),
                  ),
                  if (photo)
                    IconButton.filledTonal(
                      tooltip: l.liveRetry,
                      icon: const Icon(Icons.videocam_rounded),
                      onPressed: _snapping ? null : _restart,
                    ),
                  if (phase == LivePhase.live)
                    IconButton.filledTonal(
                      key: const Key('live_auto_describe'),
                      tooltip: l.liveAutoDescribe,
                      isSelected: settings.liveAutoDescribe,
                      icon: const Icon(Icons.center_focus_weak_rounded),
                      selectedIcon: const Icon(
                        Icons.center_focus_strong_rounded,
                        color: SahbiColors.green,
                      ),
                      onPressed: () {
                        final on = !settings.liveAutoDescribe;
                        ref
                            .read(settingsProvider.notifier)
                            .update((x) => x.copyWith(liveAutoDescribe: on));
                        if (on) _scene.reset();
                        ScaffoldMessenger.of(context)
                          ..hideCurrentSnackBar()
                          ..showSnackBar(
                            SnackBar(
                              content: Text(
                                on
                                    ? '${l.liveAutoDescribe} ✓ — ${l.liveAutoDescribeHint}'
                                    : '${l.liveAutoDescribe} ✗',
                              ),
                            ),
                          );
                      },
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
                      _Caption(
                        text: '${l.liveHint}\n${l.liveTapHint}',
                        dim: true,
                      ),
                    if (_userText.isNotEmpty)
                      _Caption(text: _userText, dim: true),
                    if (_robotText.isNotEmpty) _Caption(text: _robotText),
                    if (photo && _photoAt == null)
                      _Caption(
                        text: '${l.photoModeHint}\n${l.liveTapHint}',
                        dim: true,
                      ),
                    if (_pointNote case final note?)
                      _Caption(text: note, dim: true),
                    if (photo && _photoAt != null)
                      _Caption(text: photoReply ?? l.photoThinking),
                    const SizedBox(height: 10),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        if (photo)
                          IconButton.filled(
                            iconSize: 30,
                            tooltip: l.photoSnap,
                            onPressed: _snapping || cam == null ? null : _snap,
                            icon: _snapping
                                ? const SizedBox(
                                    width: 28,
                                    height: 28,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 3,
                                    ),
                                  )
                                : const Icon(Icons.photo_camera_rounded),
                          )
                        else
                          IconButton.filledTonal(
                            iconSize: 28,
                            tooltip: _muted ? l.liveUnmute : l.liveMute,
                            onPressed: phase == LivePhase.live
                                ? _toggleMute
                                : null,
                            icon: Icon(
                              _muted
                                  ? Icons.mic_off_rounded
                                  : Icons.mic_rounded,
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
                                emotion: phase == LivePhase.live || photo
                                    ? (_speaking || voiceSpeaking
                                          ? Emotion.happy
                                          : Emotion.curious)
                                    : Emotion.neutral,
                                intensity: 0.6,
                                speaking: _speaking || voiceSpeaking,
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
