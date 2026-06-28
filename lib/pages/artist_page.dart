import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/artist_info.dart';
import '../models/music_model.dart';
import '../services/music_service.dart';
import '../services/musicbrainz_service.dart';
import '../services/responsive.dart';
import '../services/youtube_music_service.dart';
import '../widgets/cover_art_texture.dart';

class ArtistPage extends StatefulWidget {
  final String artistName;
  final String? localCoverPath;
  const ArtistPage({super.key, required this.artistName, this.localCoverPath});

  @override
  State<ArtistPage> createState() => _ArtistPageState();
}

class _ArtistPageState extends State<ArtistPage> with SingleTickerProviderStateMixin {
  ArtistInfo? _artist;
  String? _coverUrl;
  List<ArtistInfo> _relatedArtists = [];
  bool _isLoading = true;
  bool _hasError = false;
  bool _bioExpanded = false;
  late final AnimationController _morphController;
  late final Animation<double> _morphAnimation;

  List<YoutubeMusicResult> _ytResults = [];
  bool _isYtLoading = false;

  @override
  void initState() {
    super.initState();
    _morphController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _morphAnimation = CurvedAnimation(
      parent: _morphController,
      curve: Curves.easeOutCubic,
    );
    _loadData();
  }

  @override
  void dispose() {
    _morphController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() { _isLoading = true; _hasError = false; });
    try {
      final service = MusicBrainzService.instance;
      final artist = await service.searchArtist(widget.artistName);
      if (!mounted) return;
      if (artist.isEmpty) {
        setState(() { _isLoading = false; _artist = ArtistInfo(name: widget.artistName); });
        _morphController.forward();
        return;
      }
      String? coverUrl;
      if (artist.mbid.isNotEmpty) coverUrl = await service.fetchCoverArt(artist.mbid);
      // Fallback to Wikidata image if MusicBrainz cover art not found
      if (coverUrl == null || coverUrl.isEmpty) {
        if (artist.wikidataId != null && artist.wikidataId!.isNotEmpty) {
          coverUrl = await service.fetchWikidataImage(artist.wikidataId!);
        }
      }
      List<ArtistInfo> related = [];
      if (artist.mbid.isNotEmpty) related = await service.fetchRelatedArtists(artist.mbid);
      if (!mounted) return;
      setState(() { _artist = artist; _coverUrl = coverUrl; _relatedArtists = related; _isLoading = false; });
      _morphController.forward();
      _searchYouTubeMusic();
    } catch (_) {
      if (mounted) {
        setState(() => _hasError = true);
        _morphController.forward();
      }
    }
  }

  bool _matchesArtist(Music m, String artistName) {
    final target = artistName.toLowerCase();
    final parts = m.artist.toLowerCase().split(',').map((s) => s.trim());
    return parts.any((p) => p == target || target.contains(p) || p.contains(target));
  }

  Future<void> _searchYouTubeMusic() async {
    if (!YoutubeMusicService.isSupported) return;
    setState(() => _isYtLoading = true);
    try {
      final results = await YoutubeMusicService().search(
        query: widget.artistName, filter: 'songs', limit: 15,
      );
      if (!mounted) return;
      setState(() { _ytResults = results; _isYtLoading = false; });
    } catch (_) {
      if (mounted) setState(() => _isYtLoading = false);
    }
  }

  Future<void> _playYtResult(YoutubeMusicResult result) async {
    final musicService = context.read<MusicService>();
    final ytService = YoutubeMusicService();
    try {
      final stream = await ytService.stream(result, audioOnly: true);
      if (!mounted) return;
      final music = Music(
        id: 'ytm:${stream.videoId.isNotEmpty ? stream.videoId : result.videoId}',
        title: stream.displayTitle,
        artist: stream.displayArtist,
        album: stream.album.isEmpty ? 'YouTube Music' : stream.album,
        filePath: stream.url,
        coverPath: stream.thumbnailUrl,
        httpHeaders: stream.httpHeaders,
        genre: 'YouTube Music',
        duration: stream.durationSeconds > 0 ? Duration(seconds: stream.durationSeconds) : null,
      );
      await musicService.playStreamingMusic(music);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (Responsive.isDesktop) return _buildDesktopPanel(theme);
    return _buildMobilePage(theme);
  }

  Widget _buildDesktopPanel(ThemeData theme) {
    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      body: _buildScrollableContent(theme),
    );
  }

  Widget _buildMobilePage(ThemeData theme) {
    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      body: _buildScrollableContent(theme),
    );
  }

  Widget _buildScrollableContent(ThemeData theme) {
    final expandedHeight = Responsive.isDesktop ? 400.0 : 340.0;
    return CustomScrollView(
      physics: const BouncingScrollPhysics(),
      slivers: [
        SliverAppBar(
          expandedHeight: expandedHeight,
          pinned: true,
          backgroundColor: theme.colorScheme.surface,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios_new_rounded),
            onPressed: () => Navigator.of(context).pop(),
          ),
          flexibleSpace: FlexibleSpaceBar(
            background: _buildHero(theme, height: expandedHeight),
          ),
        ),
        SliverToBoxAdapter(child: _buildContent(theme)),
      ],
    );
  }

  Widget _buildHero(ThemeData theme, {required double height}) {
    final coverUrl = _coverUrl;
    final localCover = widget.localCoverPath;
    return SizedBox(
      height: height, width: double.infinity,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (coverUrl != null && coverUrl.isNotEmpty)
            Hero(
              tag: 'artist-cover-${widget.artistName}',
              child: Image.network(coverUrl, fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => _fallbackCover(theme)),
            )
          else if (localCover != null && localCover.isNotEmpty)
            Hero(
              tag: 'artist-cover-${widget.artistName}',
              child: CoverArtTexture(coverArtPath: localCover,
                width: double.infinity, height: double.infinity,
                filterQuality: FilterQuality.medium),
            )
          else
            Hero(
              tag: 'artist-cover-${widget.artistName}',
              child: _fallbackCover(theme),
            ),
          _buildGradientOverlay(theme),
          if (_isLoading) Container(
            color: Colors.black.withValues(alpha: 0.3),
            child: const Center(child: CircularProgressIndicator(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  Widget _buildGradientOverlay(ThemeData theme) {
    return AnimatedBuilder(
      animation: _morphAnimation,
      builder: (context, child) {
        final t = _morphAnimation.value;
        return Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.transparent,
                Colors.transparent,
                theme.colorScheme.surface.withValues(alpha: 0.3 + t * 0.4),
                theme.colorScheme.surface,
              ],
              stops: const [0.0, 0.4, 0.75, 1.0],
            ),
          ),
        );
      },
    );
  }

  Widget _fallbackCover(ThemeData theme) {
    return Container(
      color: theme.colorScheme.surfaceContainerHighest,
      child: Center(child: Icon(Icons.person_rounded, size: 80,
        color: theme.colorScheme.onSurface.withValues(alpha: 0.15))),
    );
  }

  Widget _buildContent(ThemeData theme) {
    if (_isLoading) return _buildLoading(theme);
    if (_hasError) return _buildError(theme);
    final artist = _artist;
    return AnimatedBuilder(
      animation: _morphAnimation,
      builder: (context, child) {
        return Opacity(
          opacity: _morphAnimation.value,
          child: Transform.translate(
            offset: Offset(0, 20 * (1 - _morphAnimation.value)),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 100),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                _buildArtistTitle(theme, artist),
                if (artist?.disambiguation.isNotEmpty == true) ...[
                  const SizedBox(height: 4),
                  Text(artist!.disambiguation, style: TextStyle(fontSize: 13,
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.5))),
                ],
                if (artist?.type != null) ...[
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primary.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(artist!.type!, style: TextStyle(fontSize: 11,
                      fontWeight: FontWeight.w600, color: theme.colorScheme.primary)),
                  ),
                ],
                const SizedBox(height: 20),
                _buildMetaChips(theme, artist),
                const SizedBox(height: 24),
                if (artist?.biography != null && artist!.biography!.isNotEmpty)
                  _buildBio(theme, artist),
                _buildLocalSongs(theme),
                if (_relatedArtists.isNotEmpty) _buildRelated(theme),
                if (artist?.relations.isNotEmpty == true) _buildLinks(theme, artist!),
              ]),
            ),
          ),
        );
      },
    );
  }

  Widget _buildArtistTitle(ThemeData theme, ArtistInfo? artist) {
    final name = artist?.name ?? widget.artistName;
    final parts = name.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
    if (parts.length <= 1) {
      return Text(name, style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900,
        color: theme.colorScheme.onSurface, letterSpacing: -0.5));
    }
    return Wrap(
      spacing: 8, runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        for (int i = 0; i < parts.length; i++) ...[
          GestureDetector(
            onTap: () {
              Navigator.of(context).push(PageRouteBuilder(
                transitionDuration: const Duration(milliseconds: 320),
                reverseTransitionDuration: const Duration(milliseconds: 280),
                pageBuilder: (_, __, ___) => ArtistPage(artistName: parts[i]),
                transitionsBuilder: (_, anim, __, child) => FadeTransition(
                  opacity: CurvedAnimation(parent: anim, curve: Curves.easeOutCubic),
                  child: child,
                ),
              ));
            },
            child: Text(parts[i], style: TextStyle(
              fontSize: 28, fontWeight: FontWeight.w900,
              color: theme.colorScheme.primary, letterSpacing: -0.5,
              decoration: TextDecoration.underline,
              decorationColor: theme.colorScheme.primary.withValues(alpha: 0.4),
            )),
          ),
          if (i < parts.length - 1) Text(',', style: TextStyle(fontSize: 28,
            fontWeight: FontWeight.w900,
            color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
            letterSpacing: -0.5)),
        ],
      ],
    );
  }

  Widget _buildLoading(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 100),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        _skel(theme, 200, 28), const SizedBox(height: 12), _skel(theme, 140, 16),
        const SizedBox(height: 20),
        Row(children: [_skel(theme, 80, 28), const SizedBox(width: 8), _skel(theme, 60, 28),
          const SizedBox(width: 8), _skel(theme, 90, 28)]),
        const SizedBox(height: 24),
        _skel(theme, double.infinity, 60), const SizedBox(height: 16),
        _skel(theme, double.infinity, 60),
      ]),
    );
  }

  Widget _skel(ThemeData theme, double w, double h) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 600),
      width: w, height: h,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3)),
    );
  }

  Widget _buildError(ThemeData theme) {
    return Center(
      child: Padding(padding: const EdgeInsets.all(32), child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.wifi_off_rounded, size: 48,
          color: theme.colorScheme.onSurface.withValues(alpha: 0.2)),
        const SizedBox(height: 16),
        Text('Unable to load artist info', style: TextStyle(fontSize: 16,
          fontWeight: FontWeight.w600,
          color: theme.colorScheme.onSurface.withValues(alpha: 0.6))),
        const SizedBox(height: 8),
        Text('Check your connection and try again', style: TextStyle(fontSize: 13,
          color: theme.colorScheme.onSurface.withValues(alpha: 0.4))),
        const SizedBox(height: 20),
        FilledButton.icon(onPressed: _loadData,
          icon: const Icon(Icons.refresh_rounded, size: 18),
          label: const Text('Retry')),
      ])),
    );
  }

  Widget _buildMetaChips(ThemeData theme, ArtistInfo? artist) {
    final chips = <_MetaChip>[];
    if (artist?.country.isNotEmpty == true)
      chips.add(_MetaChip(icon: Icons.public_rounded, label: artist!.country, theme: theme));
    if (artist?.activeYears.isNotEmpty == true)
      chips.add(_MetaChip(icon: Icons.date_range_rounded, label: artist!.activeYears, theme: theme));
    if (artist?.albumCount != null)
      chips.add(_MetaChip(icon: Icons.album_rounded, label: '${artist!.albumCount} albums', theme: theme));
    if (chips.isEmpty) return const SizedBox.shrink();
    return Wrap(spacing: 8, runSpacing: 8, children: chips);
  }

  Widget _buildBio(ThemeData theme, ArtistInfo artist) {
    final bio = artist.biography!;
    final isLong = bio.length > 300;
    final text = _bioExpanded || !isLong ? bio : '${bio.substring(0, 300)}...';
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('About', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
      const SizedBox(height: 10),
      GestureDetector(
        onTap: isLong ? () => setState(() => _bioExpanded = !_bioExpanded) : null,
        child: Text(text, style: TextStyle(fontSize: 14, height: 1.5,
          color: theme.colorScheme.onSurface.withValues(alpha: 0.7))),
      ),
      if (isLong) ...[
        const SizedBox(height: 6),
        GestureDetector(
          onTap: () => setState(() => _bioExpanded = !_bioExpanded),
          child: Text(_bioExpanded ? 'Show less' : 'Read more',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700,
              color: theme.colorScheme.primary)),
        ),
      ],
      const SizedBox(height: 20),
    ]);
  }

  Widget _buildLocalSongs(ThemeData theme) {
    return Consumer<MusicService>(builder: (context, musicService, _) {
      final songs = musicService.musicList
          .where((m) => _matchesArtist(m, widget.artistName)).toList();
      final ytSongs = _ytResults;
      final hasLocal = songs.isNotEmpty;
      final hasYt = ytSongs.isNotEmpty;
      if (!hasLocal && !hasYt && !_isYtLoading) return const SizedBox.shrink();
      return Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        if (hasLocal) ...[
          const Text('Your Library', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
          const SizedBox(height: 10),
          ...songs.take(8).map((m) => _SongTile(music: m, songs: songs)),
          if (songs.length > 8) ...[
            const SizedBox(height: 8),
            Center(child: Text('+${songs.length - 8} more songs',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600,
                color: theme.colorScheme.primary))),
          ],
          const SizedBox(height: 24),
        ],
        if (_isYtLoading) ...[
          const Text('YouTube Music', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
          const SizedBox(height: 12),
          SizedBox(height: 60, child: Center(child: CircularProgressIndicator(
            strokeWidth: 2, color: theme.colorScheme.primary))),
          const SizedBox(height: 24),
        ],
        if (hasYt) ...[
          Text('YouTube Music', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800,
            color: theme.colorScheme.onSurface)),
          const SizedBox(height: 10),
          ...ytSongs.map((r) => _YtResultTile(result: r, onTap: () => _playYtResult(r))),
          const SizedBox(height: 24),
        ],
      ]);
    });
  }

  Widget _buildRelated(ThemeData theme) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
      const Text('Related Artists', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
      const SizedBox(height: 12),
      SizedBox(
        height: 130,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: _relatedArtists.length,
          separatorBuilder: (_, __) => const SizedBox(width: 16),
          itemBuilder: (context, index) {
            final r = _relatedArtists[index];
            return GestureDetector(
              onTap: () => Navigator.of(context).push(PageRouteBuilder(
                transitionDuration: const Duration(milliseconds: 320),
                reverseTransitionDuration: const Duration(milliseconds: 280),
                pageBuilder: (_, __, ___) => ArtistPage(artistName: r.name),
                transitionsBuilder: (_, anim, __, child) => FadeTransition(
                  opacity: CurvedAnimation(parent: anim, curve: Curves.easeOutCubic),
                  child: child,
                ),
              )),
              child: SizedBox(width: 100, child: Column(children: [
                Container(
                  width: 80, height: 80,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.person_rounded, size: 36,
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.3)),
                ),
                const SizedBox(height: 8),
                Text(r.name, maxLines: 2, overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600,
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.8))),
              ])),
            );
          },
        ),
      ),
      const SizedBox(height: 24),
    ]);
  }

  Widget _buildLinks(ThemeData theme, ArtistInfo artist) {
    final links = <(String, String, IconData)>[];
    if (artist.musicBrainzUrl != null)
      links.add(('MusicBrainz', artist.musicBrainzUrl!, Icons.category_rounded));
    if (artist.lastFmUrl != null)
      links.add(('Last.fm', artist.lastFmUrl!, Icons.waves_rounded));
    if (artist.wikidataId != null)
      links.add(('Wikidata', 'https://www.wikidata.org/wiki/${artist.wikidataId}',
        Icons.account_balance_rounded));
    for (final rel in artist.relations) {
      if (rel.targetType == 'url' && rel.target.isNotEmpty &&
          !rel.target.contains('musicbrainz.org') &&
          !rel.target.contains('last.fm') &&
          !rel.target.contains('wikidata.org')) {
        links.add((rel.type.isNotEmpty ? rel.type : 'Link', rel.target, Icons.link_rounded));
      }
    }
    if (links.isEmpty) return const SizedBox.shrink();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
      const Text('Links', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
      const SizedBox(height: 10),
      ...links.take(6).map((l) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: GestureDetector(
          onTap: () async {
            final uri = Uri.parse(l.$2);
            if (await canLaunchUrl(uri)) await launchUrl(uri, mode: LaunchMode.externalApplication);
          },
          child: Row(children: [
            Icon(l.$3, size: 18, color: theme.colorScheme.primary),
            const SizedBox(width: 10),
            Expanded(child: Text(l.$1, style: TextStyle(fontSize: 14,
              fontWeight: FontWeight.w600, color: theme.colorScheme.primary))),
            Icon(Icons.open_in_new_rounded, size: 14,
              color: theme.colorScheme.onSurface.withValues(alpha: 0.3)),
          ]),
        ),
      )),
    ]);
  }
}

