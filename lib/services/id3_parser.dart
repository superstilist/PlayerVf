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
      return Map.from(_tagCache[filePath]!); // Return copy to prevent modification
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
        '.aiff'
      };

      if (metadataExtensions.contains(extension)) {
        try {
          result = await _parseWithMediaMetadata(file);
          if (result.isNotEmpty) {
            _tagCache[filePath] = result;
            return result;
          }
        } catch (e) {
          if (kDebugMode) print('Media metadata failed for $filePath: $e');
        }
      }

      // 2) MP3 via id3 package (ID3v2)
      if (extension == '.mp3') {
        try {
          final bytes = await file.readAsBytes(); // MP3 parsing generally needs full bytes
          final mp3Res = _parseMp3Tags(bytes);
          if (mp3Res.isNotEmpty) {
            _tagCache[filePath] = mp3Res;
            return mp3Res;
          }

          // try ID3v1 fallback
          final id3v1 = _parseId3v1(bytes);
          if (id3v1.isNotEmpty) {
            _tagCache[filePath] = id3v1;
            return id3v1;
          }
        } catch (e) {
          if (kDebugMode) print('MP3 parsing failed: $e');
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
            _tagCache[filePath] = flacRes;
            return flacRes;
          }
        }
      } catch (e) {
        if (kDebugMode) print('FLAC parse error: $e');
      }

      // 4) Try APEv2 tags (often in .ape, some mp3s)
      try {
        final apeRes = await _parseApeTag(file);
        if (apeRes.isNotEmpty) {
          _tagCache[filePath] = apeRes;
          return apeRes;
        }
      } catch (e) {
        if (kDebugMode) print('APE parse error: $e');
      }

      // 5) Fallback: filename parsing
      result = _parseFromFilename(filePath);
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
      final tailSize = len < 16 * 1024 ? len : 16 * 1024; // read up to last 16KB
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
        final key = _decodeString(block.sublist(keyStart, keyEnd)).toLowerCase();
        pos = keyEnd + 1;
        // value
        if (pos + vlen > block.length) break;
        final valueBytes = block.sublist(pos, pos + vlen);
        final value = _decodeString(valueBytes, allowMalformed: true);
        pos += vlen;

        if (key == 'title' && value.isNotEmpty) result['title'] = value;
        if (key == 'artist' && value.isNotEmpty) result['artist'] = value;
        if ((key == 'album' || key == 'albumtitle') && value.isNotEmpty) result['album'] = value;
        if ((key == 'year' || key == 'date') && value.isNotEmpty) result['year'] = value;
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

  // ----------------------------
  // FLAC block parser: Vorbis comment (type 4) + PICTURE (type 6)
  Map<String, dynamic> _parseFlacBlocks(Uint8List bytes) {
    final result = <String, dynamic>{};
    try {
      // bytes start with 'fLaC'
      if (bytes.length < 8) return {};
      if (!(bytes[0] == 0x66 && bytes[1] == 0x4C && bytes[2] == 0x61 && bytes[3] == 0x43)) {
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
        final len = (bytes[pos + 1] << 16) | (bytes[pos + 2] << 8) | bytes[pos + 3];
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
                final comment = _decodeString(block.sublist(off, off + clen), allowMalformed: true);
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
  Future<Map<String, dynamic>> _parseWithMediaMetadata(io.File file) async {
    final result = <String, dynamic>{};
    try {
      final metadata = await MetadataRetriever.fromFile(file);

      if (metadata.trackName != null && metadata.trackName!.isNotEmpty) result['title'] = metadata.trackName;
      if (metadata.trackArtistNames != null) {
        final artists = metadata.trackArtistNames;
        if (artists is List) result['artist'] = (artists as List).join(', ');
        else result['artist'] = artists.toString();
      }
      if (metadata.albumName != null && metadata.albumName!.isNotEmpty) result['album'] = metadata.albumName;
      if (metadata.trackNumber != null) result['track'] = metadata.trackNumber.toString();
      if (metadata.year != null) result['year'] = metadata.year.toString();
      if (metadata.genre != null && metadata.genre!.isNotEmpty) result['genre'] = metadata.genre;
      if (metadata.albumArt != null && metadata.albumArt!.isNotEmpty) result['cover'] = metadata.albumArt;
      if (metadata.mimeType != null) result['mimeType'] = metadata.mimeType;
      if (metadata.bitrate != null) result['bitrate'] = metadata.bitrate;
      if (metadata.trackDuration != null) result['trackDuration'] = metadata.trackDuration;
    } catch (e) {
      if (kDebugMode) print('flutter_media_metadata failed for ${file.path}: $e');
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
  Music createMusicFromTags(String filePath, Map<String, dynamic> tags, {String? coverDirectory}) {
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
          
          final coverFile = io.File('${dir.path}/${hash}_cover.jpg');
          if (!coverFile.existsSync()) {
            coverFile.writeAsBytesSync(coverBytes);
          }
          coverPath = coverFile.path;
          _coverCache[filePath] = coverPath; // Cache the cover path
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
    );
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
