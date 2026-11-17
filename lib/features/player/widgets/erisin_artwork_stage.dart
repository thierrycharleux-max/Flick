import 'package:flutter/material.dart';
import 'package:flick/models/song.dart';
import 'package:flick/widgets/common/cached_image_widget.dart';

/// The cover uses the space freed by moving track identity to the right panel.
class ErisinArtworkStage extends StatelessWidget {
  const ErisinArtworkStage({
    super.key,
    required this.song,
    this.footerHeight = 48,
    this.footer,
  });

  final Song song;
  final double footerHeight;
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
      child: Column(
        children: [
          Expanded(
            child: Center(
              child: AspectRatio(
                aspectRatio: 1,
                child: Container(
                  key: const ValueKey('erisin_player_cover'),
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(20),
                    child: CachedImageWidget(
                      imagePath: song.albumArt,
                      audioSourcePath: song.filePath,
                      fit: BoxFit.contain,
                      useThumbnail: true,
                      thumbnailWidth: 640,
                      thumbnailHeight: 640,
                    ),
                  ),
                ),
              ),
            ),
          ),
          if (footer != null)
            Visibility(
              visible: false,
              maintainSize: true,
              maintainState: true,
              maintainAnimation: true,
              child: footer!,
            )
          else
            SizedBox(height: footerHeight),
        ],
      ),
    );
  }
}

/// Pinned identity above the waveform, matching the approved landscape preview.
class ErisinPlaybackPanel extends StatelessWidget {
  const ErisinPlaybackPanel({
    super.key,
    required this.song,
    required this.onArtist,
    required this.onAlbum,
    required this.controls,
  });

  final Song song;
  final VoidCallback onArtist;
  final VoidCallback onAlbum;
  final Widget controls;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) => MediaQuery(
        data: MediaQuery.of(context).copyWith(size: constraints.biggest),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 20, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    song.title,
                    key: const ValueKey('erisin_player_title'),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: constraints.maxWidth >= 400 ? 36 : 28,
                      height: 1.15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Container(
                    key: const ValueKey('erisin_player_identity'),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.045),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.10),
                      ),
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (song.album?.isNotEmpty == true) ...[
                          GestureDetector(
                            onTap: onAlbum,
                            child: Text(
                              song.album!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                                color: Colors.white70,
                              ),
                            ),
                          ),
                          const SizedBox(height: 5),
                        ],
                        GestureDetector(
                          onTap: onArtist,
                          child: Text(
                            song.artist,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 12,
                              color: Colors.white60,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: LayoutBuilder(
                builder: (context, remaining) => MediaQuery(
                  data: MediaQuery.of(
                    context,
                  ).copyWith(size: remaining.biggest),
                  child: Align(
                    alignment: const Alignment(0, 0.3),
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: SizedBox(
                        width: constraints.maxWidth,
                        child: controls,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
