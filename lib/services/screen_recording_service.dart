import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:path/path.dart' as p;

import 'package:permission_handler/permission_handler.dart';

import '../models/music_model.dart';
import 'app_directories.dart';

class ScreenRecordingResult {
  final String path;
  final String message;

  const ScreenRecordingResult({
    required this.path,
    required this.message,
  });
}

class _WindowsCaptureRegion {
  final int x;
  final int y;
  final int width;
  final int height;
  final String label;

  const _WindowsCaptureRegion({
    required this.x,
    required this.y,
    required this.width,
    required this.height,
    required this.label,
  });
}

class RecordingOutputSize {
  final int width;
  final int height;

  const RecordingOutputSize({
    required this.width,
    required this.height,
  });

  bool get isPortrait => height > width;
}

class ScreenRecordingService {
  static const MethodChannel _androidRecordingChannel =
      MethodChannel('player_vf_screen_recording');
  static const int _outputWidth = 1920;
  static const int _outputHeight = 1080;
  static const int _mobileLandscapeWidth = 1920;
  static const int _mobileLandscapeHeight = 1080;

  Process? _process;
  String? _outputPath;
  String? _tempVideoPath;
  String? _mobileFrameDirectory;
  String? _ffmpegPath;
  String? _localAudioSource;
  String? _audioCaptureMessage;
  String? _videoCaptureMessage;
  String? _saveLocationMessage;
  RecordingOutputSize? _mobileOutputSize;
  bool _nativeMobileRecording = false;
  Duration _recordStart = Duration.zero;
  Duration _recordEnd = Duration.zero;
  DateTime? _captureStartedAt;
  DateTime? _playbackStartedAt;
  DateTime? _mobileFirstFrameAt;
  DateTime? _mobileLastFrameAt;
  double _mobileNativeFrameRate = 60.0;
  int _mobileFrameCount = 0;
  final StringBuffer _stderr = StringBuffer();
  final StringBuffer _postProcessStderr = StringBuffer();

  bool get isRecording =>
      _process != null ||
      _mobileFrameDirectory != null ||
      _nativeMobileRecording;
  String? get outputPath => _outputPath;

  void markPlaybackStarted() {
    _playbackStartedAt = DateTime.now();
  }

  Future<bool> get isAvailable async {
    if (kIsWeb) return false;
    if (Platform.isAndroid || Platform.isIOS) return true;
    return Platform.isWindows && await _findFfmpeg() != null;
  }

  Future<String?> availabilityMessage() async {
    if (kIsWeb) return 'Screen recording is not available on web.';
    if (Platform.isAndroid || Platform.isIOS) return null;
    if (!Platform.isWindows) {
      return 'Screen recording currently needs the Windows FFmpeg backend.';
    }
    if (await _findFfmpeg() == null) {
      return 'ffmpeg.exe not found. Put it in tools/ffmpeg/bin or PATH.';
    }
    return null;
  }

  static RecordingOutputSize outputSizeForScreen({
    required double width,
    required double height,
    bool mobile = false,
  }) {
    final portrait = height > width;
    final landscapeWidth = mobile ? _mobileLandscapeWidth : _outputWidth;
    final landscapeHeight = mobile ? _mobileLandscapeHeight : _outputHeight;
    return portrait
        ? RecordingOutputSize(
            width: landscapeHeight,
            height: landscapeWidth,
          )
        : RecordingOutputSize(
            width: landscapeWidth,
            height: landscapeHeight,
          );
  }

