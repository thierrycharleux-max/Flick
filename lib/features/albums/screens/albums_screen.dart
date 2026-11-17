import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flick/core/theme/app_colors.dart';
import 'package:flick/core/theme/adaptive_color_provider.dart';
import 'package:flick/core/constants/app_constants.dart';
import 'package:flick/core/utils/responsive.dart';
import 'package:flick/core/utils/navigation_helper.dart';
import 'package:flick/core/utils/string_sort_utils.dart';
import 'package:flick/models/album_completeness.dart';
import 'package:flick/features/albums/widgets/album_completeness_status.dart';
import 'package:flick/models/song.dart';
import 'package:flick/data/repositories/song_repository.dart';
import 'package:flick/features/albums/screens/album_detail_screen.dart';
import 'package:flick/features/player/widgets/ambient_background.dart';
import 'package:flick/providers/providers.dart';
import 'package:flick/services/player_service.dart';
import 'package:flick/services/motion_art/animated_artwork_service.dart';
import 'package:flick/widgets/common/cached_image_widget.dart';
import 'package:flick/widgets/common/surface_icon_button.dart';
import 'package:flick/widgets/common/glass_bottom_sheet.dart';
import 'package:flick/l10n/l10n.dart';
import 'package:flick/widgets/common/library_heading.dart';

enum AlbumSortOption { name, artist, tracks }

/// Albums screen with masonry grid of album artwork.
class AlbumsScreen extends ConsumerStatefulWidget {
  const AlbumsScreen({super.key});

  @override
  ConsumerState<AlbumsScreen> createState() => _AlbumsScreenState();
}

