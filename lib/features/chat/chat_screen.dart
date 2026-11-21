import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/providers.dart';
import '../../core/theme.dart';
import '../../core/ui_helpers.dart';
import '../../core/zellige.dart';
import '../../l10n/app_localizations.dart';
import '../face/robot_face.dart';
import '../personality/voice_state.dart';
import '../search/search_sources.dart';
import '../voice/mic_flow.dart';
import 'chat_models.dart';
import 'photo_strip.dart';

class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen({super.key});

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final _text = TextEditingController();
  final _focus = FocusNode();
  final _scroll = ScrollController();

  @override
  void dispose() {
    _text.dispose();
    _focus.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _send() {
    final t = _text.text.trim();
    if (t.isEmpty) return;
    _text.clear();
    ref.read(chatControllerProvider).send(t);
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final chat = ref.watch(chatControllerProvider);
    final voice = ref.watch(voiceControllerProvider);
    final companion = ref.watch(companionProvider);
    final net = ref.watch(connectivityProvider).value;
    final settings = ref.watch(settingsProvider);
    final backend = ref.read(backendClientProvider);
    ref.listen(chatControllerProvider, (_, _) => _scrollToEnd());

    final listening = voice.state == VoiceState.listening;

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 8,
        title: Row(
          children: [
            SizedBox(
              width: 40,
              height: 40,
              child: RobotFace(
                inputs: FaceInputs(
                  emotion: companion.emotion,
                  intensity: companion.intensity,
                  speaking: voice.state == VoiceState.speaking,
                  listening: listening,
                  listenLevel: voice.level,
                  dizzy: companion.dizzy,
                ),
                wordPulse: voice.wordPulse,
              ),
            ),
            const SizedBox(width: 10),
            Text(l.appTitle),
          ],
        ),
        actions: [
          MicIndicator(on: voice.micOpen),
          IconButton(
            tooltip: l.newChat,
            icon: const Icon(Icons.add_comment_outlined),
            onPressed: chat.messages.isEmpty ? null : chat.clear,
          ),
        ],
      ),
      body: ZelligeBackground(
        child: Column(
          children: [
            ConnectivityBanner(
              net: net,
              hasBackendUrl: backend.hasBaseUrl,
              sendToAi: settings.sendToAi,
            ),
            Expanded(
              child: chat.messages.isEmpty
                  ? _Empty(
                      onPick: (p) => chat.send(p),
                      latin: settings.latinDarija,
                    )
                  : ListView.builder(
                      controller: _scroll,
                      padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
                      itemCount: chat.messages.length,
                      itemBuilder: (_, i) => _Bubble(
                        key: ValueKey(chat.messages[i].id),
                        m: chat.messages[i],
                        onRetry: () => chat.retry(chat.messages[i]),
                        onReplay: () => chat.replay(chat.messages[i]),
                      ),
                    ),
            ),
            if (listening)
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 4,
                ),
                child: Text(
                  voice.partial.isEmpty ? l.listeningHint : voice.partial,
                  style: const TextStyle(color: SahbiColors.green),
                ),
              ),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
                child: Row(
                  children: [
                    IconButton.filled(
                      key: const Key('chat_mic'),
                      tooltip: listening ? l.stopListening : l.tapToTalk,
                      style: IconButton.styleFrom(
                        backgroundColor: listening
                            ? SahbiColors.coral
                            : SahbiColors.surfaceHigh,
                        foregroundColor: listening
                            ? Colors.white
                            : SahbiColors.turquoise,
                      ),
                      onPressed: () async {
                        if (listening) {
                          await voice.stopListening();
                        } else {
                          await startListeningFlow(
                            context,
                            ref,
                            onTypedFallback: _focus.requestFocus,
                          );
                        }
                      },
                      icon: Icon(
                        listening ? Icons.stop_rounded : Icons.mic_rounded,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: TextField(
                        key: const Key('chat_input'),
                        controller: _text,
                        focusNode: _focus,
                        minLines: 1,
                        maxLines: 4,
                        maxLength: 4000,
                        buildCounter: (
                          _, {
                          required currentLength,
                          required isFocused,
                          maxLength,
                        }) => null,
                        textInputAction: TextInputAction.send,
                        onSubmitted: (_) => _send(),
                        decoration: InputDecoration(hintText: l.typeMessage),
                      ),
                    ),
                    const SizedBox(width: 6),
                    if (voice.state == VoiceState.speaking || chat.busy)
                      IconButton(
                        tooltip: l.interruptSpeech,
                        onPressed: ref.read(chatControllerProvider).stop,
                        icon: const Icon(
                          Icons.stop_circle_outlined,
                          color: SahbiColors.coral,
                        ),
                      ),
                    ValueListenableBuilder(
                      valueListenable: _text,
                      builder: (_, v, _) => IconButton.filled(
                        key: const Key('chat_send'),
                        tooltip: l.send,
                        onPressed: v.text.trim().isEmpty ? null : _send,
                        icon: const Icon(Icons.send_rounded),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.onPick, required this.latin});
  final void Function(String) onPick;
  final bool latin;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const ZelligeLoader(size: 56),
            const SizedBox(height: 16),
            Text(
              L10n.of(context).emptyChat,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 16),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final (e, p) in quickPhrases(latin))
                  ActionChip(label: Text('$e  $p'), onPressed: () => onPick(p)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({
    super.key,
    required this.m,
    required this.onRetry,
    required this.onReplay,
  });
  final ChatMessage m;
  final VoidCallback onRetry;
  final VoidCallback onReplay;

  bool get _rtlText => RegExp(r'[\u0600-\u06FF]').hasMatch(m.text);

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final user = m.role == ChatRole.user;
    final isError = m.kind == ChatKind.error;
    final bg = user
        ? SahbiColors.turquoise.withValues(alpha: 0.18)
        : isError
        ? SahbiColors.coral.withValues(alpha: 0.12)
        : SahbiColors.surfaceHigh;

    final content = <Widget>[];
    if (m.kind == ChatKind.offline || m.kind == ChatKind.command) {
      content.add(
        Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                m.kind == ChatKind.offline
                    ? Icons.cloud_off_rounded
                    : Icons.bolt_rounded,
                size: 13,
                color: SahbiColors.amber,
              ),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  m.kind == ChatKind.offline
                      ? '${l.labelOffline}${m.errorCode != null ? ' · ${errorText(l, m.errorCode)}' : ''}'
                      : l.labelCommand,
                  style: const TextStyle(
                    fontSize: 11,
                    color: SahbiColors.amber,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }
    if (m.streaming && m.text.isEmpty) {
      content.add(
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const ZelligeLoader(size: 20),
            const SizedBox(width: 8),
            Text(switch (m.phase) {
              'searching' => l.phaseSearching,
              'weather' => l.phaseWeather,
              'retrying' => l.phaseRetrying,
              'waking' => l.phaseWaking,
              _ => l.stateThinking,
            }, style: const TextStyle(color: SahbiColors.textSecondary)),
          ],
        ),
      );
    } else {
      content.add(
        SelectableText(
          isError && m.text.isEmpty ? errorText(l, m.errorCode) : m.text,
          textDirection: _rtlText ? TextDirection.rtl : TextDirection.ltr,
          style: const TextStyle(
            fontSize: 16,
            height: 1.45,
            color: SahbiColors.textPrimary,
          ),
        ),
      );
      if (m.streaming && m.phase != null && m.phase != 'thinking') {
        content.add(
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              m.phase == 'searching' ? l.phaseSearching : l.phaseWeather,
              style: const TextStyle(
                fontSize: 12,
                color: SahbiColors.textSecondary,
              ),
            ),
          ),
        );
      }
    }
    if (m.images.isNotEmpty) {
      content.add(
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: PhotoStrip(images: m.images),
        ),
      );
    }
    final tr = m.translation;
    if (tr != null) {
      content.add(
        Container(
          margin: const EdgeInsets.only(top: 8),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: SahbiColors.background.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: SahbiColors.green.withValues(alpha: 0.4)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${l.translation} · ${tr.target.toUpperCase()}',
                style: const TextStyle(fontSize: 11, color: SahbiColors.green),
              ),
              const SizedBox(height: 4),
              Text(
                tr.source,
                style: const TextStyle(color: SahbiColors.textSecondary),
              ),
              const SizedBox(height: 4),
              SelectableText(
                tr.translation,
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w500,
                ),
              ),
              Align(
                alignment: AlignmentDirectional.centerEnd,
                child: IconButton(
                  tooltip: l.copy,
                  icon: const Icon(Icons.copy_rounded, size: 18),
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: tr.translation));
                    ScaffoldMessenger.of(context)
                        .showSnackBar(SnackBar(content: Text(l.copied)));
                  },
                ),
              ),
            ],
          ),
        ),
      );
    }
    if (m.searchUnavailable || m.sources.isNotEmpty) {
      content.add(
        SearchSources(
          sources: m.sources,
          verification: m.verification,
          searchUnavailable: m.searchUnavailable,
        ),
      );
    }
    if (isError && m.retryText != null) {
      content.add(
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: TextButton.icon(
            key: Key('retry_${m.id}'),
            onPressed: onRetry,
            icon: const Icon(Icons.refresh_rounded, size: 18),
            label: Text(l.retry),
          ),
        ),
      );
    }
    if (!user && !m.streaming && !isError && m.text.isNotEmpty) {
      content.add(
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              visualDensity: VisualDensity.compact,
              tooltip: l.replay,
              icon: const Icon(
                Icons.volume_up_outlined,
                size: 18,
                color: SahbiColors.textSecondary,
              ),
              onPressed: onReplay,
            ),
            IconButton(
              visualDensity: VisualDensity.compact,
              tooltip: l.copy,
              icon: const Icon(
                Icons.copy_rounded,
                size: 16,
                color: SahbiColors.textSecondary,
              ),
              onPressed: () {
                Clipboard.setData(ClipboardData(text: m.text));
                ScaffoldMessenger.of(context)
                    .showSnackBar(SnackBar(content: Text(l.copied)));
              },
            ),
          ],
        ),
      );
    }

    return Align(
      alignment: user
          ? AlignmentDirectional.centerEnd
          : AlignmentDirectional.centerStart,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * 0.84,
        ),
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 5),
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 8),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadiusDirectional.only(
              topStart: const Radius.circular(18),
              topEnd: const Radius.circular(18),
              bottomStart: Radius.circular(user ? 18 : 4),
              bottomEnd: Radius.circular(user ? 4 : 18),
            ),
            border: Border.all(
              color: isError
                  ? SahbiColors.coral.withValues(alpha: 0.4)
                  : SahbiColors.outline.withValues(alpha: 0.6),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: content,
          ),
        ),
      ),
    );
  }
}
