import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';

import '../../core/providers.dart';
import '../../core/theme.dart';
import '../../l10n/app_localizations.dart';
import 'youtube_controller.dart';

/// Floating card with the official YouTube embedded player, so songs play
/// inside the app. Shown only while YouTube is active; it pauses when the app
/// leaves the screen (embedded playback must stay visible).
class YoutubePanel extends ConsumerWidget {
  const YoutubePanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final yt = ref.watch(youtubeControllerProvider);
    final l = L10n.of(context);
    if (yt.state == YoutubeState.idle) return const SizedBox.shrink();
    final width = MediaQuery.sizeOf(context).width.clamp(0.0, 420.0) - 24;
    Widget body;
    if (yt.state == YoutubeState.searching) {
      body = _Row(
        leading: const SizedBox(
          width: 22,
          height: 22,
          child: CircularProgressIndicator(strokeWidth: 2.5),
        ),
        text: l.ytSearching(yt.query ?? ''),
        onClose: yt.stop,
        closeLabel: l.ytClose,
      );
    } else if (yt.state == YoutubeState.error) {
      body = _Row(
        leading: const Icon(
          Icons.error_outline_rounded,
          color: SahbiColors.coral,
        ),
        text: l.ytError,
        onClose: () async => yt.dismissError(),
        closeLabel: l.ytClose,
      );
    } else {
      final v = yt.current!;
      body = Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
            child: SizedBox(
              width: width,
              height: width * 9 / 16,
              child: _YoutubeWebPlayer(controller: yt),
            ),
          ),
          Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(12, 4, 4, 4),
            child: Row(
              children: [
                const Icon(
                  Icons.smart_display_rounded,
                  color: SahbiColors.coral,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    v.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                if (yt.index + 1 < yt.results.length)
                  IconButton(
                    tooltip: l.ytNext,
                    icon: const Icon(Icons.skip_next_rounded),
                    onPressed: yt.next,
                  ),
                IconButton(
                  tooltip: l.ytClose,
                  icon: const Icon(Icons.close_rounded),
                  onPressed: yt.stop,
                ),
              ],
            ),
          ),
        ],
      );
    }
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Material(
          color: SahbiColors.surface.withValues(alpha: 0.96),
          elevation: 8,
          borderRadius: BorderRadius.circular(18),
          child: SizedBox(width: width, child: body),
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({
    required this.leading,
    required this.text,
    required this.onClose,
    required this.closeLabel,
  });
  final Widget leading;
  final String text;
  final Future<Object?> Function() onClose;
  final String closeLabel;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsetsDirectional.fromSTEB(14, 6, 4, 6),
    child: Row(
      children: [
        leading,
        const SizedBox(width: 12),
        Expanded(
          child: Text(text, maxLines: 2, overflow: TextOverflow.ellipsis),
        ),
        IconButton(
          tooltip: closeLabel,
          icon: const Icon(Icons.close_rounded),
          onPressed: onClose,
        ),
      ],
    ),
  );
}

class _YoutubeWebPlayer extends StatefulWidget {
  const _YoutubeWebPlayer({required this.controller});
  final YoutubeController controller;

  @override
  State<_YoutubeWebPlayer> createState() => _YoutubeWebPlayerState();
}

class _YoutubeWebPlayerState extends State<_YoutubeWebPlayer>
    with WidgetsBindingObserver
    implements YoutubeSurface {
  /// Identifies the app to YouTube (the embedded player requires a referrer;
  /// without one it shows "error 153").
  static const _origin = 'https://com.sahbi.app';
  late final WebViewController _web;
  String? _loadedId;
  bool _pageReady = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.controller.surface = this;
    widget.controller.addListener(_sync);
    _web = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.black)
      ..addJavaScriptChannel('Sahbi', onMessageReceived: _onMessage)
      ..setNavigationDelegate(
        NavigationDelegate(
          // Stay on the player: links (YouTube logo, titles) are not opened.
          onNavigationRequest: (r) =>
              r.url.startsWith(_origin) ||
                  r.url.startsWith('https://www.youtube.com/embed/') ||
                  r.url.startsWith('about:')
              ? NavigationDecision.navigate
              : NavigationDecision.prevent,
        ),
      );
    final p = _web.platform;
    if (p is AndroidWebViewController) {
      // Autoplay after the user asked by voice (no extra tap needed).
      unawaited(p.setMediaPlaybackRequiresUserGesture(false));
    }
    _sync();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.controller.removeListener(_sync);
    if (identical(widget.controller.surface, this)) {
      widget.controller.surface = null;
    }
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      unawaited(widget.controller.pause());
    }
  }

  void _sync() {
    final id = widget.controller.current?.id;
    if (id == null || id == _loadedId) return;
    _loadedId = id;
    if (_pageReady) {
      unawaited(
        _web.runJavaScript('player&&player.loadVideoById(${jsonEncode(id)});'),
      );
    } else {
      unawaited(_web.loadHtmlString(_html(id), baseUrl: '$_origin/'));
    }
  }

  void _onMessage(JavaScriptMessage m) {
    final msg = m.message;
    if (msg == 'ready') {
      _pageReady = true;
    } else if (msg.startsWith('error:')) {
      // 2 bad id, 5 HTML5 error, 100 removed/private, 101/150 embed blocked.
      widget.controller.onVideoError();
    } else if (msg.startsWith('state:')) {
      final s = int.tryParse(msg.substring(6));
      if (s == 0) widget.controller.onEnded();
      if (s == 1) widget.controller.onPlayerState(playingNow: true);
      if (s == 2) widget.controller.onPlayerState(playingNow: false);
    }
  }

  @override
  Future<void> pause() => _web.runJavaScript('player&&player.pauseVideo();');

  @override
  Future<void> resume() => _web.runJavaScript('player&&player.playVideo();');

  static String _html(String id) =>
      '''
<!doctype html><html><head><meta name="viewport" content="width=device-width,initial-scale=1">
<meta name="referrer" content="strict-origin-when-cross-origin">
<style>html,body{margin:0;height:100%;background:#000;overflow:hidden}#p{position:absolute;inset:0;width:100%;height:100%}</style>
</head><body><div id="p"></div><script>
var player;
function onYouTubeIframeAPIReady(){
  player=new YT.Player('p',{videoId:${jsonEncode(id)},
    playerVars:{autoplay:1,playsinline:1,rel:0,origin:'$_origin'},
    events:{
      onReady:function(e){Sahbi.postMessage('ready');e.target.playVideo();},
      onStateChange:function(e){Sahbi.postMessage('state:'+e.data);},
      onError:function(e){Sahbi.postMessage('error:'+e.data);}
    }});
}
</script><script src="https://www.youtube.com/iframe_api"></script></body></html>''';

  @override
  Widget build(BuildContext context) => WebViewWidget(controller: _web);
}
