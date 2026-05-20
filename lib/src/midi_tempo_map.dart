import 'midi_event.dart';
import 'midi_file.dart';
import 'midi_smpte.dart';

/// A tempo map for converting MIDI ticks to wall-clock durations.
class MidiTempoMap {
  /// Creates a tempo map from tempo changes.
  ///
  /// Later changes at the same tick replace earlier changes at that tick.
  MidiTempoMap(Iterable<MidiTempoChange> changes)
    : changes = _normalizedChanges(changes);

  /// Builds a tempo map from a Standard MIDI File.
  ///
  /// Format 0 and format 1 files use the first track for tempo changes. Throws
  /// an [ArgumentError] for format 2 files because each track is independent.
  factory MidiTempoMap.fromFile(MidiFile file) {
    if (file.format == MidiFileFormat.independentSequences) {
      throw ArgumentError.value(
        file,
        'file',
        'Format 2 files contain independent sequences; build a tempo map '
            'from each track.',
      );
    }
    return MidiTempoMap.fromTrack(file.tracks.first);
  }

  /// Builds a tempo map from one MIDI track.
  factory MidiTempoMap.fromTrack(MidiTrack track) {
    final changes = <MidiTempoChange>[];
    for (final event in track.events) {
      final midiEvent = event.event;
      if (midiEvent is MidiMetaEvent &&
          midiEvent.microsecondsPerQuarter != null) {
        changes.add(
          MidiTempoChange(
            tick: event.tick,
            microsecondsPerQuarter: midiEvent.microsecondsPerQuarter!,
          ),
        );
      }
    }
    return MidiTempoMap(changes);
  }

  /// The default MIDI tempo of 120 BPM.
  static const int defaultMicrosecondsPerQuarter = 500000;

  /// The normalized tempo changes sorted by absolute tick.
  final List<MidiTempoChange> changes;

  /// Converts an absolute [tick] to a [Duration].
  Duration tickToDuration(int tick, MidiTimeDivision timeDivision) {
    if (tick < 0) {
      throw RangeError.range(tick, 0, null, 'tick');
    }
    return switch (timeDivision) {
      MidiTicksPerQuarter(:final ticksPerQuarter) => _ppqTickToDuration(
        tick,
        ticksPerQuarter,
      ),
      MidiSmpteTimeDivision(:final frameRate, :final ticksPerFrame) =>
        _smpteTickToDuration(tick, frameRate, ticksPerFrame),
    };
  }

  Duration _ppqTickToDuration(int tick, int ticksPerQuarter) {
    var currentTick = 0;
    var currentTempo = defaultMicrosecondsPerQuarter;
    var totalMicroseconds = 0;

    for (final change in changes) {
      if (change.tick > tick) {
        break;
      }
      final elapsedTicks = change.tick - currentTick;
      totalMicroseconds += elapsedTicks * currentTempo ~/ ticksPerQuarter;
      currentTick = change.tick;
      currentTempo = change.microsecondsPerQuarter;
    }

    totalMicroseconds += (tick - currentTick) * currentTempo ~/ ticksPerQuarter;
    return Duration(microseconds: totalMicroseconds);
  }

  Duration _smpteTickToDuration(
    int tick,
    MidiSmpteFrameRate frameRate,
    int ticksPerFrame,
  ) {
    return Duration(
      microseconds:
          tick *
          frameRate.actualFramesPerSecondDenominator *
          Duration.microsecondsPerSecond ~/
          (frameRate.actualFramesPerSecondNumerator * ticksPerFrame),
    );
  }
}

/// A tempo change at an absolute MIDI tick.
class MidiTempoChange {
  /// Creates a tempo change.
  ///
  /// The [microsecondsPerQuarter] value must be positive.
  MidiTempoChange({required this.tick, required this.microsecondsPerQuarter}) {
    if (tick < 0) {
      throw RangeError.range(tick, 0, null, 'tick');
    }
    if (microsecondsPerQuarter <= 0) {
      throw RangeError.range(
        microsecondsPerQuarter,
        1,
        null,
        'microsecondsPerQuarter',
      );
    }
  }

  /// The absolute tick where the tempo takes effect.
  final int tick;

  /// The number of microseconds per quarter note.
  final int microsecondsPerQuarter;

  @override
  bool operator ==(Object other) {
    return other is MidiTempoChange &&
        other.tick == tick &&
        other.microsecondsPerQuarter == microsecondsPerQuarter;
  }

  @override
  int get hashCode => Object.hash(tick, microsecondsPerQuarter);
}

List<MidiTempoChange> _normalizedChanges(Iterable<MidiTempoChange> changes) {
  final indexedChanges = <({int index, MidiTempoChange change})>[
    for (final indexed in changes.indexed)
      (index: indexed.$1, change: indexed.$2),
  ];
  indexedChanges.sort((left, right) {
    final tickComparison = left.change.tick.compareTo(right.change.tick);
    if (tickComparison != 0) {
      return tickComparison;
    }
    return left.index.compareTo(right.index);
  });

  final normalized = <MidiTempoChange>[];
  for (final indexed in indexedChanges) {
    final change = indexed.change;
    if (normalized.isNotEmpty && normalized.last.tick == change.tick) {
      normalized[normalized.length - 1] = change;
    } else {
      normalized.add(change);
    }
  }
  return List<MidiTempoChange>.unmodifiable(normalized);
}