  Future<String> start({
    required Music music,
    required Duration start,
    required Duration end,
    String saveDirectory = '',
    int frameRate = 60,
  }) async {
    if (_process != null) {
      throw StateError('A recording is already running.');
    }

    final ffmpeg = await _findFfmpeg();
    if (ffmpeg == null) {
      throw StateError('ffmpeg.exe not found.');
    }
    if (!Platform.isWindows) {
      throw StateError('Recording backend is only enabled on Windows.');
    }

    final output = await _recordingOutputPath(
      music,
      start,
      end,
      saveDirectory: saveDirectory,
    );
    final tempVideo = _tempVideoOutputPath(output);
    final captureRegion = await _findWindowsClientCaptureRegion();
    final localAudioSource = await _findLocalAudioSource(music);
    final audioDevice = localAudioSource == null
        ? await _findWindowsAudioCaptureDevice(ffmpeg)
        : null;
    final usesLocalAudio = localAudioSource != null;
    _videoCaptureMessage = captureRegion == null
        ? 'Saved as 16:9 video by window title fallback.'
        : 'Saved as 16:9 app content only from ${captureRegion.label}.';
    _audioCaptureMessage = localAudioSource != null
        ? 'Audio synced from the song file.'
        : audioDevice == null
            ? 'No local audio file or FFmpeg loopback device found; saved video only.'
            : 'Audio captured from $audioDevice.';
    final videoInputArgs = captureRegion == null
        ? <String>[
            '-f',
            'gdigrab',
            '-draw_mouse',
            '0',
            '-framerate',
            frameRate.toString(),
            '-i',
            'title=playervf',
          ]
        : <String>[
            '-f',
            'gdigrab',
            '-draw_mouse',
            '0',
            '-framerate',
            frameRate.toString(),
            '-offset_x',
            captureRegion.x.toString(),
            '-offset_y',
            captureRegion.y.toString(),
            '-video_size',
            '${captureRegion.width}x${captureRegion.height}',
            '-i',
            'desktop',
          ];
    final audioInputArgs = !usesLocalAudio && audioDevice != null
        ? <String>[
            '-f',
            'dshow',
            '-i',
            'audio=$audioDevice',
          ]
        : <String>[];
    final hasLiveAudio = !usesLocalAudio && audioDevice != null;
    final liveAudioFilter = _audioFadeFilter(end - start);
    final recordingTarget = usesLocalAudio ? tempVideo : output;
    final args = <String>[
      '-y',
      '-hide_banner',
      '-loglevel',
      'warning',
      ...videoInputArgs,
      ...audioInputArgs,
      '-map',
      '0:v:0',
      if (hasLiveAudio) ...[
        '-map',
        '1:a:0',
      ],
      '-c:v',
      'libx264',
      '-preset',
      'veryfast',
      '-crf',
      '20',
      '-vf',
      'scale=$_outputWidth:$_outputHeight:force_original_aspect_ratio=decrease,'
          'pad=$_outputWidth:$_outputHeight:(ow-iw)/2:(oh-ih)/2:black,'
          'format=yuv420p',
      '-pix_fmt',
      'yuv420p',
      if (hasLiveAudio) ...[
        '-c:a',
        'aac',
        '-b:a',
        '192k',
        if (liveAudioFilter != null) ...[
          '-af',
          liveAudioFilter,
        ],
        '-shortest',
      ],
      '-movflags',
      '+faststart',
      recordingTarget,
    ];

    _stderr.clear();
    _postProcessStderr.clear();
    _outputPath = output;
    _tempVideoPath = usesLocalAudio ? tempVideo : null;
    _ffmpegPath = ffmpeg;
    _localAudioSource = localAudioSource;
    _recordStart = start;
    _recordEnd = end;
    _captureStartedAt = null;
    _playbackStartedAt = null;
    final process = await Process.start(
      ffmpeg,
      args,
      mode: ProcessStartMode.normal,
    );
    _process = process;
    _captureStartedAt = DateTime.now();
    process.stderr
        .transform(systemEncoding.decoder)
        .listen(_stderr.write, onError: (_) {});
    process.stdout.drain<void>();
    unawaited(process.exitCode.then((_) {
      if (identical(_process, process)) {
        _process = null;
      }
    }));

    final earlyExit =
        await process.exitCode.then<int?>((value) => value).timeout(
              const Duration(milliseconds: 650),
              onTimeout: () => null,
            );
    if (earlyExit != null) {
      _process = null;
      await Future<void>.delayed(const Duration(milliseconds: 80));
      final error = _stderr.toString().trim();
      throw StateError(
        'FFmpeg could not start recording. '
        '${error.isEmpty ? 'Make sure the PlayerVf window is visible.' : error}',
      );
    }
    return output;
  }

  Future<String> startMobileFrameRecording({
    required Music music,
    required Duration start,
    required Duration end,
    required double screenWidth,
    required double screenHeight,
    required double nativeFrameRate,
    String saveDirectory = '',
  }) async {
    if (!Platform.isAndroid && !Platform.isIOS) {
      throw StateError(
          'Mobile frame recording is only enabled on Android/iOS.');
    }
    if (isRecording) {
      throw StateError('A recording is already running.');
    }

    final output = await _recordingOutputPath(
      music,
      start,
      end,
      saveDirectory: saveDirectory,
    );
    final frameRoot = await getPlayerVfCacheDirectory();
    final stamp = DateTime.now().microsecondsSinceEpoch.toString();
    final frameDir =
        Directory(p.join(frameRoot.path, 'recording_frames_$stamp'));
    await frameDir.create(recursive: true);

    _stderr.clear();
    _postProcessStderr.clear();
    _outputPath = output;
    _mobileFrameDirectory = frameDir.path;
    _mobileOutputSize = outputSizeForScreen(
      width: screenWidth,
      height: screenHeight,
      mobile: true,
    );
    _mobileFrameCount = 0;
    _mobileFirstFrameAt = null;
    _mobileLastFrameAt = null;
    _mobileNativeFrameRate = nativeFrameRate.clamp(24.0, 120.0).toDouble();
    _localAudioSource = await _findLocalAudioSource(music);
    _recordStart = start;
    _recordEnd = end;
    _captureStartedAt = DateTime.now();
    _playbackStartedAt = null;
    _videoCaptureMessage =
        'Saved from Flutter frames as ${_mobileOutputSize!.width}x${_mobileOutputSize!.height} at native ${_mobileNativeFrameRate.toStringAsFixed(0)} FPS.';
    _audioCaptureMessage = _localAudioSource == null
        ? 'No local audio file found; saved video only.'
        : 'Audio synced from the song file.';
    return output;
  }

