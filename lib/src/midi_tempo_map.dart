import 'midi_event.dart';
import 'midi_file.dart';
import 'midi_smpte.dart';

class MidiTempoMap {
  MidiTempoMap(Iterable<MidiTempoChange> changes)
    : changes = _normalizedChanges(changes);

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

  static const int defaultMicrosecondsPerQuarter = 500000;

  final List<MidiTempoChange> changes;

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

class MidiTempoChange {
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

  final int tick;
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
