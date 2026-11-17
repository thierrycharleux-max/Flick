import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:flick/core/theme/adaptive_color_provider.dart';

/// Keeps playback outside the scrolling tracks on shallow landscape displays.
class AlbumLandscapeLayout extends StatelessWidget {
  const AlbumLandscapeLayout({
    super.key,
    required this.title,
    required this.artist,
    required this.meta,
    required this.artwork,
    required this.actions,
    required this.tracks,
    required this.onBack,
  });

  final String title;
  final String artist;
  final String meta;
  final Widget artwork;
  final Widget actions;
  final Widget tracks;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final split = constraints.maxWidth >= 560;
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                child: Row(
                  children: [
                    IconButton(
                      tooltip: MaterialLocalizations.of(
                        context,
                      ).backButtonTooltip,
                      icon: Icon(
                        LucideIcons.chevronLeft,
                        color: context.adaptiveTextPrimary,
                      ),
                      onPressed: onBack,
                    ),
                    if (!split) ...[
                      SizedBox(
                        width: 44,
                        height: 44,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: artwork,
                        ),
                      ),
                      const SizedBox(width: 12),
                    ],
                    Expanded(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.titleLarge
                                ?.copyWith(
                                  color: context.adaptiveTextPrimary,
                                  fontWeight: FontWeight.w700,
                                ),
                          ),
                          if (!split)
                            Text(
                              artist,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(
                                    color: context.adaptiveTextSecondary,
                                  ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                  ],
                ),
              ),
              if (split)
                Expanded(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SizedBox(
                        width: (constraints.maxWidth * 0.42)
                            .clamp(260.0, 320.0)
                            .toDouble(),
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: LayoutBuilder(
                                  builder: (context, artConstraints) {
                                    final edge = math.min(
                                      artConstraints.maxWidth,
                                      artConstraints.maxHeight,
                                    );
                                    return Center(
                                      child: SizedBox.square(
                                        dimension: edge,
                                        child: ClipRRect(
                                          borderRadius: BorderRadius.circular(
                                            10,
                                          ),
                                          child: artwork,
                                        ),
                                      ),
                                    );
                                  },
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                artist,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.bodyMedium
                                    ?.copyWith(
                                      color: context.adaptiveTextSecondary,
                                    ),
                              ),
                              Text(
                                meta,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.bodySmall
                                    ?.copyWith(
                                      color: context.adaptiveTextTertiary,
                                    ),
                              ),
                              const SizedBox(height: 8),
                              _fixedActions(),
                            ],
                          ),
                        ),
                      ),
                      Expanded(child: _trackViewport()),
                    ],
                  ),
                )
              else ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
                  child: _fixedActions(),
                ),
                Expanded(child: _trackViewport()),
              ],
            ],
          );
        },
      ),
    );
  }

  Widget _fixedActions() =>
      KeyedSubtree(key: const ValueKey('album_fixed_actions'), child: actions);

  Widget _trackViewport() =>
      KeyedSubtree(key: const ValueKey('album_tracks_viewport'), child: tracks);
}