  Future<String> startMobileRecording({
    required Music music,
    required Duration start,
    required Duration end,
    required double screenWidth,
    required double screenHeight,
    required double nativeFrameRate,
    String saveDirectory = '',
  }) async {
    if (Platform.isAndroid) {
      return _startAndroidNativeRecording(
        music: music,
        start: start,
        end: end,
        screenWidth: screenWidth,
        screenHeight: screenHeight,
        nativeFrameRate: nativeFrameRate,
        saveDirectory: saveDirectory,
      );
    }

    return startMobileFrameRecording(
      music: music,
      start: start,
      end: end,
      screenWidth: screenWidth,
      screenHeight: screenHeight,
      nativeFrameRate: nativeFrameRate,
      saveDirectory: saveDirectory,
    );
  }

  Future<String> _startAndroidNativeRecording({
    required Music music,
    required Duration start,
    required Duration end,
    required double screenWidth,
    required double screenHeight,
    required double nativeFrameRate,
    required String saveDirectory,
  }) async {
    if (!Platform.isAndroid) {
      throw StateError('Native mobile recording is only enabled on Android.');
    }
    if (isRecording) {
      throw StateError('A recording is already running.');
    }

    try {
      await Permission.notification.request();
    } catch (_) {}

    final output = await _recordingOutputPath(
      music,
      start,
      end,
      saveDirectory: saveDirectory,
    );
    final outputSize = outputSizeForScreen(
      width: screenWidth,
      height: screenHeight,
      mobile: true,
    );
    final localAudioSource = await _findLocalAudioSource(music);
    final recordingTarget =
        localAudioSource == null ? output : _tempVideoOutputPath(output);
    final frameRate = nativeFrameRate.clamp(24.0, 120.0).round();
    final bitRate = _mobileBitRateFor(outputSize, frameRate);

    _stderr.clear();
    _postProcessStderr.clear();
    _outputPath = output;
    _tempVideoPath = localAudioSource == null ? null : recordingTarget;
    _mobileOutputSize = outputSize;
    _localAudioSource = localAudioSource;
    _recordStart = start;
    _recordEnd = end;
    _captureStartedAt = null;
    _playbackStartedAt = null;
    _mobileNativeFrameRate = frameRate.toDouble();
    _nativeMobileRecording = true;
    _videoCaptureMessage =
        'Saved with Android screen recording as ${outputSize.width}x${outputSize.height} at $frameRate FPS.';
    _audioCaptureMessage = localAudioSource == null
        ? 'No local audio file found; saved video only.'
        : 'Audio synced from the song file.';

    try {
      await _androidRecordingChannel.invokeMethod<Object?>('start', {
        'outputPath': recordingTarget,
        'width': outputSize.width,
        'height': outputSize.height,
        'frameRate': frameRate,
        'bitRate': bitRate,
      });
      _captureStartedAt = DateTime.now();
      return output;
    } catch (error) {
      _postProcessStderr.write(error);
      _clearRecordingSession();
      rethrow;
    }
  }

  Future<void> captureMobileFrame(GlobalKey repaintBoundaryKey) async {
    final frameDir = _mobileFrameDirectory;
    final outputSize = _mobileOutputSize;
    if (frameDir == null || outputSize == null) return;

    final context = repaintBoundaryKey.currentContext;
    final renderObject = context?.findRenderObject();
    if (renderObject is! RenderRepaintBoundary) return;
    if (renderObject.debugNeedsPaint) {
      await Future<void>.delayed(const Duration(milliseconds: 16));
    }
    final size = renderObject.size;
    if (size.width <= 0 || size.height <= 0) return;

    final pixelRatio = math
        .min(
          outputSize.width / size.width,
          outputSize.height / size.height,
        )
        .clamp(0.35, 2.0)
        .toDouble();
    ui.Image? image;
    try {
      image = await renderObject.toImage(pixelRatio: pixelRatio);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      if (data == null) return;
      final capturedAt = DateTime.now();
      _mobileFrameCount++;
      _mobileFirstFrameAt ??= capturedAt;
      _mobileLastFrameAt = capturedAt;
      final framePath = p.join(
        frameDir,
        'frame_${_mobileFrameCount.toString().padLeft(6, '0')}.png',
      );
      await File(framePath).writeAsBytes(
        Uint8List.view(data.buffer),
        flush: false,
      );
    } finally {
      image?.dispose();
    }
  }