class _SongTile extends StatelessWidget {
  final Music music;
  final List<Music> songs;
  const _SongTile({required this.music, required this.songs});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final musicService = context.read<MusicService>();
    final currentMusic = context.select<MusicService, Music?>((s) => s.currentMusic);
    final isPlaying = currentMusic?.id == music.id;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      leading: ClipRRect(borderRadius: BorderRadius.circular(6), child: SizedBox(
        width: 44, height: 44,
        child: music.coverPath.isNotEmpty
            ? CoverArtTexture(coverArtPath: music.coverPath, width: 44, height: 44)
            : Container(color: theme.colorScheme.surfaceContainerHighest,
                child: Icon(Icons.music_note_rounded,
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.4))),
      )),
      title: Text(music.title, maxLines: 1, overflow: TextOverflow.ellipsis,
        style: TextStyle(fontWeight: isPlaying ? FontWeight.w700 : FontWeight.w600,
          fontSize: 14, color: isPlaying ? theme.colorScheme.primary : null)),
      subtitle: Text(music.album.isNotEmpty ? music.album : '',
        maxLines: 1, overflow: TextOverflow.ellipsis,
        style: TextStyle(fontSize: 12,
          color: theme.colorScheme.onSurface.withValues(alpha: 0.5))),
      trailing: Text(_fmt(music.duration),
        style: TextStyle(fontSize: 12,
          color: theme.colorScheme.onSurface.withValues(alpha: 0.4))),
      onTap: () => musicService.playMusicFromQueue(songs, music),
    );
  }

  String _fmt(Duration? d) {
    if (d == null) return '';
    return '${d.inMinutes}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';
  }
}

