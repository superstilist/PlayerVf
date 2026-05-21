String formatPlaybackDuration(Duration duration) {
  if (duration <= Duration.zero) return '0:00';

  final totalSeconds = duration.inSeconds;
  final hours = totalSeconds ~/ Duration.secondsPerHour;
  final minutes = (totalSeconds ~/ Duration.secondsPerMinute) % 60;
  final seconds = totalSeconds % 60;

  if (hours > 0) {
    return '$hours:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  return '$minutes:${seconds.toString().padLeft(2, '0')}';
}

String normalizePlaybackDurationText(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) return '';

  final numeric = int.tryParse(trimmed);
  if (numeric != null && numeric > 0) {
    final seconds = numeric > 10000 ? numeric ~/ 1000 : numeric;
    return formatPlaybackDuration(Duration(seconds: seconds));
  }

  final parts = trimmed.split(':');
  if (parts.length < 2 || parts.length > 3) return trimmed;

  final numbers = parts.map((part) => int.tryParse(part.trim())).toList();
  if (numbers.any((part) => part == null)) return trimmed;

  final duration = parts.length == 3
      ? Duration(
          hours: numbers[0]!,
          minutes: numbers[1]!,
          seconds: numbers[2]!,
        )
      : Duration(minutes: numbers[0]!, seconds: numbers[1]!);
  return formatPlaybackDuration(duration);
}