  Future<ScreenRecordingResult?> stop() async {
    if (_nativeMobileRecording) {
      return _stopAndroidNativeRecording();
    }
    if (_mobileFrameDirectory != null) {
      return _stopMobileFrameRecording();
    }

    final process = _process;
    final output = _outputPath;
    if (process == null || output == null) return null;

    _process = null;
    try {
      process.stdin.writeln('q');
      await process.stdin.flush();
      await process.stdin.close();
    } catch (_) {
      // ffmpeg may already have exited; the timeout below handles both paths.
    }

    int exitCode;
    try {
      exitCode = await process.exitCode.timeout(const Duration(seconds: 4));
    } on TimeoutException {
      process.kill(ProcessSignal.sigterm);
      exitCode = await process.exitCode.timeout(
        const Duration(seconds: 2),
        onTimeout: () {
          process.kill(ProcessSignal.sigkill);
          return -1;
        },
      );
    }

    final localAudioSource = _localAudioSource;
    final tempVideo = _tempVideoPath;
    var finalPath = output;
    var postProcessMessage = '';
    if (localAudioSource != null && tempVideo != null) {
      finalPath = await _muxLocalAudio(
        output: output,
        tempVideo: tempVideo,
        audioSource: localAudioSource,
      );
      final delay = _measuredPlaybackDelay();
      postProcessMessage =
          ' Sync delay ${delay.inMilliseconds.clamp(0, 5000)} ms.';
    }

    final file = File(finalPath);
    final exists = await file.exists();
    final size = exists ? await file.length() : 0;
    final audioMessage = _audioCaptureMessage;
    final videoMessage = _videoCaptureMessage;
    final saveMessage = _saveLocationMessage;
    final message = exitCode == 0 && size > 0
        ? 'Recording saved.'
            '${saveMessage == null ? '' : ' $saveMessage'}'
            '${videoMessage == null ? '' : ' $videoMessage'}'
            '${audioMessage == null ? '' : ' $audioMessage'}'
            '$postProcessMessage'
        : 'Recording stopped, but FFmpeg may not have produced video. '
            '${_combinedErrorText()}';
    _clearRecordingSession();
    return ScreenRecordingResult(path: finalPath, message: message);
  }

  Future<ScreenRecordingResult?> _stopAndroidNativeRecording() async {
    final output = _outputPath;
    if (output == null) return null;

    var nativeStopped = false;
    try {
      final result =
          await _androidRecordingChannel.invokeMethod<Object?>('stop');
      if (result is Map) {
        nativeStopped = result['stopped'] == true;
      } else {
        nativeStopped = true;
      }
    } catch (error) {
      _postProcessStderr.write(error);
    }

    final localAudioSource = _localAudioSource;
    final tempVideo = _tempVideoPath;
    var finalPath = output;
    var postProcessMessage = '';
    if (localAudioSource != null && tempVideo != null) {
      finalPath = await _muxLocalAudioWithFfmpegKit(
        output: output,
        tempVideo: tempVideo,
        audioSource: localAudioSource,
      );
      final delay = _measuredPlaybackDelay();
      postProcessMessage =
          ' Sync delay ${delay.inMilliseconds.clamp(0, 5000)} ms.';
    }

    final file = File(finalPath);
    final exists = await file.exists();
    final size = exists ? await file.length() : 0;
    final saveMessage = _saveLocationMessage;
    final videoMessage = _videoCaptureMessage;
    final audioMessage = _audioCaptureMessage;
    final message = nativeStopped && size > 0
        ? 'Recording saved.'
            '${saveMessage == null ? '' : ' $saveMessage'}'
            '${videoMessage == null ? '' : ' $videoMessage'}'
            '${audioMessage == null ? '' : ' $audioMessage'}'
            '$postProcessMessage'
        : 'Recording stopped, but Android did not produce video. '
            '${_combinedErrorText()}';
    _clearRecordingSession();
    return ScreenRecordingResult(path: finalPath, message: message);
  }

  Future<ScreenRecordingResult?> _stopMobileFrameRecording() async {
    final output = _outputPath;
    final frameDir = _mobileFrameDirectory;
    final outputSize = _mobileOutputSize;
    if (output == null || frameDir == null || outputSize == null) return null;

    final localAudioSource = _localAudioSource;
    final framePattern = p.join(frameDir, 'frame_%06d.png');
    final duration = _recordEnd - _recordStart;
    final delay = _measuredPlaybackDelay();
    final inputFrameRate = _measuredMobileFrameRate();
    final nativeFrameRate = _mobileNativeFrameRate;
    final audioFilter = _audioFadeFilter(duration, startDelay: delay);
    final hasAudio = localAudioSource != null;
    final args = <String>[
      '-y',
      '-hide_banner',
      '-loglevel',
      'warning',
      '-framerate',
      inputFrameRate.toStringAsFixed(3),
      '-start_number',
      '1',
      '-i',
      framePattern,
      if (hasAudio) ...[
        '-ss',
        _ffmpegSeconds(_recordStart),
        '-t',
        _ffmpegSeconds(duration),
        '-i',
        localAudioSource,
      ],
      '-map',
      '0:v:0',
      if (hasAudio) ...[
        '-map',
        '1:a:0',
      ],
      '-c:v',
      'libx264',
      '-preset',
      'ultrafast',
      '-crf',
      '23',
      '-vf',
      'scale=${outputSize.width}:${outputSize.height}:force_original_aspect_ratio=decrease,'
          'pad=${outputSize.width}:${outputSize.height}:(ow-iw)/2:(oh-ih)/2:black,'
          'format=yuv420p',
      '-r',
      nativeFrameRate.toStringAsFixed(3),
      '-pix_fmt',
      'yuv420p',
      if (hasAudio) ...[
        '-c:a',
        'aac',
        '-b:a',
        '192k',
        if (audioFilter != null) ...[
          '-af',
          audioFilter,
        ],
      ],
      '-movflags',
      '+faststart',
      output,
    ];

    var success = false;
    try {
      if (_mobileFrameCount <= 0) {
        throw StateError('No frames were captured.');
      }
      final session = await FFmpegKit.executeWithArguments(args);
      final returnCode = await session.getReturnCode();
      final outputText = await session.getOutput();
      final logs = await session.getLogsAsString();
      _postProcessStderr.write('${outputText ?? ''}\n$logs');
      success = ReturnCode.isSuccess(returnCode);
    } catch (error) {
      _postProcessStderr.write(error);
    }

    final file = File(output);
    final exists = await file.exists();
    final size = exists ? await file.length() : 0;
    try {
      await Directory(frameDir).delete(recursive: true);
    } catch (_) {}

    final message = success && size > 0
        ? 'Recording saved. ${_saveLocationMessage ?? ''} '
            '${_videoCaptureMessage ?? ''} '
            '${_audioCaptureMessage ?? ''} Captured ${inputFrameRate.toStringAsFixed(1)} FPS, saved ${nativeFrameRate.toStringAsFixed(1)} FPS. '
            'Sync delay ${delay.inMilliseconds.clamp(0, 5000)} ms.'
        : 'Recording stopped, but mobile FFmpeg did not produce video. '
            '${_combinedErrorText()}';
    _clearRecordingSession();
    return ScreenRecordingResult(path: output, message: message);
  }

