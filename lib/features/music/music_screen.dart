import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../core/providers.dart';
import '../../core/theme.dart';
import '../../core/zellige.dart';
import '../../l10n/app_localizations.dart';
import '../chat/result_lines.dart';
import 'music_models.dart';
import 'music_controller.dart';

class MusicScreen extends ConsumerStatefulWidget {
  const MusicScreen({super.key});

  @override
  ConsumerState<MusicScreen> createState() => _MusicScreenState();
}

class _MusicScreenState extends ConsumerState<MusicScreen>
    with WidgetsBindingObserver {
  final _query = TextEditingController();
  bool _notifDenied = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(musicControllerProvider).refreshOutput();
      _checkNotifications();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    // Output may change while the user is in the system panel.
    if (s == AppLifecycleState.resumed) {
      ref.read(musicControllerProvider).refreshOutput();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _query.dispose();
    super.dispose();
  }

  Future<void> _checkNotifications() async {
    try {
      final s = await Permission.notification.status;
      if (mounted) {
        setState(() => _notifDenied = s.isDenied || s.isPermanentlyDenied);
      }
    } catch (_) {}
  }

  /// Android 13+: ask for POST_NOTIFICATIONS right before first playback so
  /// the media notification can show. Playback works either way.
  Future<void> _ensureNotif() async {
    try {
      final s = await Permission.notification.status;
      if (s.isDenied) {
        final r = await Permission.notification.request();
        if (mounted) setState(() => _notifDenied = !r.isGranted);
      }
    } catch (_) {}
  }

  void _toast(ActionResult r) {
    if (!mounted) return;
    final lang = ref.read(settingsProvider).uiLocale;
    final line = resultLine(r);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          line.display(lang == 'ar' ? 'darija' : lang, latinDarija: false),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final music = ref.watch(musicControllerProvider);
    final snap = music.snapshot;
    final cur = snap.current;

    return Scaffold(
      appBar: AppBar(title: Text(l.musicTitle)),
      body: ZelligeBackground(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [
            if (_notifDenied)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  l.notificationsDenied,
                  style: const TextStyle(
                    color: SahbiColors.amber,
                    fontSize: 12,
                  ),
                ),
              ),
            _NowPlaying(music: music, onResult: _toast),
            const SizedBox(height: 12),
            _OutputCard(music: music),
            const SizedBox(height: 12),
            ZelligeCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l.streamingTitle,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _query,
                    decoration: InputDecoration(
                      hintText: l.streamingSearchHint,
                      prefixIcon: const Icon(Icons.search),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      FilledButton.tonalIcon(
                        onPressed: () async => _toast(
                          await music.links.openSpotify(
                            _query.text.trim().isEmpty
                                ? null
                                : _query.text.trim(),
                          ),
                        ),
                        icon: const Icon(Icons.open_in_new_rounded, size: 18),
                        label: Text(l.openSpotify),
                      ),
                      FilledButton.tonalIcon(
                        onPressed: () async => _toast(
                          await music.links.openYouTubeMusic(
                            _query.text.trim().isEmpty
                                ? null
                                : _query.text.trim(),
                          ),
                        ),
                        icon: const Icon(Icons.open_in_new_rounded, size: 18),
                        label: Text(l.openYouTubeMusic),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    l.streamingNote,
                    style: const TextStyle(
                      fontSize: 12,
                      color: SahbiColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: Text(
                    l.myTracks,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                IconButton(
                  tooltip: l.addFiles,
                  icon: const Icon(Icons.library_add_outlined),
                  onPressed: () async {
                    final r = await music.importFiles();
                    if (!r.ok) _toast(r);
                  },
                ),
                IconButton(
                  tooltip: l.addFolder,
                  icon: const Icon(Icons.create_new_folder_outlined),
                  onPressed: () async {
                    final r = await music.importFolder();
                    if (!r.ok) _toast(r);
                  },
                ),
              ],
            ),
            if (music.library.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  l.noTracks,
                  style: const TextStyle(color: SahbiColors.textSecondary),
                ),
              ),
            for (var i = 0; i < music.library.length; i++)
              _TrackTile(
                t: music.library[i],
                current: cur?.id == music.library[i].id,
                onTap: () async {
                  await _ensureNotif();
                  final r = await music.playTracks(music.library, start: i);
                  if (!r.ok) _toast(r);
                },
                onRemove: () => music.removeTrack(music.library[i]),
                removeLabel: l.removeTrack,
              ),
            const SizedBox(height: 16),
            Text(l.demoTracks, style: Theme.of(context).textTheme.titleMedium),
            for (var i = 0; i < demoTracks.length; i++)
              _TrackTile(
                t: demoTracks[i],
                current: cur?.id == demoTracks[i].id,
                onTap: () async {
                  await _ensureNotif();
                  final r = await music.playTracks(demoTracks, start: i);
                  if (!r.ok) _toast(r);
                },
              ),
          ],
        ),
      ),
    );
  }
}