class _AlbumsScreenState extends ConsumerState<AlbumsScreen> {
  final SongRepository _songRepository = SongRepository();
  final PlayerService _playerService = PlayerService();
  List<AlbumGroup> _albums = [];
  List<AlbumGroup> _sortedAlbums = [];
  bool _isLoading = true;
  AlbumSortOption _sortOption = AlbumSortOption.artist;
  int _loadGeneration = 0;
  bool _openingAlbum = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadSortOption();
      _loadAlbums();
    });
  }

  Future<void> _loadSortOption() async {
    final prefs = await SharedPreferences.getInstance();
    final value = prefs.getString('albums_sort_option');
    if (!mounted) return;
    final option = AlbumSortOption.values.firstWhere(
      (v) => v.name == value,
      orElse: () => AlbumSortOption.artist,
    );
    if (option != _sortOption) {
      setState(() => _sortOption = option);
    }
  }

  Future<void> _setSortOption(AlbumSortOption option) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('albums_sort_option', option.name);
    if (mounted) {
      setState(() {
        _sortOption = option;
        _applySorting();
      });
    }
  }

  Future<void> _loadAlbums() async {
    final generation = ++_loadGeneration;
    final albums = await _songRepository.getAlbumGroups();
    if (!mounted || generation != _loadGeneration) return;
    setState(() {
      _albums = albums;
      _sortedAlbums = List.from(albums);
      _applySorting();
      _isLoading = false;
    });
    unawaited(_prefetchMotionArt(albums));
  }

  // Warm a bounded set of album lookups so opening an album hero or playing a
  // track does not wait on a cold network call. Only metadata is fetched here;
  // the video itself streams lazily when a widget actually becomes visible.
  // Sequential with a gap because boidu's upstream rate-limits bursts.
  Future<void> _prefetchMotionArt(List<AlbumGroup> albums) async {
    final prefs = ref.read(appPreferencesProvider);
    if (!prefs.animatedAlbumArt || !prefs.animationsEnabled) return;
    final service = AnimatedArtworkService.instance;
    for (final album in albums.take(8)) {
      if (!mounted) return;
      await service.getAnimatedArtworkForAlbum(
        albumName: album.albumName,
        artist: album.albumArtist,
        representativeSongTitle: album.songs.isNotEmpty
            ? album.songs.first.title
            : null,
      );
      await Future<void>.delayed(const Duration(milliseconds: 400));
    }
  }

  void _applySorting() {
    switch (_sortOption) {
      case AlbumSortOption.name:
        _sortedAlbums.sort(
          (a, b) => compareCaseInsensitive(a.albumName, b.albumName),
        );
      case AlbumSortOption.artist:
        _sortedAlbums.sort((a, b) {
          final artistCompare = compareCaseInsensitive(
            a.albumArtist,
            b.albumArtist,
          );
          if (artistCompare != 0) return artistCompare;
          return compareCaseInsensitive(a.albumName, b.albumName);
        });
      case AlbumSortOption.tracks:
        _sortedAlbums.sort((a, b) => b.songs.length.compareTo(a.songs.length));
    }
  }

  void _showSortSheet() {
    showModalBottomSheet(
      useRootNavigator: true,
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => _AlbumSortSheet(
        currentOption: _sortOption,
        onSelected: (option) => _setSortOption(option),
      ),
    );
  }

  String? _getAlbumArt(List<Song> songs) {
    for (final song in songs) {
      if (song.albumArt != null && song.albumArt!.isNotEmpty) {
        return song.albumArt;
      }
    }
    return null;
  }

  // ponytail: pick the source path of the SAME song whose albumArt we'd use,
  // so CachedImageWidget's embedded-art fallback targets the matching track
  // instead of an unrelated one. Falls back to first non-empty filePath only
  // when no song has albumArt.
  String? _getArtworkSourcePath(List<Song> songs) {
    for (final song in songs) {
      if (song.albumArt != null && song.albumArt!.isNotEmpty) {
        final fp = song.filePath;
        if (fp != null && fp.isNotEmpty) return fp;
      }
    }
    for (final song in songs) {
      final fp = song.filePath;
      if (fp != null && fp.isNotEmpty) return fp;
    }
    return null;
  }

  Future<void> _openAlbumDetail(AlbumGroup album) async {
    if (_openingAlbum) return;
    _openingAlbum = true;
    try {
      await NavigationHelper.pushFade<void>(
        context,
        (_) => AlbumDetailScreen(
          albumName: album.albumName,
          albumArtist: album.albumArtist,
          songs: album.songs,
          albumArt: _getAlbumArt(album.songs),
          albumArtSourcePath: _getArtworkSourcePath(album.songs),
          playerService: _playerService,
          libraryAlbums: _albums,
        ),
      );
    } finally {
      _openingAlbum = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentSong = ref.watch(currentSongProvider);

    // Post-scan artwork/metadata writes land after the initial load; reload so
    // covers appear without needing a scroll to rebuild each tile.
    ref.listen(libraryChangeRevisionProvider, (previous, next) {
      if (next.hasValue) _loadAlbums();
    });

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          Positioned.fill(child: AmbientBackground(song: currentSong)),
          SafeArea(
            bottom: false,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildHeader(context),
                Expanded(
                  child: _isLoading
                      ? _buildLoadingState()
                      : _sortedAlbums.isEmpty
                      ? _buildEmptyState()
                      : _buildAlbumsGrid(),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    final landscape =
        MediaQuery.sizeOf(context).width > MediaQuery.sizeOf(context).height;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        AppConstants.spacingLg,
        landscape ? AppConstants.spacingXs : AppConstants.spacingMd,
        AppConstants.spacingLg,
        landscape ? AppConstants.spacingXs : AppConstants.spacingMd,
      ),
      child: Row(
        children: [
          if (Navigator.of(context).canPop()) ...[
            SurfaceIconButton.icon(
              icon: LucideIcons.chevronLeft,
              onPressed: () => Navigator.of(context).pop(),
              iconColor: context.adaptiveTextPrimary,
            ),
            const SizedBox(width: AppConstants.spacingMd),
          ],
          Expanded(
            child: Row(
              children: [
                Flexible(
                  child: LibraryHeading(
                    section: LibrarySection.albums,
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: context.adaptiveTextPrimary,
                    ),
                  ),
                ),
                const SizedBox(width: AppConstants.spacingMd),
                Text(
                  l10n.albums2(_albums.length),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: context.adaptiveTextTertiary,
                  ),
                ),
              ],
            ),
          ),
          SurfaceIconButton.icon(
            icon: Icons.sort_rounded,
            onPressed: _showSortSheet,
            iconColor: context.adaptiveTextPrimary,
          ),
        ],
      ),
    );
  }

  Widget _buildLoadingState() {
    return Center(
      child: CircularProgressIndicator(color: context.adaptiveTextSecondary),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            LucideIcons.disc,
            size: context.responsiveIcon(AppConstants.containerSizeLg),
            color: context.adaptiveTextTertiary.withValues(alpha: 0.5),
          ),
          const SizedBox(height: AppConstants.spacingLg),
          Text(
            l10n.noAlbumsFound,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              color: context.adaptiveTextSecondary,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: AppConstants.spacingSm),
          Text(
            l10n.addMusicWithAlbumTagsTo,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: context.adaptiveTextTertiary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAlbumsGrid() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = MediaQuery.sizeOf(context);
        final landscape = size.width > size.height;
        var columns = landscape
            ? (constraints.maxWidth / 180).floor().clamp(2, 6).toInt()
            : context.gridColumns(compact: 2, phone: 2, tablet: 3);
        // Both the cover and its labels must fit above the persistent bar.
        // Width alone selected three oversized covers on the 240-dpi Erisin.
        double widthForColumns(int count) =>
            (constraints.maxWidth -
                AppConstants.spacingLg * 2 -
                AppConstants.spacingMd * (count - 1)) /
            count;
        final textBudget = 72 * MediaQuery.textScalerOf(context).scale(1);
        final rowHeight = math.max(
          0.0,
          constraints.maxHeight - AppConstants.spacingXs,
        );
        if (landscape) {
          while (columns < 6 &&
              widthForColumns(columns) + textBudget > rowHeight) {
            columns++;
          }
        }
        final cardWidth = widthForColumns(columns);
        final artworkExtent = landscape
            ? math.min(cardWidth, math.max(0.0, rowHeight - textBudget))
            : cardWidth;

        return NotificationListener<ScrollNotification>(
          onNotification: (_) => true,
          child: GridView.builder(
            key: const ValueKey('albums_grid'),
            padding: EdgeInsets.only(
              left: AppConstants.spacingLg,
              right: AppConstants.spacingLg,
              top: AppConstants.spacingXs,
              bottom: landscape
                  ? AppConstants.spacingMd
                  : AppConstants.navBarHeight + 120,
            ),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: columns,
              mainAxisExtent: artworkExtent + textBudget,
              crossAxisSpacing: AppConstants.spacingMd,
              mainAxisSpacing: AppConstants.spacingLg,
            ),
            itemCount: _sortedAlbums.length,
            itemBuilder: (context, index) {
              final album = _sortedAlbums[index];
              return _AlbumCard(
                albumName: album.albumName,
                albumArtist: album.albumArtist,
                songs: album.songs,
                artworkExtent: artworkExtent,
                albumArt: _getAlbumArt(album.songs),
                albumArtSourcePath: _getArtworkSourcePath(album.songs),
                stretchArtwork: ref
                    .watch(appPreferencesProvider)
                    .albumsStretchArtwork,
                onTap: () => _openAlbumDetail(album),
              );
            },
          ),
        );
      },
    );
  }
}