  Future<String> _muxLocalAudio({
    required String output,
    required String tempVideo,
    required String audioSource,
  }) async {
    final ffmpeg = _ffmpegPath;
    if (ffmpeg == null) return tempVideo;
    final videoFile = File(tempVideo);
    if (!await videoFile.exists()) return tempVideo;

    final delay = _measuredPlaybackDelay();
    final duration = _recordEnd - _recordStart;
    final audioFilter = _audioFadeFilter(duration, startDelay: delay);
    final args = <String>[
      '-y',
      '-hide_banner',
      '-loglevel',
      'warning',
      '-i',
      tempVideo,
      '-ss',
      _ffmpegSeconds(_recordStart),
      '-t',
      _ffmpegSeconds(duration),
      '-i',
      audioSource,
      '-map',
      '0:v:0',
      '-map',
      '1:a:0',
      '-c:v',
      'copy',
      '-c:a',
      'aac',
      '-b:a',
      '192k',
      if (audioFilter != null) ...[
        '-af',
        audioFilter,
      ],
      '-movflags',
      '+faststart',
      output,
    ];
    try {
      final result = await Process.run(ffmpeg, args).timeout(
        const Duration(minutes: 3),
      );
      _postProcessStderr.write('${result.stdout}\n${result.stderr}');
      final outputFile = File(output);
      if (result.exitCode == 0 &&
          await outputFile.exists() &&
          await outputFile.length() > 0) {
        try {
          await videoFile.delete();
        } catch (_) {}
        return output;
      }
    } catch (error) {
      _postProcessStderr.write(error);
    }

    try {
      await videoFile.rename(output);
      return output;
    } catch (_) {
      return tempVideo;
    }
  }

  Future<String> _muxLocalAudioWithFfmpegKit({
    required String output,
    required String tempVideo,
    required String audioSource,
  }) async {
    final videoFile = File(tempVideo);
    if (!await videoFile.exists()) return tempVideo;

    final delay = _measuredPlaybackDelay();
    final duration = _recordEnd - _recordStart;
    final audioFilter = _audioFadeFilter(duration, startDelay: delay);
    final args = <String>[
      '-y',
      '-hide_banner',
      '-loglevel',
      'warning',
      '-i',
      tempVideo,
      '-ss',
      _ffmpegSeconds(_recordStart),
      '-t',
      _ffmpegSeconds(duration),
      '-i',
      audioSource,
      '-map',
      '0:v:0',
      '-map',
      '1:a:0',
      '-c:v',
      'copy',
      '-c:a',
      'aac',
      '-b:a',
      '192k',
      if (audioFilter != null) ...[
        '-af',
        audioFilter,
      ],
      '-movflags',
      '+faststart',
      output,
    ];

    try {
      final session = await FFmpegKit.executeWithArguments(args);
      final returnCode = await session.getReturnCode();
      final outputText = await session.getOutput();
      final logs = await session.getLogsAsString();
      _postProcessStderr.write('${outputText ?? ''}\n$logs');
      final outputFile = File(output);
      if (ReturnCode.isSuccess(returnCode) &&
          await outputFile.exists() &&
          await outputFile.length() > 0) {
        try {
          await videoFile.delete();
        } catch (_) {}
        return output;
      }
    } catch (error) {
      _postProcessStderr.write(error);
    }

    try {
      await videoFile.rename(output);
      return output;
    } catch (_) {
      return tempVideo;
    }
  }

