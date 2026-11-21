import 'package:material_ui/material_ui.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/theme.dart';
import '../../l10n/app_localizations.dart';
import 'chat_models.dart';

/// Wikimedia asks API/image clients to identify themselves.
const sahbiImageHeaders = {
  'User-Agent': 'SAHBI/0.1 (companion robot app; https://github.com/ayoubouzzine05/sahbi)',
};

/// Horizontal strip of photos ("wrini …"). Tap one to open it full screen
/// with its source page (author and licence).
class PhotoStrip extends StatelessWidget {
  const PhotoStrip({super.key, required this.images, this.height = 120});

  final List<ChatImage> images;
  final double height;

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final sources = images.map((i) => i.source).toSet().join(' / ');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          height: height,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: images.length,
            separatorBuilder: (_, _) => const SizedBox(width: 8),
            itemBuilder: (context, i) => _Thumb(
              key: Key('photo_$i'),
              image: images[i],
              height: height,
              onTap: () => openPhotoViewer(context, images, i),
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          l.photosCaption(sources),
          style: const TextStyle(
            fontSize: 11,
            color: SahbiColors.textSecondary,
          ),
        ),
      ],
    );
  }
}

class _Thumb extends StatelessWidget {
  const _Thumb({
    super.key,
    required this.image,
    required this.height,
    required this.onTap,
  });
  final ChatImage image;
  final double height;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: image.title,
    child: GestureDetector(
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: Container(
          width: height * 4 / 3,
          height: height,
          color: SahbiColors.background,
          child: NetPhoto(url: image.url, fit: BoxFit.cover),
        ),
      ),
    ),
  );
}

/// Network photo with a loader and an honest "could not load" state.
class NetPhoto extends StatelessWidget {
  const NetPhoto({super.key, required this.url, this.fit = BoxFit.contain});
  final String url;
  final BoxFit fit;

  @override
  Widget build(BuildContext context) => Image.network(
    url,
    headers: sahbiImageHeaders,
    fit: fit,
    loadingBuilder: (context, child, progress) => progress == null
        ? child
        : const Center(
            child: SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
    errorBuilder: (context, _, _) => Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.broken_image_outlined,
            color: SahbiColors.textSecondary,
          ),
          Text(
            L10n.of(context).photoFailed,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 11,
              color: SahbiColors.textSecondary,
            ),
          ),
        ],
      ),
    ),
  );
}

Future<void> openPhotoViewer(
  BuildContext context,
  List<ChatImage> images,
  int start,
) => Navigator.of(context).push(
  MaterialPageRoute<void>(
    fullscreenDialog: true,
    builder: (_) => _PhotoViewer(images: images, start: start),
  ),
);

class _PhotoViewer extends StatefulWidget {
  const _PhotoViewer({required this.images, required this.start});
  final List<ChatImage> images;
  final int start;

  @override
  State<_PhotoViewer> createState() => _PhotoViewerState();
}

class _PhotoViewerState extends State<_PhotoViewer> {
  late int _i = widget.start;
  late final PageController _pc = PageController(initialPage: widget.start);

  @override
  void dispose() {
    _pc.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final img = widget.images[_i];
    final page = Uri.tryParse(img.page);
    final canOpen = page != null && page.scheme == 'https';
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: Text(
          img.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 15),
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: PageView.builder(
              controller: _pc,
              itemCount: widget.images.length,
              onPageChanged: (i) => setState(() => _i = i),
              itemBuilder: (_, i) => InteractiveViewer(
                maxScale: 4,
                child: NetPhoto(url: widget.images[i].url),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 8, 16),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '${img.source} · ${_i + 1}/${widget.images.length}',
                    style: const TextStyle(color: SahbiColors.textSecondary),
                  ),
                ),
                if (canOpen)
                  TextButton.icon(
                    onPressed: () =>
                        launchUrl(page, mode: LaunchMode.externalApplication),
                    icon: const Icon(Icons.open_in_new_rounded, size: 18),
                    label: Text(l.photoOpenPage),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Photos the robot is showing, as a card over the face screen.
class PhotoOverlayCard extends StatelessWidget {
  const PhotoOverlayCard({
    super.key,
    required this.images,
    required this.query,
    required this.onClose,
  });
  final List<ChatImage> images;
  final String query;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    return Material(
      color: SahbiColors.surface.withValues(alpha: 0.96),
      elevation: 8,
      borderRadius: BorderRadius.circular(18),
      child: Padding(
        padding: const EdgeInsetsDirectional.fromSTEB(12, 4, 4, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.photo_library_rounded,
                  size: 18,
                  color: SahbiColors.turquoise,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    l.photosFor(query),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                IconButton(
                  key: const Key('photos_close'),
                  tooltip: l.ytClose,
                  icon: const Icon(Icons.close_rounded),
                  onPressed: onClose,
                ),
              ],
            ),
            PhotoStrip(images: images, height: 170),
          ],
        ),
      ),
    );
  }
}