class _NowPlaying extends StatelessWidget {
  const _NowPlaying({required this.music, required this.onResult});
  final MusicController music;
  final void Function(ActionResult) onResult;

  String _fmt(Duration d) =>
      '${d.inMinutes}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final snap = music.snapshot;
    final cur = snap.current;
    final dur = snap.duration ?? cur?.duration;
    final hasQueue = cur != null;
    return ZelligeCard(
      child: Column(
        children: [
          Row(
            children: [
              _Art(track: cur, size: 64),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      cur?.title ?? l.nothingPlaying,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    if (cur?.artist != null)
                      Text(
                        cur!.artist!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: SahbiColors.textSecondary,
                        ),
                      ),
                    if (snap.error != null)
                      Text(
                        snap.error!,
                        style: const TextStyle(
                          color: SahbiColors.coral,
                          fontSize: 12,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
          if (hasQueue && dur != null && dur > Duration.zero) ...[
            Slider(
              value: snap.position.inMilliseconds
                  .clamp(0, dur.inMilliseconds)
                  .toDouble(),
              max: dur.inMilliseconds.toDouble(),
              onChanged: (v) => music.seek(Duration(milliseconds: v.round())),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  Text(
                    _fmt(snap.position),
                    style: const TextStyle(
                      fontSize: 12,
                      color: SahbiColors.textSecondary,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    _fmt(dur),
                    style: const TextStyle(
                      fontSize: 12,
                      color: SahbiColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ],
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                tooltip: l.prevTrack,
                onPressed: hasQueue
                    ? () async => onResult(await music.previous())
                    : null,
                icon: const Icon(Icons.skip_previous_rounded, size: 32),
              ),
              const SizedBox(width: 8),
              IconButton.filled(
                iconSize: 36,
                onPressed: hasQueue
                    ? () async {
                        final r = snap.playing
                            ? await music.pause()
                            : await music.resume();
                        if (!r.ok) onResult(r);
                      }
                    : null,
                icon: snap.loading
                    ? const SizedBox(
                        width: 28,
                        height: 28,
                        child: CircularProgressIndicator(strokeWidth: 2.5),
                      )
                    : Icon(
                        snap.playing
                            ? Icons.pause_rounded
                            : Icons.play_arrow_rounded,
                      ),
              ),
              const SizedBox(width: 8),
              IconButton(
                tooltip: l.nextTrack,
                onPressed: hasQueue
                    ? () async => onResult(await music.next())
                    : null,
                icon: const Icon(Icons.skip_next_rounded, size: 32),
              ),
              IconButton(
                tooltip: l.stopPlayback,
                onPressed: hasQueue
                    ? () async => onResult(await music.stop())
                    : null,
                icon: const Icon(Icons.stop_rounded),
              ),
            ],
          ),
          Row(
            children: [
              const Icon(
                Icons.volume_down_rounded,
                size: 20,
                color: SahbiColors.textSecondary,
              ),
              Expanded(
                child: Slider(
                  value: (music.systemVolume ?? 0).clamp(0.0, 1.0),
                  onChanged: music.systemVolume == null
                      ? null
                      : (v) => music.setVolume(v),
                  semanticFormatterCallback: (v) =>
                      '${l.systemVolume} ${(v * 100).round()}%',
                ),
              ),
              const Icon(
                Icons.volume_up_rounded,
                size: 20,
                color: SahbiColors.textSecondary,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _OutputCard extends StatelessWidget {
  const _OutputCard({required this.music});
  final MusicController music;

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final o = music.output;
    final (icon, label) = switch (o.type) {
      'bluetooth' => (Icons.bluetooth_audio_rounded, l.outputBluetooth),
      'wired' => (Icons.headphones_rounded, l.outputWired),
      'usb' => (Icons.usb_rounded, l.outputUsb),
      'speaker' => (Icons.speaker_phone_rounded, l.outputSpeaker),
      _ => (Icons.device_unknown_rounded, l.outputUnknown),
    };
    final messenger = ScaffoldMessenger.of(context);
    return ZelligeCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l.outputDevice,
            style: const TextStyle(
              fontSize: 12,
              color: SahbiColors.textSecondary,
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Icon(
                icon,
                color: o.isBluetooth
                    ? SahbiColors.turquoise
                    : SahbiColors.textPrimary,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  o.name.isNotEmpty && o.name != label
                      ? '$label · ${o.name}'
                      : label,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.icon(
                onPressed: () async {
                  final r = await music.bridge.openOutputSwitcher();
                  if (r == 'none') {
                    messenger.showSnackBar(
                      SnackBar(content: Text(l.outputSwitcherUnavailable)),
                    );
                  } else if (r == 'media_output_panel') {
                    // Android 11–13: best-effort SystemUI panel; we cannot confirm it opened.
                    messenger.showSnackBar(
                      SnackBar(
                        content: Text(l.outputPanelMaybe),
                        action: SnackBarAction(
                          label: l.openBluetoothSettings,
                          onPressed: music.bridge.openBluetoothSettings,
                        ),
                      ),
                    );
                  }
                },
                icon: const Icon(Icons.cast_rounded, size: 18),
                label: Text(l.openOutputSwitcher),
              ),
              OutlinedButton.icon(
                onPressed: () => music.bridge.openBluetoothSettings(),
                icon: const Icon(Icons.bluetooth_rounded, size: 18),
                label: Text(l.openBluetoothSettings),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            l.outputNote,
            style: const TextStyle(
              fontSize: 12,
              color: SahbiColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

class _TrackTile extends StatelessWidget {
  const _TrackTile({
    required this.t,
    required this.current,
    required this.onTap,
    this.onRemove,
    this.removeLabel,
  });
  final Track t;
  final bool current;
  final VoidCallback onTap;
  final VoidCallback? onRemove;
  final String? removeLabel;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 4),
      leading: _Art(track: t, size: 44),
      title: Text(
        t.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(color: current ? SahbiColors.turquoise : null),
      ),
      subtitle: t.artist == null
          ? null
          : Text(t.artist!, maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: onRemove == null
          ? (current
                ? const Icon(
                    Icons.graphic_eq_rounded,
                    color: SahbiColors.turquoise,
                  )
                : null)
          : IconButton(
              tooltip: removeLabel,
              icon: const Icon(Icons.close_rounded),
              onPressed: onRemove,
            ),
      onTap: onTap,
    );
  }
}

class _Art extends StatelessWidget {
  const _Art({required this.track, required this.size});
  final Track? track;
  final double size;

  @override
  Widget build(BuildContext context) {
    final art = track?.artUri;
    Widget child;
    if (art != null && art.startsWith('file://')) {
      child = Image.file(
        File(Uri.parse(art).toFilePath()),
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => _placeholder(),
      );
    } else {
      child = _placeholder();
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(size * 0.22),
      child: SizedBox.square(dimension: size, child: child),
    );
  }

  Widget _placeholder() => DecoratedBox(
    decoration: const BoxDecoration(
      gradient: LinearGradient(
        colors: [SahbiColors.surfaceHigh, SahbiColors.outline],
      ),
    ),
    child: CustomPaint(
      painter: ZelligePainter(opacity: 0.5, cell: size * 0.9),
      child: const Center(
        child: Icon(Icons.music_note_rounded, color: SahbiColors.mint),
      ),
    ),
  );
}
