import 'music_service.dart';

class PlayerController {
  final MusicService _musicService;

  const PlayerController(this._musicService);

  void togglePlayPause() => _musicService.togglePlayPause();

  void nextTrack() => _musicService.next();

  void previousTrack() => _musicService.previousTrack();

  void previousOrRestart() => _musicService.previousOrRestartShortcut();

  void restartCurrentTrack() => _musicService.restartCurrentTrack();

  Future<void> seek(Duration position) async => _musicService.seekTo(position);
}

class PlayerCommandController {
  final MusicService musicService;

  const PlayerCommandController(this.musicService);

  PlayerController get player => PlayerController(musicService);

  void handlePlayPauseShortcut() => player.togglePlayPause();

  void handleNextShortcut() => player.nextTrack();

  void handlePreviousShortcut() => player.previousOrRestart();

  void handleRestartShortcut() => player.restartCurrentTrack();

  Future<void> handleSeek(Duration position) async => player.seek(position);
}
