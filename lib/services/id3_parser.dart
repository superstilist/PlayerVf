// ignore_for_file: curly_braces_in_flow_control_structures, no_leading_underscores_for_local_identifiers, unnecessary_string_interpolations, unused_local_variable

import 'dart:typed_data';
import 'dart:io' as io;
import 'package:flutter/services.dart' show rootBundle;
import 'package:path/path.dart' as path;
import 'package:flutter/foundation.dart' show kIsWeb, kDebugMode;
import 'package:id3/id3.dart';
import 'dart:convert';
import 'package:crypto/crypto.dart';

import 'package:flutter_media_metadata/flutter_media_metadata.dart';

import '../models/music_model.dart';

/// ID3 + APE + FLAC (Vorbis + Picture) + MP4/M4A/etc parser
class ID3Parser {
  // Tag cache to avoid redundant parsing of the same file
  static final Map<String, Map<String, dynamic>> _tagCache = {};

  /// Entry: parse tags from file path (tries many methods) with caching
  Future<Map<String, dynamic>> parseTagsFromFile(String filePath) async {
    if (kIsWeb) return {};

    // Check if we already parsed this file
    if (_tagCache.containsKey(filePath)) {
      return Map.from(
          _tagCache[filePath]!); // Return copy to prevent modification
    }

    try {
      final file = io.File(filePath);
      if (!await file.exists()) return {};

      final extension = path.extension(filePath).toLowerCase();

      // Read first few bytes to detect FLAC signature or similar without reading whole file
      Uint8List header = Uint8List(0);
      try {
        final raf = await file.open();
        final headList = await raf.read(8); // read a few bytes
        await raf.close();
        header = Uint8List.fromList(headList);
      } catch (_) {
        header = Uint8List(0);
      }

      // Prioritize faster parsing methods first
      Map<String, dynamic> result = {};
      Map<String, dynamic> metadataResult = {};

      // 1) Use flutter_media_metadata for most formats (fast and reliable cross-platform)
      final Set<String> metadataExtensions = <String>{
        '.m4a',
        '.mp4',
        '.aac',
        '.flac',
        '.wav',
        '.ogg',
        '.m4b',
        '.wma',
        '.alac',
        '.aiff',
        '.mp3'
      };

      if (metadataExtensions.contains(extension)) {
        try {
          metadataResult = await _parseWithMediaMetadata(file);
          if (extension == '.m4a' ||
              extension == '.mp4' ||
              extension == '.m4b') {
            final bytes = await file.readAsBytes();
            metadataResult = _mergeMetadata(
              metadataResult,
              _parseMp4Tags(bytes),
            );
          }
          if (metadataResult.isNotEmpty && extension != '.mp3') {
            final enriched = await _withDurationFallback(file, metadataResult);
            _tagCache[filePath] = enriched;
            return enriched;
          }
        } catch (e) {
          if (kDebugMode) print('Media metadata failed for $filePath: $e');
        }
      }

      // 2) MP3 via id3 package (ID3v2)
      if (extension == '.mp3') {
        try {
          final bytes = await file
              .readAsBytes(); // MP3 parsing generally needs full bytes
          final mp3Res = <String, dynamic>{...metadataResult};
          mp3Res.addAll(_parseMp3Tags(bytes));
          mp3Res.addAll(_parseManualId3Cover(bytes));
          if (mp3Res.isNotEmpty) {
            final enriched =
                await _withDurationFallback(file, mp3Res, bytes: bytes);
            _tagCache[filePath] = enriched;
            return enriched;
          }

          // try ID3v1 fallback
          final id3v1 = _parseId3v1(bytes);
          if (id3v1.isNotEmpty) {
            final merged = <String, dynamic>{...metadataResult, ...id3v1};
            final enriched =
                await _withDurationFallback(file, merged, bytes: bytes);
            _tagCache[filePath] = enriched;
            return enriched;
          }
        } catch (e) {
          if (kDebugMode) print('MP3 parsing failed: $e');
        }
      }

      // 3) Manual MP4/M4A cover fallback when platform metadata misses covr.
      if (extension == '.m4a' || extension == '.mp4' || extension == '.m4b') {
        try {
          final bytes = await file.readAsBytes();
          final mp4Res = _parseMp4Tags(bytes);
          if (mp4Res.isNotEmpty) {
            final enriched =
                await _withDurationFallback(file, mp4Res, bytes: bytes);
            _tagCache[filePath] = enriched;
            return enriched;
          }
        } catch (e) {
          if (kDebugMode) print('MP4 cover parse error: $e');
        }
      }

      // 3) Try FLAC manual parsing if file starts with 'fLaC'
      try {
        if (header.length >= 4 &&
            header[0] == 0x66 &&
            header[1] == 0x4C &&
            header[2] == 0x61 &&
            header[3] == 0x43) {
          // read full bytes only for FLAC parsing
          final bytes = await file.readAsBytes();
          final flacRes = _parseFlacBlocks(bytes);
          if (flacRes.isNotEmpty) {
            final enriched =
                await _withDurationFallback(file, flacRes, bytes: bytes);
            _tagCache[filePath] = enriched;
            return enriched;
          }
        }
      } catch (e) {
        if (kDebugMode) print('FLAC parse error: $e');
      }

      // 4) Try APEv2 tags (often in .ape, some mp3s)
      try {
        final apeRes = await _parseApeTag(file);
        if (apeRes.isNotEmpty) {
          final enriched = await _withDurationFallback(file, apeRes);
          _tagCache[filePath] = enriched;
          return enriched;
        }
      } catch (e) {
        if (kDebugMode) print('APE parse error: $e');
      }

      // 5) Fallback: filename parsing
      result = _parseFromFilename(filePath);
      result = <String, dynamic>{...metadataResult, ...result};
      result = await _withDurationFallback(file, result);
      _tagCache[filePath] = result;
      return result;
    } catch (e) {
      if (kDebugMode) print('Error parsing tags from $filePath: $e');
      return {};
    }
  }

