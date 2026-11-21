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
    this.images = const [],
    this.imageQuery,
    this.proactive = false,
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

  /// Photos the robot shows for "wrini …" (Wikipedia / Wikimedia Commons).
  List<ChatImage> images;
  String? imageQuery;

  /// Said by the robot on its own while the user was quiet.
  bool proactive;
  final DateTime at;
}

/// A free photo from Wikipedia / Wikimedia Commons, with its page (author
/// and licence are one tap away).
class ChatImage {
  const ChatImage({
    required this.url,
    required this.title,
    required this.page,
    required this.source,
  });

  final String url;
  final String title;
  final String page;
  final String source;

  static ChatImage? fromJson(Object? j) {
    if (j is! Map) return null;
    final url = j['url'];
    if (url is! String) return null;
    final u = Uri.tryParse(url);
    // Only Wikimedia's image servers.
    if (u == null ||
        u.scheme != 'https' ||
        !const {
          'upload.wikimedia.org',
          'thumb.wikimedia.org',
        }.contains(u.host)) {
      return null;
    }
    return ChatImage(
      url: url,
      title: (j['title'] as String?) ?? '',
      page: (j['page'] as String?) ?? '',
      source: (j['source'] as String?) ?? 'Wikimedia',
    );
  }
}