  Duration _measuredPlaybackDelay() {
    final capture = _mobileFirstFrameAt ?? _captureStartedAt;
    final playback = _playbackStartedAt;
    if (capture == null || playback == null || playback.isBefore(capture)) {
      return const Duration(milliseconds: 280);
    }
    final measured = playback.difference(capture);
    return Duration(
      milliseconds: measured.inMilliseconds.clamp(0, 5000),
    );
  }

  double _measuredMobileFrameRate() {
    final first = _mobileFirstFrameAt;
    final last = _mobileLastFrameAt;
    if (first == null || last == null || _mobileFrameCount <= 1) {
      return _mobileNativeFrameRate;
    }
    final elapsedSeconds =
        last.difference(first).inMicroseconds / Duration.microsecondsPerSecond;
    if (elapsedSeconds <= 0) return 20.0;
    return ((_mobileFrameCount - 1) / elapsedSeconds).clamp(1.0, 60.0);
  }

  void _clearRecordingSession() {
    _tempVideoPath = null;
    _mobileFrameDirectory = null;
    _ffmpegPath = null;
    _localAudioSource = null;
    _saveLocationMessage = null;
    _mobileOutputSize = null;
    _nativeMobileRecording = false;
    _recordStart = Duration.zero;
    _recordEnd = Duration.zero;
    _captureStartedAt = null;
    _playbackStartedAt = null;
    _mobileFirstFrameAt = null;
    _mobileLastFrameAt = null;
    _mobileNativeFrameRate = 60.0;
    _mobileFrameCount = 0;
  }

  int _mobileBitRateFor(RecordingOutputSize size, int frameRate) {
    final pixels = size.width * size.height;
    final base = pixels >= 1920 * 1080
        ? 18000000
        : pixels >= 1280 * 720
            ? 12000000
            : 8000000;
    return (base * (frameRate / 60.0)).round().clamp(6000000, 36000000).toInt();
  }

  String _combinedErrorText() {
    final parts = [
      _stderr.toString().trim(),
      _postProcessStderr.toString().trim(),
    ].where((part) => part.isNotEmpty).toList(growable: false);
    return parts.isEmpty
        ? 'No FFmpeg error text was reported.'
        : parts.join('\n');
  }