class _AlbumCard extends StatefulWidget {
  final String albumName;
  final String albumArtist;
  final List<Song> songs;
  final String? albumArt;
  final String? albumArtSourcePath;
  final bool stretchArtwork;
  final double artworkExtent;
  final VoidCallback onTap;

  const _AlbumCard({
    required this.albumName,
    required this.albumArtist,
    required this.songs,
    required this.albumArt,
    required this.albumArtSourcePath,
    required this.stretchArtwork,
    required this.artworkExtent,
    required this.onTap,
  });

  @override
  State<_AlbumCard> createState() => _AlbumCardState();
}

class _AlbumCardState extends State<_AlbumCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;
  late Animation<double> _tiltAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: AppConstants.animationFast,
      vsync: this,
    );
    _scaleAnimation = Tween<double>(
      begin: 1.0,
      end: 0.95,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut));
    _tiltAnimation = Tween<double>(
      begin: 0.0,
      end: 0.02,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final devicePixelRatio = MediaQuery.of(context).devicePixelRatio;
    final cardWidth = widget.artworkExtent;
    final artworkTargetWidth = (cardWidth * devicePixelRatio).round();
    // ponytail: only set thumbnailHeight when stretching — passing both
    // cacheWidth+cacheHeight forces the decoder to a square bitmap, which
    // distorts non-square art. Null height lets aspect ratio survive so
    // BoxFit.cover can crop.
    final artworkTargetHeight = widget.stretchArtwork
        ? artworkTargetWidth
        : null;
    final completeness = AlbumCompleteness.resolve(widget.songs);

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Transform(
          alignment: Alignment.center,
          transform: Matrix4.diagonal3Values(
            _scaleAnimation.value,
            _scaleAnimation.value,
            1.0,
          )..rotateZ(_tiltAnimation.value),
          child: child,
        );
      },
      child: RepaintBoundary(
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(AppConstants.radiusLg),
          child: InkWell(
            onTap: widget.onTap,
            onHighlightChanged: (pressed) {
              if (pressed) {
                _controller.forward();
              } else {
                _controller.reverse();
              }
            },
            borderRadius: BorderRadius.circular(AppConstants.radiusLg),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(AppConstants.radiusLg),
              child: SizedBox(
                width: cardWidth,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Album art
                    SizedBox(
                      height: widget.artworkExtent,
                      child: Center(
                        child: SizedBox.square(
                          dimension: widget.artworkExtent,
                          child: Container(
                            width: double.infinity,
                            decoration: BoxDecoration(
                              color: AppColors.surfaceLight,
                              borderRadius: BorderRadius.circular(
                                AppConstants.radiusLg,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.18),
                                  blurRadius: 18,
                                  offset: const Offset(0, 10),
                                ),
                              ],
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(
                                AppConstants.radiusLg,
                              ),
                              child: Stack(
                                fit: StackFit.expand,
                                children: [
                                  CachedImageWidget(
                                    imagePath: widget.albumArt,
                                    audioSourcePath: widget.albumArtSourcePath,
                                    fit: BoxFit.cover,
                                    useThumbnail: true,
                                    thumbnailWidth: artworkTargetWidth,
                                    thumbnailHeight: artworkTargetHeight,
                                    placeholder: _buildPlaceholder(context),
                                    errorWidget: _buildPlaceholder(context),
                                  ),
                                  Positioned.fill(
                                    child: DecoratedBox(
                                      decoration: BoxDecoration(
                                        gradient: LinearGradient(
                                          begin: Alignment.topCenter,
                                          end: Alignment.bottomCenter,
                                          colors: [
                                            Colors.transparent,
                                            Colors.black.withValues(alpha: 0.1),
                                            Colors.black.withValues(
                                              alpha: 0.45,
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                  Positioned(
                                    left: AppConstants.spacingSm,
                                    bottom: AppConstants.spacingSm,
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: AppConstants.spacingSm,
                                        vertical: 6,
                                      ),
                                      decoration: BoxDecoration(
                                        color: Colors.black.withValues(
                                          alpha: 0.55,
                                        ),
                                        borderRadius: BorderRadius.circular(
                                          999,
                                        ),
                                        border: Border.all(
                                          color: Colors.white.withValues(
                                            alpha: 0.12,
                                          ),
                                        ),
                                      ),
                                      child: Text(
                                        l10n.songsCount(widget.songs.length),
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 11,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ),
                                  ),
                                  if (!completeness.isUnknown)
                                    Positioned(
                                      right: AppConstants.spacingSm,
                                      bottom: AppConstants.spacingSm,
                                      child: AlbumCompletenessBadge(
                                        completeness: completeness,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    // Album info
                    Padding(
                      padding: const EdgeInsets.fromLTRB(
                        AppConstants.spacingSm,
                        AppConstants.spacingMd,
                        AppConstants.spacingSm,
                        AppConstants.spacingSm,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.albumName,
                            style: Theme.of(context).textTheme.titleSmall
                                ?.copyWith(
                                  color: context.adaptiveTextPrimary,
                                  fontWeight: FontWeight.w600,
                                ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            widget.albumArtist,
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(
                                  color: context.adaptiveTextSecondary,
                                ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPlaceholder(BuildContext context) {
    return Center(
      child: Icon(
        LucideIcons.disc,
        size: context.responsiveIcon(AppConstants.containerSizeSm),
        color: context.adaptiveTextTertiary.withValues(alpha: 0.5),
      ),
    );
  }
}

class _AlbumSortSheet extends StatelessWidget {
  final AlbumSortOption currentOption;
  final ValueChanged<AlbumSortOption> onSelected;

  const _AlbumSortSheet({
    required this.currentOption,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: AppBottomSheetSurface.decoration,
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.7,
      ),
      child: SingleChildScrollView(
        // Surface reaches the bottom edge; content clears the system
        // gesture/navigation inset.
        padding: EdgeInsets.fromLTRB(
          16,
          12,
          16,
          24 + MediaQuery.paddingOf(context).bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHandle(),
            const SizedBox(height: 16),
            _buildSectionHeader(context, l10n.sortBy),
            const SizedBox(height: 8),
            ...AlbumSortOption.values.map(
              (option) => _buildSortTile(context, option),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHandle() {
    return Center(
      child: Container(
        width: 40,
        height: 4,
        margin: const EdgeInsets.only(top: 8),
        decoration: BoxDecoration(
          color: AppColors.textTertiary,
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    );
  }

  Widget _buildSectionHeader(BuildContext context, String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: context.adaptiveTextTertiary,
          letterSpacing: 1.2,
        ),
      ),
    );
  }

  Widget _buildSortTile(BuildContext context, AlbumSortOption option) {
    final isSelected = currentOption == option;
    final icon = _iconFor(option);
    final label = _labelFor(option);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () {
          onSelected(option);
          Navigator.of(context).pop();
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            color: isSelected
                ? AppColors.accent.withValues(alpha: 0.12)
                : Colors.transparent,
          ),
          child: Row(
            children: [
              Icon(
                icon,
                size: 20,
                color: isSelected
                    ? AppColors.accent
                    : context.adaptiveTextSecondary,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: isSelected
                        ? FontWeight.w600
                        : FontWeight.normal,
                    color: isSelected
                        ? AppColors.accent
                        : context.adaptiveTextPrimary,
                  ),
                ),
              ),
              if (isSelected)
                const Icon(
                  Icons.check_rounded,
                  size: 20,
                  color: AppColors.accent,
                ),
            ],
          ),
        ),
      ),
    );
  }

  IconData _iconFor(AlbumSortOption option) {
    switch (option) {
      case AlbumSortOption.name:
        return LucideIcons.type;
      case AlbumSortOption.artist:
        return LucideIcons.mic;
      case AlbumSortOption.tracks:
        return LucideIcons.hash;
    }
  }

  String _labelFor(AlbumSortOption option) {
    switch (option) {
      case AlbumSortOption.name:
        return l10n.albumName;
      case AlbumSortOption.artist:
        return l10n.artist;
      case AlbumSortOption.tracks:
        return l10n.trackCount;
    }
  }
}
