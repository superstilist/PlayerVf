import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

Future<String?> pickDirectorySafely(BuildContext context) async {
  if (Platform.isLinux) {
    return showDialog<String>(
      context: context,
      builder: (context) => const _LinuxFileBrowserDialog(
        mode: _LinuxPickerMode.directory,
      ),
    );
  }

  try {
    return await FilePicker.platform.getDirectoryPath();
  } catch (error) {
    if (!context.mounted) return null;
    _showPickerError(context, error);
    return null;
  }
}

Future<String?> pickFilePathSafely(
  BuildContext context, {
  List<String>? allowedExtensions,
}) async {
  if (Platform.isLinux) {
    return showDialog<String>(
      context: context,
      builder: (context) => _LinuxFileBrowserDialog(
        mode: _LinuxPickerMode.file,
        allowedExtensions: allowedExtensions,
      ),
    );
  }

  try {
    final result = await FilePicker.platform.pickFiles(
      type: allowedExtensions == null ? FileType.any : FileType.custom,
      allowedExtensions: allowedExtensions,
      withData: false,
    );
    return result?.files.single.path;
  } catch (error) {
    if (!context.mounted) return null;
    _showPickerError(context, error);
    return null;
  }
}

enum _LinuxPickerMode { directory, file }

class _LinuxFileBrowserDialog extends StatefulWidget {
  final _LinuxPickerMode mode;
  final List<String>? allowedExtensions;

  const _LinuxFileBrowserDialog({
    required this.mode,
    this.allowedExtensions,
  });

  @override
  State<_LinuxFileBrowserDialog> createState() =>
      _LinuxFileBrowserDialogState();
}

class _LinuxFileBrowserDialogState extends State<_LinuxFileBrowserDialog> {
  late Directory _currentDirectory;
  late final TextEditingController _pathController;
  final TextEditingController _nameController = TextEditingController();
  List<_BrowserEntry> _entries = const [];
  String? _selectedPath;
  String? _error;

  bool get _selectingDirectory => widget.mode == _LinuxPickerMode.directory;

  Set<String>? get _allowedExtensions {
    return widget.allowedExtensions
        ?.map((extension) => extension.toLowerCase().replaceFirst('.', ''))
        .toSet();
  }

  @override
  void initState() {
    super.initState();
    _currentDirectory = Directory(_initialDirectory());
    _pathController = TextEditingController(text: _currentDirectory.path);
    _loadEntries();
  }

