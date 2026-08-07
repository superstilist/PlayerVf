import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

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
  final input = web.HTMLInputElement()
    ..multiple = true
    ..accept = _supportedExtensions.map((ext) => '.$ext').join(',');

  input
    ..setAttribute('webkitdirectory', '')
    ..setAttribute('directory', '');

  final completer = Completer<List<Music>>();
  late final StreamSubscription<web.Event> changeSub;

  void complete(List<Music> tracks) {
    if (!completer.isCompleted) {
      completer.complete(tracks);
    }
  }

  changeSub = input.onChange.listen((_) async {
    final files = input.files;
    final tracks = <Music>[];
    if (files != null) {
      for (var i = 0; i < files.length; i++) {
        final file = files.item(i);
        if (file == null) continue;
        tracks.addAll(await _filesToMusic([file]));
      }
    }
    complete(tracks);
  });

  input.click();
  final tracks = await completer.future.timeout(
    const Duration(minutes: 2),
    onTimeout: () => const [],
  );
  await changeSub.cancel();
  return tracks;
}

Future<List<Music>> _filesToMusic(List<web.File> files) async {
  final tracks = <Music>[];
  for (final file in files) {
    final name = file.name.trim();
    final ext = _extension(name);
    if (!_supportedExtensions.contains(ext)) continue;

    final relativePath = _relativePath(file);
    final folder = _folderName(relativePath);
    final url = web.URL.createObjectURL(file);
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

Future<String> _extractCoverUrl(web.File file) async {
  if (!_extension(file.name).startsWith('mp3')) return '';

  try {
    final header = await _readFileSlice(file, 0, 10);
    if (header == null ||
        header.length < 10 ||
        header[0] != 0x49 ||
        header[1] != 0x44 ||
        header[2] != 0x33) {
      return '';
    }

    final tagSize = (10 + _syncSafeInt(header, 6)).clamp(10, file.size);
    final bytes = await _readFileSlice(file, 0, tagSize);
    if (bytes == null) return '';

    final cover = _extractId3Cover(bytes);
    if (cover == null) return '';
    return web.URL.createObjectURL(web.Blob(
      [cover.bytes.toJS].toJS,
      web.BlobPropertyBag(type: cover.mimeType),
    ));
  } catch (_) {
    return '';
  }
}

Future<Uint8List?> _readFileSlice(web.File file, int start, int end) async {
  try {
    final jsBuffer = await file.slice(start, end).arrayBuffer().toDart;
    return Uint8List.view(jsBuffer.toDart);
  } catch (_) {
    return null;
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

String _relativePath(web.File file) {
  try {
    return file.webkitRelativePath;
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
