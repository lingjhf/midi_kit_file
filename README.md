# midi_kit_file

Pure Dart models, readers, writers, and timing utilities for Standard MIDI
Files.

`midi_kit_file` focuses on the Standard MIDI File container and event model. It
does not synthesize audio, play MIDI, load sound fonts, or manage files on disk.

## Features

- Standard MIDI File format 0, 1, and 2.
- `MThd` and `MTrk` parsing/writing.
- Unknown chunk preservation, including original chunk order.
- PPQ and SMPTE time divisions, including 29.97 drop-frame time code.
- Absolute tick event storage with delta-time encoding on write.
- Channel voice messages from `0x80` through `0xef`.
- Running status parsing.
- Meta events, unknown meta event preservation, and strict fixed-length
  validation for standard meta events.
- SysEx events using `0xf0` and `0xf7`.
- Tempo maps that convert ticks to `Duration`.

## Scope

This package targets Standard MIDI File 1.0 style byte streams:

- Header chunks with format `0`, `1`, or `2`.
- Track chunks containing `<delta-time><event>` records.
- Channel voice, SysEx, and meta events.
- Text meta event types `0x01` through `0x0f`.
- Sequence number, MIDI channel prefix, MIDI port, end-of-track, set tempo,
  SMPTE offset, time signature, key signature, and sequencer-specific meta
  events.

Out of scope:

- MIDI 2.0 Clip File / UMP containers.
- Audio rendering or playback.
- SoundFont loading.
- Semantic decoding of manufacturer-specific SysEx or sequencer-specific data.

## Reading A File

```dart
import 'dart:io';

import 'package:midi_kit_file/midi_kit_file.dart';

Future<void> main() async {
  final bytes = await File('song.mid').readAsBytes();
  final file = MidiFile.fromBytes(bytes);

  print(file.format);
  print(file.timeDivision);
  print('tracks: ${file.tracks.length}');

  final tempoMap = MidiTempoMap.fromFile(file);

  for (final track in file.tracks) {
    print(track.effectiveName ?? 'Untitled track');

    for (final trackEvent in track.events) {
      final position = tempoMap.tickToDuration(
        trackEvent.tick,
        file.timeDivision,
      );
      print('$position ${trackEvent.event}');
    }
  }
}
```

`MidiFile.fromBytes` throws `FormatException` for invalid Standard MIDI File
data.

## Writing A File

```dart
import 'dart:io';

import 'package:midi_kit_file/midi_kit_file.dart';

Future<void> main() async {
  final file = MidiFile(
    format: MidiFileFormat.singleTrack,
    timeDivision: MidiTicksPerQuarter(480),
    tracks: <MidiTrack>[
      MidiTrack(
        name: 'Lead',
        events: <MidiTrackEvent>[
          MidiTrackEvent(
            tick: 0,
            event: MidiMetaEvent.setTempo(500000),
          ),
          MidiTrackEvent(
            tick: 0,
            event: MidiChannelEvent(
              MidiChannelMessage.programChange(channel: 0, program: 0),
            ),
          ),
          MidiTrackEvent(
            tick: 0,
            event: MidiChannelEvent(
              MidiChannelMessage.noteOn(
                channel: 0,
                note: 60,
                velocity: 96,
              ),
            ),
          ),
          MidiTrackEvent(
            tick: 480,
            event: MidiChannelEvent(
              MidiChannelMessage.noteOff(channel: 0, note: 60),
            ),
          ),
        ],
      ),
    ],
  );

  await File('lead.mid').writeAsBytes(file.toBytes());
}
```

The writer sorts track events by absolute tick, preserves same-tick insertion
order, writes delta-times, and adds an end-of-track event when a track does not
already contain one.

## Event Model

Track event times are stored as absolute ticks:

```dart
final event = MidiTrackEvent(
  tick: 960,
  event: MidiChannelEvent(
    MidiChannelMessage.noteOn(channel: 0, note: 64, velocity: 100),
  ),
);
```

Channel helpers are available for the Standard MIDI channel voice messages:

```dart
MidiChannelMessage.noteOff(channel: 0, note: 60);
MidiChannelMessage.noteOn(channel: 0, note: 60, velocity: 90);
MidiChannelMessage.polyphonicKeyPressure(
  channel: 0,
  note: 60,
  pressure: 70,
);
MidiChannelMessage.controlChange(channel: 0, controller: 64, value: 127);
MidiChannelMessage.programChange(channel: 0, program: 4);
MidiChannelMessage.channelPressure(channel: 0, pressure: 80);
MidiChannelMessage.pitchBend(channel: 0, value: 0x2000);
```

Meta event helpers expose typed views where useful:

```dart
final tempo = MidiMetaEvent.setTempo(500000);
print(tempo.microsecondsPerQuarter);

final signature = MidiMetaEvent.timeSignature(
  numerator: 6,
  denominator: 8,
  clocksPerMetronomeClick: 36,
);
print(signature.timeSignature?.denominator);

final key = MidiMetaEvent.keySignature(sharpsFlats: -3, isMinor: true);
print(key.keySignature);
```

Unknown meta events are preserved as `MidiMetaEvent(type: ..., data: ...)`.

## Tempo Maps

For format 0 and format 1 files, `MidiTempoMap.fromFile` reads tempo changes
from the first track. This follows the Standard MIDI File convention that format
1 tempo maps live in the first `MTrk`.

```dart
final tempoMap = MidiTempoMap.fromFile(file);
final position = tempoMap.tickToDuration(960, file.timeDivision);
```

For format 2 files, each track is an independent sequence. Build a tempo map per
track:

```dart
for (final track in file.tracks) {
  final tempoMap = MidiTempoMap.fromTrack(track);
  // Use this tempo map only with events from this track.
}
```

When a file has no tempo events, the default tempo is 120 BPM
(`500000` microseconds per quarter note).

## Unknown Chunks

Unknown chunks are retained and can be written back:

```dart
final file = MidiFile.withChunks(
  format: MidiFileFormat.singleTrack,
  timeDivision: MidiTicksPerQuarter(480),
  chunks: <MidiFileChunk>[
    MidiUnknownChunk(type: 'Xtra', data: <int>[1, 2, 3]),
    MidiTrackChunk(MidiTrack(events: <MidiTrackEvent>[])),
  ],
);
```

`MThd` and `MTrk` are Standard MIDI File chunk types and cannot be used as
`MidiUnknownChunk.type`.

## Validation

Parsing invalid bytes throws `FormatException`.

Building invalid model objects throws `ArgumentError` or `RangeError`, depending
on whether the error is structural or range-based. Examples include:

- Format 0 with more than one track.
- Meta event type outside `0x00..0x7f`.
- End-of-track meta events with non-empty data.
- Time signature meta events with a zero numerator.
- Key signature values outside seven flats through seven sharps.
- SMPTE division frame rates other than `-24`, `-25`, `-29`, and `-30`.

## Development

Run the standard checks:

```sh
dart analyze
dart test
dart run coverage:test_with_coverage
```

The current unit test suite covers all package library lines.
