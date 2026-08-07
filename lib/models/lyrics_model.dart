import 'dart:math' as math;
import 'package:player_vf/utils/lyrics_parser.dart';

class LyricSyllable {
  final Duration startTime;
  final Duration endTime;
  final String text;

  const LyricSyllable({
    required this.startTime,
    required this.endTime,
    required this.text,
  });

  Duration get duration => endTime - startTime;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LyricSyllable &&
          startTime == other.startTime &&
          endTime == other.endTime &&
          text == other.text;

  @override
  int get hashCode => startTime.hashCode ^ endTime.hashCode ^ text.hashCode;
}

/// Pitch representation for karaoke/charter systems.
class LyricPitch {
  /// MIDI note number (60 = C4, 69 = A4 = 440Hz).
  final int midiNote;

  /// Duration of this pitch in the word.
  final Duration duration;

  /// Velocity (0-127), or -1 if unknown.
  final int velocity;

  /// Vibrato amount (0.0 = none, 1.0 = heavy).
  final double vibrato;

  const LyricPitch({
    required this.midiNote,
    required this.duration,
    this.velocity = -1,
    this.vibrato = 0.0,
  });

  /// Note name (e.g., "C4", "A4", "F#3").
  String get noteName {
    const names = ['C', 'C#', 'D', 'D#', 'E', 'F', 'F#', 'G', 'G#', 'A', 'A#', 'B'];
    final octave = (midiNote ~/ 12) - 1;
    final note = names[midiNote % 12];
    return '$note$octave';
  }

  /// Frequency in Hz (A4 = 440).
  double get frequency => 440.0 * math.pow(2.0, (midiNote - 69) / 12.0);

  /// Create pitch from note name (e.g., "C4", "A#3").
  static LyricPitch? fromName(String name, {required Duration duration}) {
    const names = {'C': 0, 'C#': 1, 'D': 2, 'D#': 3, 'E': 4, 'F': 5,
                   'F#': 6, 'G': 7, 'G#': 8, 'A': 9, 'A#': 10, 'B': 11};
    
    if (name.length < 2) return null;
    
    String noteName = name.substring(0, name.length - 1);
    String octaveStr = name.substring(name.length - 1);
    
    // Handle double sharps/flats
    if (noteName.endsWith('#') || noteName.endsWith('b')) {
      if (name.length < 3) return null;
      noteName = name.substring(0, name.length - 1);
      octaveStr = name.substring(name.length - 1);
    }
    
    int? octave = int.tryParse(octaveStr);
    if (octave == null) return null;
    
    int? noteValue = names[noteName];
    if (noteValue == null) return null;
    
    int midiNote = (octave + 1) * 12 + noteValue;
    return LyricPitch(midiNote: midiNote, duration: duration);
  }

  /// Create pitch from UltraStar note format.
  static LyricPitch? fromUltraStar(int noteValue, {required Duration duration}) {
    if (noteValue < 0 || noteValue > 127) return null;
    return LyricPitch(midiNote: noteValue, duration: duration);
  }

  LyricPitch copyWith({
    int? midiNote,
    Duration? duration,
    int? velocity,
    double? vibrato,
  }) {
    return LyricPitch(
      midiNote: midiNote ?? this.midiNote,
      duration: duration ?? this.duration,
      velocity: velocity ?? this.velocity,
      vibrato: vibrato ?? this.vibrato,
    );
  }

  @override
  String toString() => '$noteName($midiNote)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LyricPitch &&
          runtimeType == other.runtimeType &&
          midiNote == other.midiNote &&
          duration == other.duration;

  @override
  int get hashCode => midiNote.hashCode ^ duration.hashCode;
}

class LyricWord {
  final String text;
  final Duration startTime;
  final Duration endTime;
  final bool hasComma;
  final bool hasPeriod;
  final bool isSynthetic;
  final LyricPitch? pitch;
  final List<LyricSyllable>? syllables;

  const LyricWord({
    required this.text,
    required this.startTime,
    required this.endTime,
    this.hasComma = false,
    this.hasPeriod = false,
    this.isSynthetic = false,
    this.pitch,
    this.syllables,
  });

  Duration get duration => endTime - startTime;

  bool get hasPitch => pitch != null;
  bool get hasSyllables => syllables != null && syllables!.isNotEmpty;
  int? get midiNote => pitch?.midiNote;
  String? get noteName => pitch?.noteName;