  // ----------------------------
  // MP3: id3 v2 via package
  Map<String, dynamic> _parseMp3Tags(Uint8List bytes) {
    final result = <String, dynamic>{};

    try {
      final mp3 = MP3Instance(bytes);
      final success = mp3.parseTagsSync();
      if (success) {
        final tags = mp3.getMetaTags();
        if (tags != null) {
          void putIfNonEmpty(String key, dynamic val) {
            if (val != null && val.toString().isNotEmpty) result[key] = val;
          }

          putIfNonEmpty('title', tags['Title']);
          putIfNonEmpty('artist', tags['Artist']);
          putIfNonEmpty('album', tags['Album']);
          putIfNonEmpty('track', tags['Track']);
          putIfNonEmpty('year', tags['Year']);
          putIfNonEmpty('genre', tags['Genre']);
          putIfNonEmpty('durationMs', tags['TLEN']);

          // Cover: APIC frame (may be Map with base64)
          if (tags.containsKey('APIC') && tags['APIC'] != null) {
            final apic = tags['APIC'] as Map<String, dynamic>;
            if (apic.containsKey('base64') && apic['base64'] != null) {
              final maybe = apic['base64'].toString();
              if (_looksLikeBase64(maybe)) {
                try {
                  result['cover'] = base64.decode(maybe);
                } catch (_) {}
              }
            }
          }
        }
      }
    } catch (e) {
      if (kDebugMode) print('Error parsing MP3 tags: $e');
    }

    return result;
  }

  // ----------------------------
  // Manual ID3 cover fallback for MP3 files where package parsing misses APIC.
  Map<String, dynamic> _parseManualId3Cover(Uint8List bytes) {
    final cover = _extractId3Cover(bytes);
    if (cover == null) return {};
    return {'cover': cover};
  }

