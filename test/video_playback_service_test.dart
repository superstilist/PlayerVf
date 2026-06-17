import 'package:flutter_test/flutter_test.dart';
import 'package:player_vf/models/music_model.dart';
import 'package:player_vf/services/video_playback_service.dart';

void main() {
  Music track({
    required String path,
    String genre = 'Unknown',
  }) {
    return Music(
      id: path,
      title: path,
      artist: 'Artist',
      album: 'Album',
      filePath: path,
      coverPath: '',
      genre: genre,
    );
  }

  group('VideoPlaybackService.isVideoMedia', () {
    test('recognizes common video extensions', () {
      expect(VideoPlaybackService.isVideoMedia(track(path: 'clip.mp4')), true);
      expect(VideoPlaybackService.isVideoMedia(track(path: 'clip.mkv')), true);
      expect(VideoPlaybackService.isVideoMedia(track(path: 'clip.webm')), true);
    });

    test('recognizes common audio extensions', () {
      expect(VideoPlaybackService.isVideoMedia(track(path: 'song.mp3')), false);
      expect(
          VideoPlaybackService.isVideoMedia(track(path: 'song.flac')), false);
      expect(VideoPlaybackService.isVideoMedia(track(path: 'song.m4a')), false);
    });

    test('keeps YouTube Music audio separate from video', () {
      expect(
        VideoPlaybackService.isVideoMedia(
          track(path: 'https://example.com/audio', genre: 'YouTube Music'),
        ),
        false,
      );
      expect(
        VideoPlaybackService.isVideoMedia(
          track(path: 'https://example.com/video', genre: 'YouTube Video'),
        ),
        true,
      );
    });
  });
}
