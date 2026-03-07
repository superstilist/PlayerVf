import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/music_service.dart';
import '../services/responsive.dart';
import '../widgets/music_card.dart';
import '../widgets/playlist_card.dart';
import 'playlist_detail_page.dart';

class HomeScreen extends StatelessWidget {
  final String searchQuery;
  const HomeScreen({super.key, required this.searchQuery});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Consumer<MusicService>(
        builder: (context, musicService, child) {
          final musicList = musicService.musicList.where((m) {
            return m.title.toLowerCase().contains(searchQuery) ||
                   m.artist.toLowerCase().contains(searchQuery);
          }).toList();

          if (musicService.isLoadingSystemMusic && musicList.isEmpty) {
            return const Center(child: CircularProgressIndicator(color: Colors.teal));
          }

          final allPlaylists = musicService.allPlaylists;

          return CustomScrollView(
            physics: const BouncingScrollPhysics(),
            slivers: [
              SliverToBoxAdapter(
                child: RepaintBoundary(
                  child: _buildWelcomeSection(context),
                ),
              ),

              // Playlist Section (Fixed Card Size)
              if (searchQuery.isEmpty)
                SliverToBoxAdapter(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: EdgeInsets.fromLTRB(24.w, 16.h, 24.w, 16.h),
                        child: Text(
                          'Your Library',
                          style: TextStyle(
                            fontSize: 20.sp,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                      ),
                      SizedBox(
                        height: 180.s, // Fixed height for playlist cards
                        child: ListView.builder(
                          scrollDirection: Axis.horizontal,
                          padding: EdgeInsets.symmetric(horizontal: 16.w),
                          itemCount: allPlaylists.length,
                          itemBuilder: (context, index) {
                            final playlist = allPlaylists[index];
                            return Padding(
                              padding: EdgeInsets.symmetric(horizontal: 8.w),
                              child: SizedBox(
                                width: 160.s, // Fixed width for playlist cards
                                child: PlaylistCard(
                                  playlist: playlist,
                                  onTap: () {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (context) => PlaylistDetailPage(playlist: playlist),
                                      ),
                                    );
                                  },
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                      SizedBox(height: 32.h),
                    ],
                  ),
                ),

              // Music List Header
              SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(24.w, 0, 24.w, 16.h),
                  child: Text(
                    searchQuery.isEmpty ? 'Recently Added' : 'Search Results',
                    style: TextStyle(
                      fontSize: 20.sp,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
              
              // Optimized Grid/List for Music
              SliverPadding(
                padding: EdgeInsets.symmetric(horizontal: 16.w),
                sliver: SliverGrid(
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: Responsive.isDesktop ? 6 : (Responsive.isTablet ? 4 : 2),
                    mainAxisSpacing: 16.s,
                    crossAxisSpacing: 16.s,
                    childAspectRatio: 1.0, // Force 1:1 Square
                  ),
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
                      final music = musicList[index];
                      return MusicCard(
                        key: ValueKey(music.id),
                        music: music,
                        onTap: () {
                          musicService.currentIndex = musicService.musicList.indexOf(music);
                          musicService.play();
                        },
                      );
                    },
                    childCount: musicList.length,
                  ),
                ),
              ),
              SliverToBoxAdapter(child: SizedBox(height: 100.h)),
            ],
          );
        },
      ),
    );
  }

  Widget _buildWelcomeSection(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(24.w, 40.h, 24.w, 24.h),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Good Listening',
            style: TextStyle(
              fontSize: 32.sp,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          SizedBox(height: 8.h),
          Text(
            'Your high-fidelity collection',
            style: TextStyle(
              fontSize: 16.sp,
              color: Colors.white60,
            ),
          ),
        ],
      ),
    );
  }
}