class _MetaChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final ThemeData theme;
  const _MetaChip({required this.icon, required this.label, required this.theme});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(20)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 14, color: theme.colorScheme.onSurface.withValues(alpha: 0.6)),
        const SizedBox(width: 6),
        Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600,
          color: theme.colorScheme.onSurface.withValues(alpha: 0.7))),
      ]),
    );
  }
}

class _YtResultTile extends StatelessWidget {
  final YoutubeMusicResult result;
  final VoidCallback onTap;
  const _YtResultTile({required this.result, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      leading: ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: SizedBox(
          width: 44, height: 44,
          child: result.thumbnailUrl.isNotEmpty
              ? Image.network(result.thumbnailUrl, fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Container(
                    color: theme.colorScheme.surfaceContainerHighest,
                    child: Icon(Icons.music_note_rounded,
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.4))))
              : Container(color: theme.colorScheme.surfaceContainerHighest,
                  child: Icon(Icons.music_note_rounded,
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.4))),
        ),
      ),
      title: Text(result.displayTitle, maxLines: 1, overflow: TextOverflow.ellipsis,
        style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600,
          color: theme.colorScheme.onSurface)),
      subtitle: Row(children: [
        Icon(Icons.play_circle_outline_rounded, size: 12,
          color: theme.colorScheme.primary),
        const SizedBox(width: 4),
        Text(result.displayArtist, maxLines: 1, overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: 12,
            color: theme.colorScheme.onSurface.withValues(alpha: 0.5))),
        if (result.duration.isNotEmpty) ...[
          const SizedBox(width: 8),
          Text(result.duration, style: TextStyle(fontSize: 12,
            color: theme.colorScheme.onSurface.withValues(alpha: 0.4))),
        ],
      ]),
      trailing: Icon(Icons.play_arrow_rounded, color: theme.colorScheme.primary, size: 22),
      onTap: onTap,
    );
  }
}
