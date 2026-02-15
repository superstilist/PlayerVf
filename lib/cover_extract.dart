import 'dart:typed_data';
import 'dart:io' as io;

import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_media_metadata/flutter_media_metadata.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: CoverPage(),
    );
  }
}

class CoverPage extends StatefulWidget {
  const CoverPage({super.key});

  @override
  State<CoverPage> createState() => _CoverPageState();
}

class _CoverPageState extends State<CoverPage> {
  Uint8List? cover;
  String status = 'Pick MP3 file';

  Future<void> pickMp3() async {
    setState(() {
      status = 'Loading...';
      cover = null;
    });

    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['mp3'],
    );

    if (result == null || result.files.isEmpty || result.files.single.path == null) {
      setState(() => status = 'No file selected');
      return;
    }

    try {
      final path = result.files.single.path!;
      final file = io.File(path);

      // Windows: must use fromFile
      final Metadata metadata = await MetadataRetriever.fromFile(file);

      final Uint8List? albumArt = metadata.albumArt;

      if (albumArt == null || albumArt.isEmpty) {
        setState(() => status = 'No cover art found');
        return;
      }

      setState(() {
        cover = albumArt;
        status = 'Cover loaded';
      });

      // optional: save cover to disk
      try {
        final ext = _guessImageExt(albumArt);
        final out = io.File('cover_extracted.$ext');
        out.writeAsBytesSync(albumArt);
      } catch (_) {}
    } catch (e, st) {
      setState(() => status = 'Error: $e');
      // ignore: avoid_print
      print('Error extracting metadata: $e\n$st');
    }
  }

  String _guessImageExt(Uint8List bytes) {
    if (bytes.length >= 4) {
      if (bytes[0] == 0xFF && bytes[1] == 0xD8 && bytes[2] == 0xFF) return 'jpg';
      if (bytes[0] == 0x89 && bytes[1] == 0x50 && bytes[2] == 0x4E && bytes[3] == 0x47) return 'png';
      if (bytes[0] == 0x47 && bytes[1] == 0x49 && bytes[2] == 0x46) return 'gif';
    }
    return 'bin';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('MP3 Cover Art (Windows)')),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (cover != null)
              Column(
                children: [
                  Image.memory(cover!, width: 300, height: 300, fit: BoxFit.contain),
                  const SizedBox(height: 8),
                  Text(status),
                ],
              )
            else
              Text(status),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: pickMp3,
              child: const Text('Open MP3'),
            ),
          ],
        ),
      ),
    );
  }
}