  @override
  void dispose() {
    _pathController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final title = _selectingDirectory ? 'Select Folder' : 'Select File';
    return AlertDialog(
      title: Text(title),
      contentPadding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
      content: SizedBox(
        width: 760,
        height: 520,
        child: Column(
          children: [
            _buildPathBar(),
            const SizedBox(height: 10),
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildShortcuts(),
                  const SizedBox(width: 12),
                  Expanded(child: _buildEntryList()),
                ],
              ),
            ),
            const SizedBox(height: 10),
            _buildSelectionBar(),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _canSelect ? _selectCurrentChoice : null,
          child: Text(_selectingDirectory ? 'Select Folder' : 'Open'),
        ),
      ],
    );
  }

  Widget _buildPathBar() {
    return Row(
      children: [
        IconButton(
          tooltip: 'Up',
          onPressed: _currentDirectory.parent.path == _currentDirectory.path
              ? null
              : () => _openDirectory(_currentDirectory.parent.path),
          icon: const Icon(Icons.arrow_upward_rounded),
        ),
        Expanded(
          child: TextField(
            controller: _pathController,
            decoration: InputDecoration(
              isDense: true,
              prefixIcon: const Icon(Icons.folder_open_rounded),
              border: const OutlineInputBorder(),
              errorText: _error,
            ),
            onSubmitted: _openDirectory,
          ),
        ),
        const SizedBox(width: 8),
        IconButton(
          tooltip: 'Go',
          onPressed: () => _openDirectory(_pathController.text.trim()),
          icon: const Icon(Icons.arrow_forward_rounded),
        ),
      ],
    );
  }

  Widget _buildShortcuts() {
    final shortcuts = _shortcutDirectories();
    return SizedBox(
      width: 170,
      child: ListView(
        children: [
          for (final shortcut in shortcuts)
            ListTile(
              dense: true,
              leading: Icon(shortcut.icon),
              title: Text(
                shortcut.label,
                overflow: TextOverflow.ellipsis,
              ),
              onTap: () => _openDirectory(shortcut.path),
            ),
        ],
      ),
    );
  }

  Widget _buildEntryList() {
    if (_entries.isEmpty) {
      return const Center(child: Text('No matching files or folders.'));
    }

    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).dividerColor),
        borderRadius: BorderRadius.circular(8),
      ),
      child: ListView.builder(
        itemCount: _entries.length,
        itemBuilder: (context, index) {
          final entry = _entries[index];
          final selected = entry.path == _selectedPath;
          return GestureDetector(
            onDoubleTap: () => _activateEntry(entry),
            child: ListTile(
              dense: true,
              selected: selected,
              leading: Icon(
                entry.isDirectory
                    ? Icons.folder_rounded
                    : Icons.insert_drive_file_rounded,
              ),
              title: Text(
                entry.name,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle:
                  entry.isDirectory ? null : Text(_fileSubtitle(entry.path)),
              onTap: () => _selectEntry(entry),
            ),
          );
        },
      ),
    );
  }

  Widget _buildSelectionBar() {
    final label = _selectingDirectory ? 'Folder' : 'File';
    return Row(
      children: [
        SizedBox(width: 68, child: Text(label)),
        Expanded(
          child: TextField(
            controller: _nameController,
            readOnly: true,
            decoration: const InputDecoration(
              isDense: true,
              border: OutlineInputBorder(),
            ),
          ),
        ),
      ],
    );
  }

  bool get _canSelect {
    if (_selectingDirectory) {
      return Directory(_selectedPath ?? _currentDirectory.path).existsSync();
    }
    final selected = _selectedPath;
    return selected != null &&
        File(selected).existsSync() &&
        _isAllowedFile(selected);
  }

  void _selectCurrentChoice() {
    final selected = _selectingDirectory
        ? _selectedPath ?? _currentDirectory.path
        : _selectedPath;
    if (selected == null) return;
    Navigator.of(context).pop(selected);
  }

  void _selectEntry(_BrowserEntry entry) {
    setState(() {
      _selectedPath = entry.path;
      _nameController.text = entry.name;
    });
  }

  void _activateEntry(_BrowserEntry entry) {
    if (entry.isDirectory) {
      _openDirectory(entry.path);
      return;
    }
    if (_isAllowedFile(entry.path)) {
      Navigator.of(context).pop(entry.path);
    }
  }

  void _openDirectory(String path) {
    final normalized = p.normalize(path);
    final directory = Directory(normalized);
    if (!directory.existsSync()) {
      setState(() => _error = 'Folder does not exist.');
      return;
    }

    setState(() {
      _currentDirectory = directory;
      _pathController.text = directory.path;
      _selectedPath = _selectingDirectory ? directory.path : null;
      _nameController.text =
          _selectingDirectory ? p.basename(directory.path) : '';
      _error = null;
    });
    _loadEntries();
  }

  void _loadEntries() {
    final entries = <_BrowserEntry>[];
    try {
      for (final entity in _currentDirectory.listSync(followLinks: false)) {
        final stat = entity.statSync();
        final isDirectory = stat.type == FileSystemEntityType.directory;
        if (!isDirectory && !_isAllowedFile(entity.path)) continue;
        entries.add(_BrowserEntry(
          path: entity.path,
          name: p.basename(entity.path),
          isDirectory: isDirectory,
        ));
      }
    } catch (error) {
      setState(() {
        _entries = const [];
        _error = error.toString();
      });
      return;
    }

    entries.sort((a, b) {
      if (a.isDirectory != b.isDirectory) return a.isDirectory ? -1 : 1;
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });

    setState(() => _entries = entries);
  }

  bool _isAllowedFile(String path) {
    final allowed = _allowedExtensions;
    if (allowed == null || allowed.isEmpty) return true;
    final extension = p.extension(path).toLowerCase().replaceFirst('.', '');
    return allowed.contains(extension);
  }

  String _fileSubtitle(String path) {
    try {
      final bytes = File(path).lengthSync();
      if (bytes < 1024) return '$bytes B';
      if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    } catch (_) {
      return '';
    }
  }

  String _initialDirectory() {
    final home = Platform.environment['HOME'];
    if (home != null && Directory(home).existsSync()) return home;
    return Directory.current.path;
  }

  List<_ShortcutDirectory> _shortcutDirectories() {
    final shortcuts = <_ShortcutDirectory>[
      const _ShortcutDirectory('Root', '/', Icons.storage_rounded),
    ];

    final home = Platform.environment['HOME'];
    if (home != null && Directory(home).existsSync()) {
      shortcuts.add(_ShortcutDirectory('Home', home, Icons.home_rounded));
      for (final name in const ['Desktop', 'Downloads', 'Music', 'Videos']) {
        final path = p.join(home, name);
        if (Directory(path).existsSync()) {
          shortcuts.add(_ShortcutDirectory(name, path, Icons.folder_rounded));
        }
      }
    }

    for (final path in const ['/mnt', '/media', '/run/media']) {
      if (Directory(path).existsSync()) {
        shortcuts.add(_ShortcutDirectory(path, path, Icons.devices_rounded));
      }
    }

    return shortcuts;
  }
}

class _BrowserEntry {
  final String path;
  final String name;
  final bool isDirectory;

  const _BrowserEntry({
    required this.path,
    required this.name,
    required this.isDirectory,
  });
}

class _ShortcutDirectory {
  final String label;
  final String path;
  final IconData icon;

  const _ShortcutDirectory(this.label, this.path, this.icon);
}

void _showPickerError(BuildContext context, Object error) {
  if (!context.mounted) return;
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text('Could not open the file picker: $error'),
        behavior: SnackBarBehavior.floating,
      ),
    );
}