  Future<_WindowsCaptureRegion?> _findWindowsClientCaptureRegion() async {
    if (!Platform.isWindows) return null;
    const scriptTemplate = r'''
$ErrorActionPreference = 'Stop'
$targetPid = __PID__
Add-Type @"
using System;
using System.Runtime.InteropServices;
using System.Text;
public static class PlayerVfUser32 {
  public delegate bool EnumWindowsProc(IntPtr hWnd, IntPtr lParam);
  [StructLayout(LayoutKind.Sequential)]
  public struct RECT {
    public int Left;
    public int Top;
    public int Right;
    public int Bottom;
  }
  [StructLayout(LayoutKind.Sequential)]
  public struct POINT {
    public int X;
    public int Y;
  }
  [DllImport("user32.dll")]
  public static extern bool EnumWindows(EnumWindowsProc lpEnumFunc, IntPtr lParam);
  [DllImport("user32.dll")]
  public static extern bool IsWindowVisible(IntPtr hWnd);
  [DllImport("user32.dll")]
  public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint processId);
  [DllImport("user32.dll", CharSet = CharSet.Unicode)]
  public static extern int GetWindowText(IntPtr hWnd, StringBuilder text, int count);
  [DllImport("user32.dll", CharSet = CharSet.Unicode)]
  public static extern int GetWindowTextLength(IntPtr hWnd);
  [DllImport("user32.dll")]
  public static extern bool GetClientRect(IntPtr hWnd, out RECT lpRect);
  [DllImport("user32.dll")]
  public static extern bool ClientToScreen(IntPtr hWnd, ref POINT lpPoint);
}
"@
$windows = New-Object System.Collections.ArrayList
$callback = [PlayerVfUser32+EnumWindowsProc] {
  param([IntPtr]$hwnd, [IntPtr]$lParam)
  if (-not [PlayerVfUser32]::IsWindowVisible($hwnd)) { return $true }

  [uint32]$windowPid = 0
  [void][PlayerVfUser32]::GetWindowThreadProcessId($hwnd, [ref]$windowPid)
  try {
    $process = Get-Process -Id ([int]$windowPid) -ErrorAction Stop
  } catch {
    return $true
  }

  $title = ''
  $length = [PlayerVfUser32]::GetWindowTextLength($hwnd)
  if ($length -gt 0) {
    $builder = New-Object System.Text.StringBuilder -ArgumentList ($length + 1)
    [void][PlayerVfUser32]::GetWindowText($hwnd, $builder, $builder.Capacity)
    $title = $builder.ToString()
  }

  $processMatches = $process.ProcessName -match '(?i)playervf|untitled'
  $titleMatches = $title -match '(?i)player\s*vf|playervf|untitled'
  $pidMatches = [int]$windowPid -eq $targetPid
  if (-not ($pidMatches -or $processMatches -or $titleMatches)) {
    return $true
  }

  $rect = New-Object PlayerVfUser32+RECT
  if (-not [PlayerVfUser32]::GetClientRect($hwnd, [ref]$rect)) { return $true }
  $topLeft = New-Object PlayerVfUser32+POINT
  $bottomRight = New-Object PlayerVfUser32+POINT
  $topLeft.X = $rect.Left
  $topLeft.Y = $rect.Top
  $bottomRight.X = $rect.Right
  $bottomRight.Y = $rect.Bottom
  if (-not [PlayerVfUser32]::ClientToScreen($hwnd, [ref]$topLeft)) { return $true }
  if (-not [PlayerVfUser32]::ClientToScreen($hwnd, [ref]$bottomRight)) { return $true }

  $width = $bottomRight.X - $topLeft.X
  $height = $bottomRight.Y - $topLeft.Y
  if ($width -lt 64 -or $height -lt 64) { return $true }

  $score = [double]($width * $height)
  if ($pidMatches) { $score += 1000000000000 }
  if ($titleMatches) { $score += 100000000000 }
  if ($processMatches) { $score += 10000000000 }
  [void]$windows.Add([pscustomobject]@{
    X = $topLeft.X
    Y = $topLeft.Y
    Width = $width
    Height = $height
    Score = $score
    Process = $process.ProcessName
    Title = $title
  })
  return $true
}
[void][PlayerVfUser32]::EnumWindows($callback, [IntPtr]::Zero)
$best = $windows | Sort-Object Score -Descending | Select-Object -First 1
if ($null -eq $best) { throw 'PlayerVf window not found.' }
$label = "$($best.Process) $($best.Title)".Trim().Replace(',', ' ')
Write-Output "$($best.X),$($best.Y),$($best.Width),$($best.Height),$label"
''';
    final script = scriptTemplate.replaceFirst('__PID__', pid.toString());
    try {
      final result = await Process.run(
        'powershell',
        [
          '-NoProfile',
          '-ExecutionPolicy',
          'Bypass',
          '-Command',
          script,
        ],
      ).timeout(const Duration(seconds: 3));
      if (result.exitCode != 0) return null;
      final line = result.stdout
          .toString()
          .split(RegExp(r'\r?\n'))
          .map((value) => value.trim())
          .firstWhere((value) => value.isNotEmpty, orElse: () => '');
      final parts = line.split(',');
      if (parts.length < 4) return null;
      final x = int.tryParse(parts[0]);
      final y = int.tryParse(parts[1]);
      var width = int.tryParse(parts[2]);
      var height = int.tryParse(parts[3]);
      final label =
          parts.length > 4 ? parts.skip(4).join(',').trim() : 'PlayerVf window';
      if (x == null || y == null || width == null || height == null) {
        return null;
      }
      if (width < 64 || height < 64) return null;
      width -= width % 2;
      height -= height % 2;
      return _WindowsCaptureRegion(
        x: x,
        y: y,
        width: width,
        height: height,
        label: label.isEmpty ? 'PlayerVf window' : label,
      );
    } catch (_) {
      return null;
    }
  }

  Future<String> _recordingOutputPath(
    Music music,
    Duration start,
    Duration end, {
    required String saveDirectory,
  }) async {
    _saveLocationMessage = null;
    final requested = saveDirectory.trim();
    final defaultRoot = await getPlayerVfDocumentsDirectory();
    final defaultDir = Directory(p.join(defaultRoot.path, 'Recordings'));
    final dir = requested.isEmpty
        ? await _prepareWritableRecordingDirectory(defaultDir)
        : await _prepareRequestedRecordingDirectory(
            requested: Directory(requested),
            fallback: defaultDir,
          );
    final stamp = DateTime.now()
        .toIso8601String()
        .replaceAll(':', '-')
        .replaceAll('.', '-');
    final title =
        _safeFileName(music.title.isEmpty ? 'recording' : music.title);
    final range =
        '${_durationToken(start)}-${_durationToken(end)}'.replaceAll(':', '-');
    return p.join(dir.path, '$title-$range-$stamp.mp4');
  }

  Future<Directory> _prepareRequestedRecordingDirectory({
    required Directory requested,
    required Directory fallback,
  }) async {
    try {
      return await _prepareWritableRecordingDirectory(requested);
    } catch (_) {
      final fallbackDir = await _prepareWritableRecordingDirectory(fallback);
      _saveLocationMessage =
          'Selected folder needs permission or is not writable; saved to the default PlayerVf Recordings folder.';
      return fallbackDir;
    }
  }

  Future<Directory> _prepareWritableRecordingDirectory(Directory dir) async {
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    final probe = File(p.join(
      dir.path,
      '.player_vf_recording_write_${DateTime.now().microsecondsSinceEpoch}.tmp',
    ));
    try {
      await probe.writeAsString('ok', flush: true);
    } finally {
      try {
        if (await probe.exists()) {
          await probe.delete();
        }
      } catch (_) {}
    }
    return dir;
  }

