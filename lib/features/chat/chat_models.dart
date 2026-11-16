import '../brain/brain_models.dart';
import '../music/music_models.dart';

enum ChatRole { user, sahbi }

/// ai = real AI answer; offline = pre-written; command = local command result;
/// error = failure notice.
enum ChatKind { ai, offline, command, error }

class ChatMessage {
  ChatMessage({
    required this.id,
    required this.role,
    required this.text,
    this.ttsText,
    this.language = 'darija',
    this.kind = ChatKind.ai,
    this.streaming = false,
    this.phase,
    this.sources = const [],
    this.verification = Verification.none,
    this.searchUnavailable = false,
    this.errorCode,
    this.retryText,
    this.results = const [],
    this.translation,
    DateTime? at,
  }) : at = at ?? DateTime.now();

  final String id;
  final ChatRole role;
  String text;
  String? ttsText;
  String language;
  ChatKind kind;
  bool streaming;

  /// thinking | searching | weather | retrying
  String? phase;
  List<SourceRef> sources;
  Verification verification;
  bool searchUnavailable;
  String? errorCode;

  /// User text to resend on "retry".
  String? retryText;
  List<ActionResult> results;
  ({String source, String target, String translation})? translation;
  final DateTime at;
}