  LyricWord copyWith({
    String? text,
    Duration? startTime,
    Duration? endTime,
    bool? hasComma,
    bool? hasPeriod,
    bool? isSynthetic,
    LyricPitch? pitch,
    List<LyricSyllable>? syllables,
  }) {
    return LyricWord(
      text: text ?? this.text,
      startTime: startTime ?? this.startTime,
      endTime: endTime ?? this.endTime,
      hasComma: hasComma ?? this.hasComma,
      hasPeriod: hasPeriod ?? this.hasPeriod,
      isSynthetic: isSynthetic ?? this.isSynthetic,
      pitch: pitch ?? this.pitch,
      syllables: syllables ?? this.syllables,
    );
  }
}

class LyricLine {
  final Duration? timestamp;
  final Duration? endTime;
  final String text;
  final String? translation;
  final List<LyricWord>? words;
  
  /// Pitch data for this line (list of pitches, one per syllable/word).
  final List<LyricPitch>? pitches;

  const LyricLine({
    required this.timestamp,
    this.endTime,
    required this.text,
    this.translation,
    this.words,
    this.pitches,
  });

  bool get hasWords => words != null && words!.isNotEmpty;

  /// Whether this line has pitch data for karaoke scoring.
  bool get hasPitches => pitches != null && pitches!.isNotEmpty;

  /// Whether any word in this line has pitch data.
  bool get hasWordPitches => words?.any((w) => w.hasPitch) ?? false;

  LyricLine copyWith({
    Duration? timestamp,
    Duration? endTime,
    String? text,
    String? translation,
    List<LyricWord>? words,
    List<LyricPitch>? pitches,
  }) {
    return LyricLine(
      timestamp: timestamp ?? this.timestamp,
      endTime: endTime ?? this.endTime,
      text: text ?? this.text,
      translation: translation ?? this.translation,
      words: words ?? this.words,
      pitches: pitches ?? this.pitches,
    );
  }
}

class LyricsDocument {
  final String rawText;
  final List<LyricLine> lines;
  final String source;

  const LyricsDocument({
    required this.rawText,
    required this.lines,
    required this.source,
  });

  bool get hasTimedLines => lines.any((line) => line.timestamp != null);

  String get plainText => lines
      .map((line) => line.text.trim())
      .where((line) => line.isNotEmpty)
      .join('\n');

  int activeIndexAt(Duration position) {
    var active = -1;
    for (var i = 0; i < lines.length; i++) {
      final timestamp = lines[i].timestamp;
      if (timestamp == null) continue;
      if (timestamp <= position) {
        active = i;
      } else {
        break;
      }
    }
    return active;
  }

  static LyricsDocument parse(String rawText, {required String source}) {
    return LyricsParser.parse(rawText, source: source);
  }

  LyricsDocument shiftedBy(Duration offset) {
    if (offset == Duration.zero || !hasTimedLines) return this;
    final shiftedRaw = shiftRawTimestamps(rawText, offset);
    return LyricsDocument.parse(shiftedRaw, source: source);
  }

  static String shiftRawTimestamps(String rawText, Duration offset) {
    // Matches both line tags [mm:ss.xx] and absolute word tags <mm:ss.xx>.
    // Relative word tags (<0.50>) are offsets from the line start and are
    // left untouched — the shifted line tag already moves them.
    final timeTagPattern = RegExp(r'(\[|<)(\d{1,2}):(\d{2})(?:[.:](\d{1,3}))?(\]|>)');
    return rawText.replaceAllMapped(timeTagPattern, (match) {
      final open = match.group(1) ?? '[';
      final close = match.group(5) ?? ']';
      final minutes = int.tryParse(match.group(2) ?? '') ?? 0;
      final seconds = int.tryParse(match.group(3) ?? '') ?? 0;
      final fraction = match.group(4) ?? '0';
      final milliseconds = fraction.length == 1
          ? int.parse(fraction) * 100
          : fraction.length == 2
              ? int.parse(fraction) * 10
              : int.parse(fraction.padRight(3, '0').substring(0, 3));
      final timestamp = Duration(
        minutes: minutes,
        seconds: seconds,
        milliseconds: milliseconds,
      );
      final shifted = timestamp + offset;
      final clamped = shifted.isNegative ? Duration.zero : shifted;
      
      final totalMilliseconds = clamped.inMilliseconds;
      final m = totalMilliseconds ~/ Duration.millisecondsPerMinute;
      final s = (totalMilliseconds ~/ Duration.millisecondsPerSecond) % 60;
      final cs = (totalMilliseconds % 1000) ~/ 10;
      return '$open${m.toString().padLeft(2, '0')}:'
          '${s.toString().padLeft(2, '0')}.'
          '${cs.toString().padLeft(2, '0')}$close';
    });
  }
}