  String _tempVideoOutputPath(String output) {
    final dir = p.dirname(output);
    final base = p.basenameWithoutExtension(output);
    return p.join(dir, '$base.video.tmp.mp4');
  }

  Future<String?> _findLocalAudioSource(Music music) async {
    final path = music.filePath.trim();
    if (path.isEmpty ||
        path.startsWith('http://') ||
        path.startsWith('https://') ||
        path.startsWith('blob:')) {
      return null;
    }
    try {
      final file = File(path);
      if (await file.exists()) return file.path;
    } catch (_) {
      return null;
    }
    return null;
  }

  Future<String?> _findWindowsAudioCaptureDevice(String ffmpeg) async {
    final envDevice = Platform.environment['PLAYER_VF_RECORD_AUDIO_DEVICE'];
    if (envDevice != null && envDevice.trim().isNotEmpty) {
      return envDevice.trim();
    }
    if (!Platform.isWindows) return null;

    final devices = <String>[];
    try {
      final result = await Process.run(
        ffmpeg,
        ['-hide_banner', '-list_devices', 'true', '-f', 'dshow', '-i', 'dummy'],
      ).timeout(const Duration(seconds: 4));
      final output = '${result.stdout}\n${result.stderr}';
      final devicePattern = RegExp(r'"([^"]+)"\s*\(audio\)');
      for (final match in devicePattern.allMatches(output)) {
        final device = match.group(1)?.trim();
        if (device != null && device.isNotEmpty) devices.add(device);
      }
    } catch (_) {
      return null;
    }

    if (devices.isEmpty) return null;
    const preferredNeedles = [
      'virtual-audio-capturer',
      'stereo mix',
      'what u hear',
      'wave out',
      'loopback',
    ];
    for (final needle in preferredNeedles) {
      for (final device in devices) {
        if (device.toLowerCase().contains(needle)) return device;
      }
    }
    return null;
  }

  Future<String?> _findFfmpeg() async {
    final env = Platform.environment['PLAYER_VF_FFMPEG'];
    if (env != null && env.isNotEmpty && await File(env).exists()) {
      return env;
    }

    final names = Platform.isWindows ? const ['ffmpeg.exe'] : const ['ffmpeg'];
    final roots = <String>[
      Directory.current.path,
      p.join(Directory.current.path, 'tools'),
      p.join(Directory.current.path, 'tools', 'ffmpeg', 'bin'),
      p.join(Directory.current.path, 'ffmpeg', 'bin'),
    ];
    for (final root in roots) {
      for (final name in names) {
        final candidate = p.join(root, name);
        if (await File(candidate).exists()) return candidate;
      }
    }

    final command = Platform.isWindows ? 'where' : 'which';
    try {
      final result = await Process.run(command, ['ffmpeg']);
      if (result.exitCode == 0) {
        final first = result.stdout
            .toString()
            .split(RegExp(r'\r?\n'))
            .map((line) => line.trim())
            .firstWhere((line) => line.isNotEmpty, orElse: () => '');
        if (first.isNotEmpty && await File(first).exists()) return first;
      }
    } catch (_) {
      return null;
    }
    return null;
  }

  String _safeFileName(String value) {
    return value
        .replaceAll(RegExp(r'[\\/:*?"<>|]'), '_')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim()
        .clampText(80);
  }

  String _durationToken(Duration value) {
    final minutes = value.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = value.inSeconds.remainder(60).toString().padLeft(2, '0');
    final hours = value.inHours;
    return hours > 0 ? '$hours-$minutes-$seconds' : '$minutes-$seconds';
  }

  String _ffmpegSeconds(Duration value) {
    final milliseconds = value.inMilliseconds < 0 ? 0 : value.inMilliseconds;
    return (milliseconds / 1000).toStringAsFixed(3);
  }

  String? _audioFadeFilter(
    Duration duration, {
    Duration startDelay = Duration.zero,
  }) {
    if (duration <= Duration.zero) return null;
    final seconds = duration.inMilliseconds / 1000.0;
    final delaySeconds = startDelay.inMilliseconds.clamp(0, 5000) / 1000.0;
    final delayMilliseconds = startDelay.inMilliseconds.clamp(0, 5000);
    final fadeIn = seconds < 0.9 ? seconds * 0.25 : 0.45;
    final fadeOut = seconds < 1.2 ? seconds * 0.30 : 0.65;
    final inStart = delaySeconds;
    final outStart = (delaySeconds + seconds - fadeOut)
        .clamp(delaySeconds, delaySeconds + seconds)
        .toDouble();
    final filters = <String>[
      if (delayMilliseconds > 0) 'adelay=$delayMilliseconds:all=1',
      'afade=t=in:st=${inStart.toStringAsFixed(3)}:d=${fadeIn.toStringAsFixed(3)}',
      'afade=t=out:st=${outStart.toStringAsFixed(3)}:d=${fadeOut.toStringAsFixed(3)}',
    ];
    return filters.join(',');
  }
}

extension _RecordingStringClamp on String {
  String clampText(int maxLength) {
    if (length <= maxLength) return this;
    return substring(0, maxLength).trim();
  }
}
