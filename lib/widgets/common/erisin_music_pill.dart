import 'package:flutter/material.dart';
import 'package:flick/models/song.dart';
import 'package:flick/widgets/common/cached_image_widget.dart';

/// A fixed, reserved top shortcut to the player; it never expands over a page.
class ErisinMusicPill extends StatelessWidget {
  const ErisinMusicPill({super.key, required this.song, required this.isPlaying,
    required this.onOpen, required this.onPlayPause});

  final Song song;
  final bool isPlaying;
  final VoidCallback onOpen;
  final VoidCallback onPlayPause;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SizedBox(
        key: const ValueKey('erisin_music_pill'),
        width: 320,
        height: 40,
        child: Material(
          color: const Color(0xEE171B24),
          borderRadius: BorderRadius.circular(20),
          clipBehavior: Clip.antiAlias,
          child: Row(children: [
            Expanded(child: InkWell(
              onTap: onOpen,
              child: Row(children: [
                SizedBox(width: 40, height: 40,
                  child: CachedImageWidget(imagePath: song.albumArt,
                    audioSourcePath: song.filePath, useThumbnail: true,
                    thumbnailWidth: 80, thumbnailHeight: 80)),
                const SizedBox(width: 10),
                Expanded(child: Text(song.title, maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 13, color: Colors.white))),
              ]),
            )),
            IconButton(
              onPressed: onPlayPause,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints.tightFor(width: 40, height: 40),
              icon: Icon(isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                color: Colors.white, size: 24),
            ),
          ]),
        ),
      ),
    );
  }
}
