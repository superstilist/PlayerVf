// ignore_for_file: avoid_web_libraries_in_flutter

import 'dart:async';
import 'dart:html' as html;
import 'dart:js_util' as js_util;
import 'dart:typed_data';

import '../models/music_model.dart';

const Set<String> _supportedExtensions = {
  'mp3',
  'm4a',
  'wav',
  'flac',
  'aac',
  'ogg',
  'mp4',
  'mkv',
  'webm',
};

Future<List<Music>> pickWebFolderMusic() async {
  final input = html.FileUploadInputElement()
    ..multiple = true
    ..accept = _supportedExtensions.map((ext) => '.$ext').join(',');

  input
    ..setAttribute('webkitdirectory', '')
    ..setAttribute('directory', '');

  final completer = Completer<List<Music>>();
  late final StreamSubscription<html.Event> changeSub;

  void complete(List<Music> tracks) {
    if (!completer.isCompleted) {
      completer.complete(tracks);
    }
  }

  changeSub = input.onChange.listen((_) async {
    final files = input.files ?? const <html.File>[];
    complete(await _filesToMusic(files));
  });

  input.click();
  final tracks = await completer.future.timeout(
    const Duration(minutes: 2),
    onTimeout: () => const [],
  );
  await changeSub.cancel();
  return tracks;
}

Future<List<Music>> _filesToMusic(List<html.File> files) async {
  final tracks = <Music>[];
  for (final file in files) {
    final name = file.name.trim();
    final ext = _extension(name);
    if (!_supportedExtensions.contains(ext)) continue;

    final relativePath = _relativePath(file);
    final folder = _folderName(relativePath);
    final url = html.Url.createObjectUrl(file);
    final coverUrl = await _extractCoverUrl(file);
    final title = _titleFromName(name);
    final idSeed = relativePath.isNotEmpty ? relativePath : name;

    tracks.add(
      Music(
        id: 'web-${idSeed.hashCode}-${file.size}',
        title: title.isEmpty ? name : title,
        artist: 'Web folder',
        album: folder.isEmpty ? 'Browser import' : folder,
        filePath: url,
        coverPath: coverUrl,
        genre: ext == 'mp4' || ext == 'mkv' || ext == 'webm'
            ? 'Web Video'
            : 'Web Audio',
      ),
    );
  }
  tracks.sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
  return tracks;
}

Future<String> _extractCoverUrl(html.File file) async {
  if (!_extension(file.name).startsWith('mp3')) return '';

  try {
    final reader = html.FileReader();
    final completer = Completer<Uint8List?>();
    late final StreamSubscription<html.ProgressEvent> loadSub;
    late final StreamSubscription<html.Event> errorSub;

    loadSub = reader.onLoad.listen((_) {
      final result = reader.result;
      if (result is ByteBuffer) {
        completer.complete(Uint8List.view(result));
      } else {
        completer.complete(null);
      }
    });
    errorSub = reader.onError.listen((_) => completer.complete(null));

    reader.readAsArrayBuffer(file);
    final bytes = await completer.future.timeout(
      const Duration(seconds: 4),
      onTimeout: () => null,
    );
    await loadSub.cancel();
    await errorSub.cancel();
    if (bytes == null) return '';

    final cover = _extractId3Cover(bytes);
    if (cover == null) return '';
    return html.Url.createObjectUrlFromBlob(
      html.Blob([cover.bytes], cover.mimeType),
    );
  } catch (_) {
    return '';
  }
}

_WebCover? _extractId3Cover(Uint8List bytes) {
  if (bytes.length < 16 ||
      bytes[0] != 0x49 ||
      bytes[1] != 0x44 ||
      bytes[2] != 0x33) {
    return null;
  }

  final version = bytes[3];
  final tagSize = _syncSafeInt(bytes, 6);
  final end = (10 + tagSize).clamp(10, bytes.length);
  var offset = 10;

  while (offset + (version == 2 ? 6 : 10) <= end) {
    if (version == 2) {
      final id = String.fromCharCodes(bytes.sublist(offset, offset + 3));
      final size = (bytes[offset + 3] << 16) |
          (bytes[offset + 4] << 8) |
          bytes[offset + 5];
      offset += 6;
      if (size <= 0 || offset + size > end) break;
      if (id == 'PIC') {
        final cover = _parsePicFrame(bytes.sublist(offset, offset + size));
        if (cover != null) return cover;
      }
      offset += size;
      continue;
    }

    final id = String.fromCharCodes(bytes.sublist(offset, offset + 4));
    final size = version == 4
        ? _syncSafeInt(bytes, offset + 4)
        : _bigEndianInt(bytes, offset + 4);
    offset += 10;
    if (id.trim().isEmpty || size <= 0 || offset + size > end) break;
    if (id == 'APIC') {
      final cover = _parseApicFrame(bytes.sublist(offset, offset + size));
      if (cover != null) return cover;
    }
    offset += size;
  }
  return null;
}

_WebCover? _parseApicFrame(Uint8List frame) {
  if (frame.length < 8) return null;
  var index = 1;
  final mimeEnd = frame.indexOf(0, index);
  if (mimeEnd == -1 || mimeEnd + 2 >= frame.length) return null;
  final mime = String.fromCharCodes(frame.sublist(index, mimeEnd));
  index = mimeEnd + 2;
  index = _skipDescription(frame, index, frame[0]);
  if (index >= frame.length) return null;
  return _WebCover(mime.isEmpty ? 'image/jpeg' : mime, frame.sublist(index));
}

_WebCover? _parsePicFrame(Uint8List frame) {
  if (frame.length < 7) return null;
  final format = String.fromCharCodes(frame.sublist(1, 4)).toLowerCase();
  var index = _skipDescription(frame, 5, frame[0]);
  if (index >= frame.length) return null;
  final mime = format.contains('png') ? 'image/png' : 'image/jpeg';
  return _WebCover(mime, frame.sublist(index));
}

int _skipDescription(Uint8List frame, int index, int encoding) {
  if (encoding == 1 || encoding == 2) {
    while (index + 1 < frame.length) {
      if (frame[index] == 0 && frame[index + 1] == 0) return index + 2;
      index += 2;
    }
    return frame.length;
  }

  while (index < frame.length && frame[index] != 0) {
    index++;
  }
  return index + 1;
}

int _syncSafeInt(Uint8List bytes, int offset) {
  return (bytes[offset] << 21) |
      (bytes[offset + 1] << 14) |
      (bytes[offset + 2] << 7) |
      bytes[offset + 3];
}

int _bigEndianInt(Uint8List bytes, int offset) {
  return (bytes[offset] << 24) |
      (bytes[offset + 1] << 16) |
      (bytes[offset + 2] << 8) |
      bytes[offset + 3];
}

class _WebCover {
  final String mimeType;
  final Uint8List bytes;

  const _WebCover(this.mimeType, this.bytes);
}

String _relativePath(html.File file) {
  try {
    final value = js_util.getProperty<Object?>(file, 'webkitRelativePath');
    return value?.toString() ?? '';
  } catch (_) {
    return '';
  }
}

String _folderName(String relativePath) {
  if (relativePath.isEmpty) return '';
  final parts = relativePath.split('/').where((part) => part.isNotEmpty);
  return parts.isEmpty ? '' : parts.first;
}

String _extension(String name) {
  final index = name.lastIndexOf('.');
  if (index == -1 || index == name.length - 1) return '';
  return name.substring(index + 1).toLowerCase();
}

String _titleFromName(String name) {
  final index = name.lastIndexOf('.');
  return index <= 0 ? name : name.substring(0, index);
}
