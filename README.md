# midi_kit_file

Pure Dart models and byte readers/writers for Standard MIDI Files.

## Features

- Standard MIDI File format 0, 1, and 2 headers.
- PPQ and SMPTE time division models.
- Multi-track event storage with absolute ticks.
- Channel voice, meta, and SysEx event models.
- Unknown chunk and unknown meta event preservation.
- Tempo map conversion from ticks to `Duration`.

## Usage

```dart
final file = MidiFile.fromBytes(bytes);
final tempoMap = MidiTempoMap.fromFile(file);

for (final track in file.tracks) {
  for (final event in track.events) {
    final position = tempoMap.tickToDuration(event.tick, file.timeDivision);
    print('$position ${event.event}');
  }
}

final encoded = file.toBytes();
```

The model stores track event timing as absolute ticks. The writer converts
absolute ticks back to Standard MIDI File delta times.