  Uint8List? _extractId3Cover(Uint8List bytes) {
    if (bytes.length < 16 ||
        bytes[0] != 0x49 ||
        bytes[1] != 0x44 ||
        bytes[2] != 0x33) {
      return null;
    }

    final version = bytes[3];
    final tagSize = _syncSafeIntAt(bytes, 6);
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
          final cover = _parsePicCover(bytes.sublist(offset, offset + size));
          if (cover != null) return cover;
        }
        offset += size;
        continue;
      }

      final id = String.fromCharCodes(bytes.sublist(offset, offset + 4));
      final size = version == 4
          ? _syncSafeIntAt(bytes, offset + 4)
          : _readBe32(bytes, offset + 4);
      offset += 10;
      if (id.trim().isEmpty || size <= 0 || offset + size > end) break;
      if (id == 'APIC') {
        final cover = _parseApicCover(bytes.sublist(offset, offset + size));
        if (cover != null) return cover;
      }
      offset += size;
    }
    return null;
  }

  Uint8List? _parseApicCover(Uint8List frame) {
    if (frame.length < 8) return null;
    var index = 1;
    final mimeEnd = frame.indexOf(0, index);
    if (mimeEnd == -1 || mimeEnd + 2 >= frame.length) return null;
    index = mimeEnd + 2;
    index = _skipId3Description(frame, index, frame[0]);
    if (index >= frame.length) return null;
    final cover = frame.sublist(index);
    return _looksLikeImage(cover) ? cover : null;
  }

  Uint8List? _parsePicCover(Uint8List frame) {
    if (frame.length < 7) return null;
    final index = _skipId3Description(frame, 5, frame[0]);
    if (index >= frame.length) return null;
    final cover = frame.sublist(index);
    return _looksLikeImage(cover) ? cover : null;
  }

  int _skipId3Description(Uint8List frame, int index, int encoding) {
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

  int _syncSafeIntAt(Uint8List bytes, int offset) {
    if (offset < 0 || offset + 4 > bytes.length) return 0;
    return (bytes[offset] << 21) |
        (bytes[offset + 1] << 14) |
        (bytes[offset + 2] << 7) |
        bytes[offset + 3];
  }

  // ----------------------------
  // ID3v1 manual parser (last 128 bytes of mp3)
  Map<String, dynamic> _parseId3v1(Uint8List bytes) {
    final result = <String, dynamic>{};
    try {
      if (bytes.length < 128) return {};
      final tail = bytes.sublist(bytes.length - 128);
      // 'TAG' at start
      if (tail.length >= 3 &&
          tail[0] == 0x54 &&
          tail[1] == 0x41 &&
          tail[2] == 0x47) {
        String _readString(List<int> arr, int start, int len) {
          final sub = arr.sublist(start, start + len);
          return _decodeString(sub).replaceAll('\x00', '').trim();
        }

        final title = _readString(tail, 3, 30);
        final artist = _readString(tail, 33, 30);
        final album = _readString(tail, 63, 30);
        final year = _readString(tail, 93, 4);

        if (title.isNotEmpty) result['title'] = title;
        if (artist.isNotEmpty) result['artist'] = artist;
        if (album.isNotEmpty) result['album'] = album;
        if (year.isNotEmpty) result['year'] = year;
      }
    } catch (e) {
      if (kDebugMode) print('ID3v1 parse error: $e');
    }
    return result;
  }

  // ----------------------------
  // APEv2 tag parsing (simple implementation)
  // APE tags often appear at end of file with "APETAGEX"
  Future<Map<String, dynamic>> _parseApeTag(io.File file) async {
    final result = <String, dynamic>{};
    try {
      final len = await file.length();
      if (len == 0) return {};
      final tailSize =
          len < 16 * 1024 ? len : 16 * 1024; // read up to last 16KB
      final raf = await file.open();
      await raf.setPosition(len - tailSize);
      final tailBytesList = await raf.read(tailSize);
      await raf.close();
      final tailBytes = Uint8List.fromList(tailBytesList);

      // Find 'APETAGEX'
      final magic = utf8.encode('APETAGEX');
      int idx = _indexOf(tailBytes, magic);
      if (idx < 0) return {};

      // header starts at idx within tailBytes
      final headerOffset = idx;
      if (headerOffset + 32 > tailBytes.length) return {};

      // header fields little-endian
      final header = tailBytes.sublist(headerOffset, headerOffset + 32);
      int le32(List<int> b, int off) =>
          b[off] | (b[off + 1] << 8) | (b[off + 2] << 16) | (b[off + 3] << 24);

      final version = le32(header, 8);
      final size = le32(header, 12);
      final itemCount = le32(header, 16);

      if (size <= 0 || size > len) return {};

      // read tag block from absolute position
      final full = await file.open();
      await full.setPosition(len - size);
      final blockList = await full.read(size);
      await full.close();
      final block = Uint8List.fromList(blockList);

      int pos = 32; // skip header
      for (int i = 0; i < itemCount && pos + 8 <= block.length; i++) {
        final vlen = le32(block, pos);
        final flags = le32(block, pos + 4);
        pos += 8;
        // read key until null
        final keyStart = pos;
        int keyEnd = keyStart;
        while (keyEnd < block.length && block[keyEnd] != 0) keyEnd++;
        if (keyEnd >= block.length) break;
        final key =
            _decodeString(block.sublist(keyStart, keyEnd)).toLowerCase();
        pos = keyEnd + 1;
        // value
        if (pos + vlen > block.length) break;
        final valueBytes = block.sublist(pos, pos + vlen);
        final value = _decodeString(valueBytes, allowMalformed: true);
        pos += vlen;

        if (key == 'title' && value.isNotEmpty) result['title'] = value;
        if (key == 'artist' && value.isNotEmpty) result['artist'] = value;
        if ((key == 'album' || key == 'albumtitle') && value.isNotEmpty)
          result['album'] = value;
        if ((key == 'year' || key == 'date') && value.isNotEmpty)
          result['year'] = value;
        if ((key == 'genre') && value.isNotEmpty) result['genre'] = value;

        if (key.contains('cover') || key.contains('art')) {
          final maybe = value.trim();
          if (_looksLikeBase64(maybe)) {
            try {
              final decoded = base64.decode(maybe);
              if (decoded.isNotEmpty) result['cover'] = decoded;
            } catch (_) {}
          }
        }
      }
    } catch (e) {
      if (kDebugMode) print('APE parse exception: $e');
    }
    return result;
  }

  // helper: find subarray (naive)
  int _indexOf(Uint8List data, List<int> pattern) {
    if (pattern.isEmpty || data.length < pattern.length) return -1;
    final int limit = data.length - pattern.length;
    for (int i = 0; i <= limit; i++) {
      bool ok = true;
      for (int j = 0; j < pattern.length; j++) {
        if (data[i + j] != pattern[j]) {
          ok = false;
          break;
        }
      }
      if (ok) return i;
    }
    return -1;
  }

  Map<String, dynamic> _parseMp4Tags(Uint8List bytes) {
    final result = <String, dynamic>{};
    final textTags = <String, List<int>>{
      'title': [0xA9, 0x6E, 0x61, 0x6D],
      'artist': [0xA9, 0x41, 0x52, 0x54],
      'albumArtist': [0x61, 0x41, 0x52, 0x54],
      'album': [0xA9, 0x61, 0x6C, 0x62],
      'genre': [0xA9, 0x67, 0x65, 0x6E],
      'year': [0xA9, 0x64, 0x61, 0x79],
    };

    try {
      for (final entry in textTags.entries) {
        final value = _readMp4TextTag(bytes, entry.value);
        if (value == null || value.isEmpty) continue;
        if (entry.key == 'albumArtist') {
          result.putIfAbsent('artist', () => value);
        } else {
          result[entry.key] = value;
        }
      }

      final track = _readMp4NumberPairTag(bytes, [0x74, 0x72, 0x6B, 0x6E]);
      if (track != null) result['track'] = track;

      result.addAll(_parseMp4Cover(bytes));
    } catch (e) {
      if (kDebugMode) print('MP4 tag parse exception: $e');
    }

    return result;
  }

  Map<String, dynamic> _mergeMetadata(
    Map<String, dynamic> primary,
    Map<String, dynamic> fallback,
  ) {
    final merged = <String, dynamic>{...primary};
    for (final entry in fallback.entries) {
      final current = merged[entry.key];
      final next = entry.value;
      if (entry.key == 'cover' && _hasUsefulMetadataValue(current)) continue;
      if (_hasUsefulMetadataValue(next)) merged[entry.key] = next;
    }
    return merged;
  }

  bool _hasUsefulMetadataValue(dynamic value) {
    if (value == null) return false;
    if (value is Uint8List) return value.isNotEmpty;
    if (value is Iterable) return value.isNotEmpty;
    return value.toString().trim().isNotEmpty;
  }

  String? _readMp4TextTag(Uint8List bytes, List<int> atomType) {
    for (final payload in _readMp4DataPayloads(bytes, atomType)) {
      final value = _decodeString(payload, allowMalformed: true)
          .replaceAll('\x00', '')
          .trim();
      if (value.isNotEmpty) return value;
    }
    return null;
  }

  String? _readMp4NumberPairTag(Uint8List bytes, List<int> atomType) {
    for (final payload in _readMp4DataPayloads(bytes, atomType)) {
      if (payload.length < 6) continue;
      final current = (payload[2] << 8) | payload[3];
      final total = (payload[4] << 8) | payload[5];
      if (current <= 0) continue;
      return total > 0 ? '$current/$total' : current.toString();
    }
    return null;
  }

  List<Uint8List> _readMp4DataPayloads(
    Uint8List bytes,
    List<int> atomType,
  ) {
    final payloads = <Uint8List>[];
    var searchFrom = 0;

    while (searchFrom < bytes.length) {
      final typeIndex = _indexOfFrom(bytes, atomType, searchFrom);
      if (typeIndex < 4) break;

      final atomStart = typeIndex - 4;
      final atomSize = _readBe32(bytes, atomStart);
      final atomEnd = atomStart + atomSize;
      if (atomSize < 16 || atomEnd > bytes.length) {
        searchFrom = typeIndex + atomType.length;
        continue;
      }

      var child = typeIndex + 4;
      while (child + 16 <= atomEnd) {
        final childSize = _readBe32(bytes, child);
        if (childSize < 16 || child + childSize > atomEnd) break;
        if (_asciiEquals(bytes, child + 4, 'data')) {
          final payloadStart = child + 16;
          final payloadEnd = child + childSize;
          if (payloadStart < payloadEnd) {
            payloads.add(bytes.sublist(payloadStart, payloadEnd));
          }
        }
        child += childSize;
      }

      searchFrom = typeIndex + atomType.length;
    }

    return payloads;
  }

  Map<String, dynamic> _parseMp4Cover(Uint8List bytes) {
    final result = <String, dynamic>{};
    try {
      final covr = utf8.encode('covr');
      int searchFrom = 0;
      while (searchFrom < bytes.length) {
        final typeIndex = _indexOfFrom(bytes, covr, searchFrom);
        if (typeIndex < 4) return result;

        final covrStart = typeIndex - 4;
        final covrSize = _readBe32(bytes, covrStart);
        final covrEnd = covrStart + covrSize;
        if (covrSize < 16 || covrEnd > bytes.length) {
          searchFrom = typeIndex + 4;
          continue;
        }

        int child = typeIndex + 4;
        while (child + 16 <= covrEnd) {
          final childSize = _readBe32(bytes, child);
          if (childSize < 16 || child + childSize > covrEnd) break;

          if (_asciiEquals(bytes, child + 4, 'data')) {
            final payloadStart = child + 16;
            final payloadEnd = child + childSize;
            if (payloadStart < payloadEnd) {
              final cover = bytes.sublist(payloadStart, payloadEnd);
              if (_looksLikeImage(cover)) {
                result['cover'] = cover;
                return result;
              }
            }
          }
          child += childSize;
        }

        searchFrom = typeIndex + 4;
      }
    } catch (e) {
      if (kDebugMode) print('MP4 covr parse exception: $e');
    }
    return result;
  }

  int _indexOfFrom(Uint8List data, List<int> pattern, int start) {
    if (pattern.isEmpty || data.length < pattern.length) return -1;
    final int limit = data.length - pattern.length;
    for (int i = start; i <= limit; i++) {
      bool ok = true;
      for (int j = 0; j < pattern.length; j++) {
        if (data[i + j] != pattern[j]) {
          ok = false;
          break;
        }
      }
      if (ok) return i;
    }
    return -1;
  }

  int _readBe32(Uint8List bytes, int offset) {
    if (offset < 0 || offset + 4 > bytes.length) return 0;
    return (bytes[offset] << 24) |
        (bytes[offset + 1] << 16) |
        (bytes[offset + 2] << 8) |
        bytes[offset + 3];
  }

  bool _asciiEquals(Uint8List bytes, int offset, String text) {
    if (offset < 0 || offset + text.length > bytes.length) return false;
    for (int i = 0; i < text.length; i++) {
      if (bytes[offset + i] != text.codeUnitAt(i)) return false;
    }
    return true;
  }

  bool _looksLikeImage(Uint8List bytes) {
    if (bytes.length < 8) return false;
    final isJpeg = bytes[0] == 0xFF && bytes[1] == 0xD8;
    final isPng = bytes[0] == 0x89 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x4E &&
        bytes[3] == 0x47;
    return isJpeg || isPng;
  }

  // ----------------------------
  // FLAC block parser: Vorbis comment (type 4) + PICTURE (type 6)
  Map<String, dynamic> _parseFlacBlocks(Uint8List bytes) {
    final result = <String, dynamic>{};
    try {
      // bytes start with 'fLaC'
      if (bytes.length < 8) return {};
      if (!(bytes[0] == 0x66 &&
          bytes[1] == 0x4C &&
          bytes[2] == 0x61 &&
          bytes[3] == 0x43)) {
        return {};
      }
      int pos = 4;
      bool isLast = false;
      while (!isLast && pos + 4 <= bytes.length) {
        final headerByte = bytes[pos];
        isLast = (headerByte & 0x80) != 0;
        final type = headerByte & 0x7f;
        // 24-bit length big-endian
        if (pos + 3 >= bytes.length) break;
        final len =
            (bytes[pos + 1] << 16) | (bytes[pos + 2] << 8) | bytes[pos + 3];
        pos += 4;
        if (len < 0 || pos + len > bytes.length) break;
        final block = bytes.sublist(pos, pos + len);

        if (type == 4) {
          // VORBIS_COMMENT: little-endian ints
          int off = 0;
          int readLe32() {
            if (off + 4 > block.length) return 0;
            final v = block[off] |
                (block[off + 1] << 8) |
                (block[off + 2] << 16) |
                (block[off + 3] << 24);
            off += 4;
            return v;
          }

          final vendorLen = readLe32();
          if (vendorLen < 0 || off + vendorLen > block.length) {
            // invalid; skip
          } else {
            off += vendorLen;
            if (off + 4 <= block.length) {
              final userCount = readLe32();
              for (int i = 0; i < userCount; i++) {
                if (off + 4 > block.length) break;
                final clen = (block[off]) |
                    (block[off + 1] << 8) |
                    (block[off + 2] << 16) |
                    (block[off + 3] << 24);
                off += 4;
                if (clen < 0 || off + clen > block.length) break;
                final comment = _decodeString(block.sublist(off, off + clen),
                    allowMalformed: true);
                off += clen;
                final idxEq = comment.indexOf('=');
                if (idxEq > 0) {
                  final key = comment.substring(0, idxEq).toUpperCase();
                  final value = comment.substring(idxEq + 1);
                  switch (key) {
                    case 'TITLE':
                      result['title'] = value;
                      break;
                    case 'ARTIST':
                      result['artist'] = value;
                      break;
                    case 'ALBUM':
                      result['album'] = value;
                      break;
                    case 'DATE':
                    case 'YEAR':
                      result['year'] = value;
                      break;
                    case 'GENRE':
                      result['genre'] = value;
                      break;
                    default:
                      break;
                  }
                }
              }
            }
          }
        } else if (type == 6) {
          // PICTURE block
          int off = 0;
          int readBe32() {
            if (off + 4 > block.length) return 0;
            final v = (block[off] << 24) |
                (block[off + 1] << 16) |
                (block[off + 2] << 8) |
                (block[off + 3]);
            off += 4;
            return v;
          }

          if (block.length >= 32) {
            final picType = readBe32();
            final mimeLen = readBe32();
            String mime = '';
            if (mimeLen > 0 && off + mimeLen <= block.length) {
              mime = _decodeString(block.sublist(off, off + mimeLen));
            }
            off += mimeLen;
            final descLen = readBe32();
            off += descLen;
            if (off + 16 <= block.length) off += 16;
            final dataLen = readBe32();
            if (dataLen > 0 && off + dataLen <= block.length) {
              final picData = block.sublist(off, off + dataLen);
              result['cover'] = picData;
            }
          }
        }

        pos += len;
      }
    } catch (e) {
      if (kDebugMode) print('FLAC block parse error: $e');
    }
    return result;
  }

  // ----------------------------
  // flutter_media_metadata fallback (cross-platform)
  Future<Duration?> parseDurationFromFile(String filePath) async {
    if (kIsWeb) return null;
    try {
      final file = io.File(filePath);
      if (!await file.exists()) return null;
      final tags =
          await _parseWithMediaMetadataInternal(file, includeCover: false);
      return _durationFromTags(tags) ?? await _parseContainerDuration(file);
    } catch (e) {
      if (kDebugMode) print('Duration parse failed for $filePath: $e');
      return null;
    }
  }

  Future<Map<String, dynamic>> _parseWithMediaMetadata(io.File file) async {
    return _parseWithMediaMetadataInternal(file, includeCover: true);
  }

  Future<Map<String, dynamic>> _parseWithMediaMetadataInternal(
    io.File file, {
    required bool includeCover,
  }) async {
    final result = <String, dynamic>{};
    try {
      final metadata = await MetadataRetriever.fromFile(file);

      if (metadata.trackName != null && metadata.trackName!.isNotEmpty)
        result['title'] = metadata.trackName;
      if (metadata.trackArtistNames != null) {
        final artists = metadata.trackArtistNames;
        if (artists is List)
          result['artist'] = (artists as List).join(', ');
        else
          result['artist'] = artists.toString();
      }
      if (metadata.albumName != null && metadata.albumName!.isNotEmpty)
        result['album'] = metadata.albumName;
      if (metadata.trackNumber != null)
        result['track'] = metadata.trackNumber.toString();
      if (metadata.year != null) result['year'] = metadata.year.toString();
      if (metadata.genre != null && metadata.genre!.isNotEmpty)
        result['genre'] = metadata.genre;
      if (includeCover &&
          metadata.albumArt != null &&
          metadata.albumArt!.isNotEmpty) {
        result['cover'] = metadata.albumArt;
      }
      if (metadata.mimeType != null) result['mimeType'] = metadata.mimeType;
      if (metadata.bitrate != null) result['bitrate'] = metadata.bitrate;
      if (metadata.trackDuration != null)
        result['trackDuration'] = metadata.trackDuration;
    } catch (e) {
      if (kDebugMode)
        print('flutter_media_metadata failed for ${file.path}: $e');
    }
    return result;
  }

  // ----------------------------
  // Filename fallback
  Map<String, dynamic> _parseFromFilename(String filePath) {
    final fileName = path.basenameWithoutExtension(filePath);
    final result = <String, dynamic>{};

    if (fileName.contains(' - ')) {
      final parts = fileName.split(' - ');
      if (parts.length >= 2) {
        result['artist'] = parts[0].trim();
        result['title'] = parts.sublist(1).join(' - ').trim();
      }
    } else {
      result['title'] = fileName;
      result['artist'] = 'Unknown Artist';
    }
    result['album'] = 'Unknown Album';
    return result;
  }

  // ----------------------------
  // Parse tags from asset (copy to temp and reuse parseTagsFromFile)
  Future<Map<String, dynamic>> parseTagsFromAsset(String assetPath) async {
    if (kIsWeb) return {};
    try {
      final tempDir = await io.Directory.systemTemp.createTemp('fluttersp');
      final tempFile = io.File('${tempDir.path}/${path.basename(assetPath)}');
      final ByteData byteData = await rootBundle.load(assetPath);
      await tempFile.writeAsBytes(byteData.buffer.asUint8List());
      final tags = await parseTagsFromFile(tempFile.path);
      try {
        await tempFile.delete();
        await tempDir.delete();
      } catch (_) {}
      return tags;
    } catch (e) {
      if (kDebugMode) print('Error parsing tags from asset $assetPath: $e');
      return {};
    }
  }

  // ----------------------------
  // Extract cover bytes (Uint8List) if present
  Uint8List? extractCover(Map<String, dynamic> tags) {
    if (tags.containsKey('cover')) {
      final cover = tags['cover'];
      if (cover is Uint8List) return cover;
      if (cover is List<int>) return Uint8List.fromList(cover);
    }
    return null;
  }

  // Cover cache to avoid redundant cover art extraction and writing
  static final Map<String, String> _coverCache = {};

  // ----------------------------
  // Create Music model from parsed tags. If cover exists, write to permanent file and set coverPath.
  Music createMusicFromTags(String filePath, Map<String, dynamic> tags,
      {String? coverDirectory}) {
    final fileName = path.basenameWithoutExtension(filePath);
    String coverPath = '';

    try {
      // Check if cover already exists in cache
      if (_coverCache.containsKey(filePath)) {
        coverPath = _coverCache[filePath]!;
      } else {
        final coverBytes = extractCover(tags);
        if (coverBytes != null && coverBytes.isNotEmpty) {
          // Use a hash of the file path for the cover filename to ensure it's unique and stable
          final hash = md5.convert(utf8.encode(filePath)).toString();

          final io.Directory dir = coverDirectory != null
              ? io.Directory(coverDirectory)
              : io.Directory.systemTemp;

          if (!dir.existsSync()) {
            dir.createSync(recursive: true);
          }

          final extension = _coverFileExtension(coverBytes);
          final coverFile =
              io.File('${dir.path}/${hash}_cover_native$extension');
          if (!coverFile.existsSync()) {
            coverFile.writeAsBytesSync(coverBytes);
          }
          coverPath = coverFile.path;
          _coverCache[filePath] = coverPath; // Cache the cover path
        } else {
          final sidecar = _findSidecarCover(filePath);
          if (sidecar != null) {
            coverPath = sidecar.path;
            _coverCache[filePath] = coverPath;
          }
        }
      }
    } catch (e) {
      if (kDebugMode) print('Failed to write cover file: $e');
    }

    return Music(
      id: fileName,
      title: tags['title']?.toString() ?? fileName,
      artist: tags['artist']?.toString() ?? 'Unknown Artist',
      album: tags['album']?.toString() ?? 'Unknown Album',
      genre: tags['genre']?.toString() ?? 'Unknown',
      filePath: filePath,
      coverPath: coverPath,
      duration: _durationFromTags(tags),
    );
  }

  Duration? _durationFromTags(Map<String, dynamic> tags) {
    final trackDuration = _durationNumber(tags['trackDuration']);
    if (trackDuration != null) {
      return Duration(milliseconds: trackDuration);
    }

    final durationMs = _durationNumber(tags['durationMs']);
    if (durationMs != null) {
      return Duration(milliseconds: durationMs);
    }

    final duration = _durationNumber(tags['duration']);
    if (duration == null) return null;
    return Duration(
      milliseconds: duration < 10000 ? duration * 1000 : duration,
    );
  }

  int? _durationNumber(dynamic raw) {
    if (raw == null) return null;
    final value = raw is num ? raw.toInt() : int.tryParse(raw.toString());
    if (value == null || value <= 0) return null;
    return value;
  }

  Future<Map<String, dynamic>> _withDurationFallback(
    io.File file,
    Map<String, dynamic> tags, {
    Uint8List? bytes,
  }) async {
    if (_durationFromTags(tags) != null) return tags;

    final duration = await _parseContainerDuration(file, bytes: bytes);
    if (duration == null || duration <= Duration.zero) return tags;
    return <String, dynamic>{
      ...tags,
      'trackDuration': duration.inMilliseconds,
    };
  }

  Future<Duration?> _parseContainerDuration(
    io.File file, {
    Uint8List? bytes,
  }) async {
    try {
      final extension = path.extension(file.path).toLowerCase();
      final data = bytes ?? await file.readAsBytes();
      switch (extension) {
        case '.mp3':
          return _parseMp3Duration(data);
        case '.flac':
          return _parseFlacDuration(data);
        case '.wav':
          return _parseWavDuration(data);
        case '.m4a':
        case '.mp4':
        case '.m4b':
        case '.aac':
          return _parseIsoBmffDuration(data);
        default:
          return _parseFlacDuration(data) ??
              _parseWavDuration(data) ??
              _parseMp3Duration(data) ??
              _parseIsoBmffDuration(data);
      }
    } catch (e) {
      if (kDebugMode) print('Container duration parse failed: $e');
      return null;
    }
  }

  Duration? _parseMp3Duration(Uint8List bytes) {
    if (bytes.length < 16) return null;

    var offset = 0;
    if (_asciiEquals(bytes, 0, 'ID3') && bytes.length >= 10) {
      final flags = bytes[5];
      offset = 10 + _syncSafeIntAt(bytes, 6) + ((flags & 0x10) != 0 ? 10 : 0);
    }

    while (offset + 4 < bytes.length) {
      final header = _readBe32(bytes, offset);
      final frame = _mpegFrameInfo(header);
      if (frame == null) {
        offset++;
        continue;
      }

      final xing = _xingFrameCount(bytes, offset, frame);
      if (xing != null && xing > 0) {
        return Duration(
          milliseconds:
              ((xing * frame.samplesPerFrame * 1000) / frame.sampleRate)
                  .round(),
        );
      }

      final audioBytes = bytes.length - offset - _id3v1TailSize(bytes);
      if (frame.bitrateKbps > 0 && audioBytes > 0) {
        final seconds = (audioBytes * 8) / (frame.bitrateKbps * 1000);
        return Duration(milliseconds: (seconds * 1000).round());
      }
      return null;
    }
    return null;
  }

  _MpegFrameInfo? _mpegFrameInfo(int header) {
    if ((header & 0xFFE00000) != 0xFFE00000) return null;

    final versionBits = (header >> 19) & 0x3;
    final layerBits = (header >> 17) & 0x3;
    final bitrateIndex = (header >> 12) & 0xF;
    final sampleRateIndex = (header >> 10) & 0x3;
    final channelMode = (header >> 6) & 0x3;

    if (versionBits == 1 ||
        layerBits == 0 ||
        bitrateIndex == 0 ||
        bitrateIndex == 15 ||
        sampleRateIndex == 3) {
      return null;
    }

    final version = switch (versionBits) {
      3 => 1,
      2 => 2,
      _ => 25,
    };
    final layer = switch (layerBits) {
      3 => 1,
      2 => 2,
      _ => 3,
    };

    const sampleRates = {
      1: [44100, 48000, 32000],
      2: [22050, 24000, 16000],
      25: [11025, 12000, 8000],
    };

    final bitrateKbps = _mpegBitrate(version, layer, bitrateIndex);
    final sampleRate = sampleRates[version]![sampleRateIndex];
    final samplesPerFrame = layer == 1
        ? 384
        : layer == 3 && version != 1
            ? 576
            : 1152;

    return _MpegFrameInfo(
      version: version,
      layer: layer,
      bitrateKbps: bitrateKbps,
      sampleRate: sampleRate,
      samplesPerFrame: samplesPerFrame,
      isMono: channelMode == 3,
    );
  }

  int _mpegBitrate(int version, int layer, int index) {
    const mpeg1Layer1 = [
      0,
      32,
      64,
      96,
      128,
      160,
      192,
      224,
      256,
      288,
      320,
      352,
      384,
      416,
      448
    ];
    const mpeg1Layer2 = [
      0,
      32,
      48,
      56,
      64,
      80,
      96,
      112,
      128,
      160,
      192,
      224,
      256,
      320,
      384
    ];
    const mpeg1Layer3 = [
      0,
      32,
      40,
      48,
      56,
      64,
      80,
      96,
      112,
      128,
      160,
      192,
      224,
      256,
      320
    ];
    const mpeg2Layer1 = [
      0,
      32,
      48,
      56,
      64,
      80,
      96,
      112,
      128,
      144,
      160,
      176,
      192,
      224,
      256
    ];
    const mpeg2Layer23 = [
      0,
      8,
      16,
      24,
      32,
      40,
      48,
      56,
      64,
      80,
      96,
      112,
      128,
      144,
      160
    ];

    if (version == 1 && layer == 1) return mpeg1Layer1[index];
    if (version == 1 && layer == 2) return mpeg1Layer2[index];
    if (version == 1) return mpeg1Layer3[index];
    if (layer == 1) return mpeg2Layer1[index];
    return mpeg2Layer23[index];
  }

  int? _xingFrameCount(Uint8List bytes, int frameOffset, _MpegFrameInfo frame) {
    final sideInfoSize = frame.layer == 3
        ? frame.version == 1
            ? (frame.isMono ? 17 : 32)
            : (frame.isMono ? 9 : 17)
        : 0;
    final start = frameOffset + 4 + sideInfoSize;
    if (start + 16 > bytes.length) return null;
    if (!_asciiEquals(bytes, start, 'Xing') &&
        !_asciiEquals(bytes, start, 'Info')) {
      return null;
    }

    final flags = _readBe32(bytes, start + 4);
    if ((flags & 0x1) == 0) return null;
    return _readBe32(bytes, start + 8);
  }

  int _id3v1TailSize(Uint8List bytes) {
    if (bytes.length >= 128 &&
        bytes[bytes.length - 128] == 0x54 &&
        bytes[bytes.length - 127] == 0x41 &&
        bytes[bytes.length - 126] == 0x47) {
      return 128;
    }
    return 0;
  }

  Duration? _parseFlacDuration(Uint8List bytes) {
    if (bytes.length < 42 || !_asciiEquals(bytes, 0, 'fLaC')) return null;
    final blockType = bytes[4] & 0x7f;
    final blockLength = (bytes[5] << 16) | (bytes[6] << 8) | bytes[7];
    if (blockType != 0 || blockLength < 34 || bytes.length < 42) return null;

    const streamInfoOffset = 8;
    final b10 = bytes[streamInfoOffset + 10];
    final b11 = bytes[streamInfoOffset + 11];
    final b12 = bytes[streamInfoOffset + 12];
    final b13 = bytes[streamInfoOffset + 13];
    final b14 = bytes[streamInfoOffset + 14];
    final b15 = bytes[streamInfoOffset + 15];
    final b16 = bytes[streamInfoOffset + 16];
    final b17 = bytes[streamInfoOffset + 17];

    final sampleRate = (b10 << 12) | (b11 << 4) | (b12 >> 4);
    final totalSamples = ((b13 & 0x0F) * 0x100000000) +
        (b14 << 24) +
        (b15 << 16) +
        (b16 << 8) +
        b17;
    if (sampleRate <= 0 || totalSamples <= 0) return null;
    return Duration(milliseconds: ((totalSamples * 1000) / sampleRate).round());
  }

  Duration? _parseWavDuration(Uint8List bytes) {
    if (bytes.length < 44 ||
        !_asciiEquals(bytes, 0, 'RIFF') ||
        !_asciiEquals(bytes, 8, 'WAVE')) {
      return null;
    }

    var offset = 12;
    int? byteRate;
    int dataSize = 0;
    while (offset + 8 <= bytes.length) {
      final chunkId = String.fromCharCodes(bytes.sublist(offset, offset + 4));
      final chunkSize = _readLe32(bytes, offset + 4);
      final chunkData = offset + 8;
      if (chunkSize < 0 || chunkData + chunkSize > bytes.length) break;

      if (chunkId == 'fmt ' && chunkSize >= 16) {
        byteRate = _readLe32(bytes, chunkData + 8);
      } else if (chunkId == 'data') {
        dataSize += chunkSize;
      }

      offset = chunkData + chunkSize + (chunkSize.isOdd ? 1 : 0);
    }

    if (byteRate == null || byteRate <= 0 || dataSize <= 0) return null;
    return Duration(milliseconds: ((dataSize * 1000) / byteRate).round());
  }

  Duration? _parseIsoBmffDuration(Uint8List bytes) {
    var offset = 0;
    while (offset + 8 <= bytes.length) {
      final size32 = _readBe32(bytes, offset);
      final type = String.fromCharCodes(bytes.sublist(offset + 4, offset + 8));
      int headerSize = 8;
      var size = size32;

      if (size32 == 1 && offset + 16 <= bytes.length) {
        size = _readBe64AsInt(bytes, offset + 8);
        headerSize = 16;
      } else if (size32 == 0) {
        size = bytes.length - offset;
      }

      if (size < headerSize || offset + size > bytes.length) break;
      if (type == 'moov') {
        return _parseMoovDuration(bytes, offset + headerSize, offset + size);
      }
      offset += size;
    }
    return null;
  }

  Duration? _parseMoovDuration(Uint8List bytes, int start, int end) {
    var offset = start;
    while (offset + 8 <= end) {
      final size = _readBe32(bytes, offset);
      final type = String.fromCharCodes(bytes.sublist(offset + 4, offset + 8));
      if (size < 8 || offset + size > end) break;
      if (type == 'mvhd') {
        return _parseMvhdDuration(bytes, offset + 8, offset + size);
      }
      offset += size;
    }
    return null;
  }

  Duration? _parseMvhdDuration(Uint8List bytes, int start, int end) {
    if (start + 20 > end) return null;
    final version = bytes[start];
    if (version == 1) {
      if (start + 32 > end) return null;
      final timescale = _readBe32(bytes, start + 20);
      final duration = _readBe64AsInt(bytes, start + 24);
      if (timescale <= 0 || duration <= 0) return null;
      return Duration(milliseconds: ((duration * 1000) / timescale).round());
    }

    final timescale = _readBe32(bytes, start + 12);
    final duration = _readBe32(bytes, start + 16);
    if (timescale <= 0 || duration <= 0) return null;
    return Duration(milliseconds: ((duration * 1000) / timescale).round());
  }

  int _readLe32(Uint8List bytes, int offset) {
    if (offset < 0 || offset + 4 > bytes.length) return 0;
    return bytes[offset] |
        (bytes[offset + 1] << 8) |
        (bytes[offset + 2] << 16) |
        (bytes[offset + 3] << 24);
  }

  int _readBe64AsInt(Uint8List bytes, int offset) {
    if (offset < 0 || offset + 8 > bytes.length) return 0;
    var value = 0;
    for (var i = 0; i < 8; i++) {
      value = (value * 256) + bytes[offset + i];
    }
    return value;
  }

  String _coverFileExtension(Uint8List bytes) {
    if (bytes.length >= 8 &&
        bytes[0] == 0x89 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x4E &&
        bytes[3] == 0x47) {
      return '.png';
    }
    if (bytes.length >= 2 && bytes[0] == 0xFF && bytes[1] == 0xD8) {
      return '.jpg';
    }
    if (bytes.length >= 12 &&
        bytes[0] == 0x52 &&
        bytes[1] == 0x49 &&
        bytes[2] == 0x46 &&
        bytes[3] == 0x46 &&
        bytes[8] == 0x57 &&
        bytes[9] == 0x45 &&
        bytes[10] == 0x42 &&
        bytes[11] == 0x50) {
      return '.webp';
    }
    return '.img';
  }

  io.File? _findSidecarCover(String filePath) {
    final media = io.File(filePath);
    final dir = media.parent;
    if (!dir.existsSync()) return null;

    final stem = path.basenameWithoutExtension(filePath).toLowerCase();
    const imageExtensions = {'.jpg', '.jpeg', '.png', '.webp'};
    final preferredNames = {
      '$stem.cover',
      '$stem',
      'cover',
      'folder',
      'album',
    };

    try {
      final images = dir
          .listSync(followLinks: false)
          .whereType<io.File>()
          .where((file) =>
              imageExtensions.contains(path.extension(file.path).toLowerCase()))
          .toList();

      for (final file in images) {
        final name = path.basenameWithoutExtension(file.path).toLowerCase();
        if (preferredNames.contains(name)) {
          return file;
        }
      }
    } catch (_) {}

    return null;
  }

  // ----------------------------
  // Helpers
  String _decodeString(List<int> bytes, {bool allowMalformed = false}) {
    try {
      return utf8.decode(bytes, allowMalformed: allowMalformed);
    } catch (_) {
      try {
        return latin1.decode(bytes);
      } catch (_) {
        return String.fromCharCodes(bytes);
      }
    }
  }

  bool _looksLikeBase64(String s) {
    final trimmed = s.replaceAll(RegExp(r'\s+'), '');
    if (trimmed.length < 24) return false;
    if (trimmed.length % 4 != 0) return false;
    final base64Reg = RegExp(r'^[A-Za-z0-9+/]+={0,2}$');
    return base64Reg.hasMatch(trimmed);
  }
}

class _MpegFrameInfo {
  final int version;
  final int layer;
  final int bitrateKbps;
  final int sampleRate;
  final int samplesPerFrame;
  final bool isMono;

  const _MpegFrameInfo({
    required this.version,
    required this.layer,
    required this.bitrateKbps,
    required this.sampleRate,
    required this.samplesPerFrame,
    required this.isMono,
  });
}
