import 'package:flutter/material.dart';

import '../services/responsive.dart';
import '../widgets/glass_container.dart';

class LyricsSearchParameters {
  final String title;
  final String artist;
  final String? album;
  final int? durationSeconds;

  LyricsSearchParameters({
    required this.title,
    required this.artist,
    required String album,
    required this.durationSeconds,
  }) : album = album.trim().isEmpty ? null : album;
}

class LyricsTimingShiftSheet extends StatefulWidget {
  final Future<bool> Function(Duration offset) onShift;
  final Future<bool> Function() onReset;

  const LyricsTimingShiftSheet({
    super.key,
    required this.onShift,
    required this.onReset,
  });

  @override
  State<LyricsTimingShiftSheet> createState() =>
      _LyricsTimingShiftSheetState();
}

class _LyricsTimingShiftSheetState extends State<LyricsTimingShiftSheet> {
  late final TextEditingController _controller;
  bool _isApplying = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: '500');
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Duration _customOffset(int direction) {
    final milliseconds = int.tryParse(_controller.text.trim()) ?? 0;
    return Duration(milliseconds: milliseconds.abs() * direction);
  }

  Future<void> _shift(Duration offset) async {
    if (_isApplying || offset == Duration.zero) return;
    setState(() => _isApplying = true);
    await widget.onShift(offset);
    if (mounted) setState(() => _isApplying = false);
  }

  Future<void> _reset() async {
    if (_isApplying) return;
    setState(() => _isApplying = true);
    await widget.onReset();
    if (mounted) setState(() => _isApplying = false);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    Widget presetButton({
      required IconData icon,
      required int milliseconds,
    }) {
      final isForward = milliseconds > 0;
      return FilledButton.tonalIcon(
        onPressed: _isApplying
            ? null
            : () => _shift(Duration(milliseconds: milliseconds)),
        icon: Icon(icon),
        label: Text('${isForward ? '+' : '-'}${milliseconds.abs()} ms'),
      );
    }

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: GlassContainer(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        color: theme.colorScheme.surface.withOpacity(0.96),
        blur: 8,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Shift Lyric Timing',
                      style: TextStyle(
                        fontSize: 20.sp,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Close',
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'Move every timed lyric row while playback keeps running.',
                style: TextStyle(
                  color: theme.colorScheme.onSurface.withOpacity(0.68),
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (_isApplying) ...[
                const SizedBox(height: 12),
                const LinearProgressIndicator(minHeight: 2),
              ],
              const SizedBox(height: 16),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  presetButton(
                    icon: Icons.fast_rewind_rounded,
                    milliseconds: -1000,
                  ),
                  presetButton(
                    icon: Icons.keyboard_arrow_left_rounded,
                    milliseconds: -500,
                  ),
                  presetButton(
                    icon: Icons.keyboard_arrow_right_rounded,
                    milliseconds: 500,
                  ),
                  presetButton(
                    icon: Icons.fast_forward_rounded,
                    milliseconds: 1000,
                  ),
                ],
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _controller,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Custom shift milliseconds',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.timer_rounded),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed:
                          _isApplying ? null : () => _shift(_customOffset(-1)),
                      icon: const Icon(Icons.remove_rounded),
                      label: const Text('Back'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed:
                          _isApplying ? null : () => _shift(_customOffset(1)),
                      icon: const Icon(Icons.add_rounded),
                      label: const Text('Forward'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: TextButton.icon(
                  onPressed: _isApplying ? null : _reset,
                  icon: const Icon(Icons.restore_rounded),
                  label: const Text('Reset original timing'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class LyricsSearchInputSheet extends StatefulWidget {
  final String title;
  final String artist;
  final String album;
  final int? durationSeconds;

  const LyricsSearchInputSheet({
    super.key,
    required this.title,
    required this.artist,
    required this.album,
    required this.durationSeconds,
  });

  @override
  State<LyricsSearchInputSheet> createState() =>
      _LyricsSearchInputSheetState();
}

class _LyricsSearchInputSheetState extends State<LyricsSearchInputSheet> {
  late final TextEditingController _titleController;
  late final TextEditingController _artistController;
  late final TextEditingController _albumController;
  late final TextEditingController _durationController;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.title);
    _artistController = TextEditingController(text: widget.artist);
    _albumController = TextEditingController(text: widget.album);
    _durationController = TextEditingController(
      text: widget.durationSeconds?.toString() ?? '',
    );
  }

  @override
  void dispose() {
    _titleController.dispose();
    _artistController.dispose();
    _albumController.dispose();
    _durationController.dispose();
    super.dispose();
  }

  void _submit() {
    Navigator.pop(
      context,
      LyricsSearchParameters(
        title: _titleController.text,
        artist: _artistController.text,
        album: _albumController.text,
        durationSeconds: int.tryParse(_durationController.text.trim()),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: GlassContainer(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        color: theme.colorScheme.surface.withOpacity(0.96),
        blur: 8,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Search Lyrics',
                      style: TextStyle(
                        fontSize: 20.sp,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancel'),
                  ),
                  FilledButton(
                    onPressed: _submit,
                    child: const Text('Search'),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _titleController,
                decoration: const InputDecoration(
                  labelText: 'Title',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _artistController,
                decoration: const InputDecoration(
                  labelText: 'Artist',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _albumController,
                decoration: const InputDecoration(
                  labelText: 'Album',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _durationController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Duration seconds',
                  border: OutlineInputBorder(),
                ),
                onSubmitted: (_) => _submit(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
