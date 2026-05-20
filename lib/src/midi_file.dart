import 'dart:collection';
import 'dart:convert';
import 'dart:typed_data';

import 'midi_channel_message.dart';
import 'midi_event.dart';
import 'midi_smpte.dart';

enum MidiFileFormat {
  singleTrack(0),
  simultaneousTracks(1),
  independentSequences(2);

  const MidiFileFormat(this.value);

  final int value;

  static MidiFileFormat fromValue(int value) {
    for (final format in MidiFileFormat.values) {
      if (format.value == value) {
        return format;
      }
    }
    throw FormatException('Unsupported Standard MIDI File format: $value.');
  }
}

sealed class MidiTimeDivision {
  const MidiTimeDivision();
}

class MidiTicksPerQuarter extends MidiTimeDivision {
  MidiTicksPerQuarter(this.ticksPerQuarter) {
    if (ticksPerQuarter <= 0 || ticksPerQuarter > 0x7fff) {
      throw RangeError.range(ticksPerQuarter, 1, 0x7fff, 'ticksPerQuarter');
    }
  }

  final int ticksPerQuarter;

  @override
  bool operator ==(Object other) {
    return other is MidiTicksPerQuarter &&
        other.ticksPerQuarter == ticksPerQuarter;
  }

  @override
  int get hashCode => ticksPerQuarter.hashCode;

  @override
  String toString() => 'MidiTicksPerQuarter($ticksPerQuarter)';
}

class MidiSmpteTimeDivision extends MidiTimeDivision {
  MidiSmpteTimeDivision({
    required this.frameRate,
    required this.ticksPerFrame,
  }) {
    if (ticksPerFrame <= 0 || ticksPerFrame > 0xff) {
      throw RangeError.range(ticksPerFrame, 1, 0xff, 'ticksPerFrame');
    }
  }

  final MidiSmpteFrameRate frameRate;
  final int ticksPerFrame;

  int get framesPerSecond => frameRate.nominalFramesPerSecond;

  @override
  bool operator ==(Object other) {
    return other is MidiSmpteTimeDivision &&
        other.frameRate == frameRate &&
        other.ticksPerFrame == ticksPerFrame;
  }

  @override
  int get hashCode => Object.hash(frameRate, ticksPerFrame);

  @override
  String toString() {
    return 'MidiSmpteTimeDivision(frameRate: ${frameRate.name}, '
        'ticksPerFrame: $ticksPerFrame)';
  }
}

class MidiFile {
  factory MidiFile({
    required MidiFileFormat format,
    required MidiTimeDivision timeDivision,
    required List<MidiTrack> tracks,
    List<MidiUnknownChunk> unknownChunks = const <MidiUnknownChunk>[],
  }) {
    return MidiFile.withChunks(
      format: format,
      timeDivision: timeDivision,
      chunks: <MidiFileChunk>[
        for (final track in tracks) MidiTrackChunk(track),
        ...unknownChunks,
      ],
    );
  }

  MidiFile.withChunks({
    required this.format,
    required this.timeDivision,
    required List<MidiFileChunk> chunks,
  }) : chunks = UnmodifiableListView<MidiFileChunk>(
         List<MidiFileChunk>.of(chunks),
       ),
       tracks = UnmodifiableListView<MidiTrack>(
         chunks.whereType<MidiTrackChunk>().map((chunk) => chunk.track),
       ),
       unknownChunks = UnmodifiableListView<MidiUnknownChunk>(
         chunks.whereType<MidiUnknownChunk>(),
       ) {
    if (tracks.isEmpty) {
      throw ArgumentError.value(
        tracks,
        'tracks',
        'At least one track is required.',
      );
    }
    if (format == MidiFileFormat.singleTrack && tracks.length != 1) {
      throw ArgumentError.value(
        tracks,
        'tracks',
        'Format 0 Standard MIDI Files must contain exactly one track.',
      );
    }
  }

  factory MidiFile.fromBytes(Uint8List bytes) {
    return _StandardMidiFileReader(bytes).read();
  }

  final MidiFileFormat format;
  final MidiTimeDivision timeDivision;
  final UnmodifiableListView<MidiFileChunk> chunks;
  final UnmodifiableListView<MidiTrack> tracks;
  final UnmodifiableListView<MidiUnknownChunk> unknownChunks;

  Uint8List toBytes() {
    return _StandardMidiFileWriter(this).write();
  }

  @override
  bool operator ==(Object other) {
    return other is MidiFile &&
        other.format == format &&
        other.timeDivision == timeDivision &&
        _listEquals(other.chunks, chunks);
  }

  @override
  int get hashCode {
    return Object.hash(format, timeDivision, Object.hashAll(chunks));
  }
}

sealed class MidiFileChunk {
  const MidiFileChunk();
}

class MidiTrackChunk extends MidiFileChunk {
  const MidiTrackChunk(this.track);

  final MidiTrack track;

  @override
  bool operator ==(Object other) {
    return other is MidiTrackChunk && other.track == track;
  }

  @override
  int get hashCode => track.hashCode;
}

class MidiTrack {
  MidiTrack({required List<MidiTrackEvent> events, this.name})
    : events = UnmodifiableListView<MidiTrackEvent>(
        List<MidiTrackEvent>.of(events),
      ) {
    if (this.events.any(
          (event) =>
              event.event is MidiMetaEvent &&
              (event.event as MidiMetaEvent).isEndOfTrack,
        ) &&
        this.events
                .where(
                  (event) =>
                      event.event is MidiMetaEvent &&
                      (event.event as MidiMetaEvent).isEndOfTrack,
                )
                .length >
            1) {
      throw ArgumentError.value(
        events,
        'events',
        'A MIDI track must not contain more than one end-of-track event.',
      );
    }
  }

  final UnmodifiableListView<MidiTrackEvent> events;
  final String? name;

  String? get effectiveName {
    for (final event in events) {
      final midiEvent = event.event;
      if (midiEvent is MidiMetaEvent && midiEvent.trackName != null) {
        return midiEvent.trackName;
      }
    }
    return name;
  }

  @override
  bool operator ==(Object other) {
    return other is MidiTrack &&
        other.name == name &&
        _listEquals(other.events, events);
  }

  @override
  int get hashCode => Object.hash(name, Object.hashAll(events));
}

class MidiTrackEvent {
  MidiTrackEvent({required this.tick, required this.event}) {
    if (tick < 0) {
      throw RangeError.range(tick, 0, null, 'tick');
    }
  }

  final int tick;
  final MidiEvent event;

  @override
  bool operator ==(Object other) {
    return other is MidiTrackEvent &&
        other.tick == tick &&
        other.event == event;
  }

  @override
  int get hashCode => Object.hash(tick, event);

  @override
  String toString() => 'MidiTrackEvent(tick: $tick, event: $event)';
}

class MidiUnknownChunk extends MidiFileChunk {
  MidiUnknownChunk({required this.type, required Iterable<int> data})
    : data = UnmodifiableListView<int>(_validatedBytes(data, 'chunk data')) {
    _validateChunkType(type);
  }

  final String type;
  final UnmodifiableListView<int> data;

  @override
  bool operator ==(Object other) {
    return other is MidiUnknownChunk &&
        other.type == type &&
        _listEquals(other.data, data);
  }

  @override
  int get hashCode => Object.hash(type, Object.hashAll(data));
}

class _StandardMidiFileReader {
  _StandardMidiFileReader(Uint8List bytes) : _reader = _ByteReader(bytes);

  final _ByteReader _reader;

  MidiFile read() {
    try {
      return _read();
    } on ArgumentError catch (error) {
      throw FormatException(error.toString());
    }
  }

  MidiFile _read() {
    final headerType = _reader.readAscii(4);
    if (headerType != 'MThd') {
      throw const FormatException('Standard MIDI File must start with MThd.');
    }
    final headerLength = _reader.readUint32();
    if (headerLength < 6) {
      throw FormatException('MThd length must be at least 6: $headerLength.');
    }

    final format = MidiFileFormat.fromValue(_reader.readUint16());
    final expectedTrackCount = _reader.readUint16();
    final timeDivision = _readTimeDivision(_reader.readUint16());
    if (headerLength > 6) {
      _reader.readBytes(headerLength - 6);
    }
    if (expectedTrackCount <= 0) {
      throw const FormatException('Standard MIDI File must contain tracks.');
    }

    final tracks = <MidiTrack>[];
    final chunks = <MidiFileChunk>[];
    while (!_reader.isDone) {
      final chunkType = _reader.readAscii(4);
      final chunkLength = _reader.readUint32();
      final chunkData = _reader.readBytes(chunkLength);
      if (chunkType == 'MTrk') {
        if (tracks.length == expectedTrackCount) {
          throw const FormatException(
            'Standard MIDI File contains too many tracks.',
          );
        }
        final track = _readTrack(chunkData);
        tracks.add(track);
        chunks.add(MidiTrackChunk(track));
      } else {
        chunks.add(MidiUnknownChunk(type: chunkType, data: chunkData));
      }
    }

    if (tracks.length != expectedTrackCount) {
      throw FormatException(
        'Expected $expectedTrackCount MIDI tracks, found ${tracks.length}.',
      );
    }

    return MidiFile.withChunks(
      format: format,
      timeDivision: timeDivision,
      chunks: chunks,
    );
  }

  MidiTimeDivision _readTimeDivision(int division) {
    if ((division & 0x8000) == 0) {
      return MidiTicksPerQuarter(division);
    }
    final smpteByte = (division >> 8) & 0xff;
    final signedSmpte = smpteByte >= 0x80 ? smpteByte - 0x100 : smpteByte;
    return MidiSmpteTimeDivision(
      frameRate: MidiSmpteFrameRate.fromSignedDivisionByte(signedSmpte),
      ticksPerFrame: division & 0xff,
    );
  }

  MidiTrack _readTrack(Uint8List data) {
    final reader = _ByteReader(data);
    final events = <MidiTrackEvent>[];
    var tick = 0;
    int? runningStatus;
    var sawEndOfTrack = false;
    String? trackName;

    while (!reader.isDone) {
      if (sawEndOfTrack) {
        throw const FormatException(
          'Track data found after end-of-track event.',
        );
      }
      tick += reader.readVariableLengthQuantity();
      final first = reader.readUint8();
      if (first < 0x80) {
        final status = runningStatus;
        if (status == null) {
          throw const FormatException(
            'Running status used before a status byte.',
          );
        }
        events.add(
          MidiTrackEvent(
            tick: tick,
            event: MidiChannelEvent(
              _readChannelMessage(reader, status, firstDataByte: first),
            ),
          ),
        );
        continue;
      }

      if (first >= 0x80 && first <= 0xef) {
        runningStatus = first;
        events.add(
          MidiTrackEvent(
            tick: tick,
            event: MidiChannelEvent(_readChannelMessage(reader, first)),
          ),
        );
        continue;
      }

      runningStatus = null;
      if (first == 0xff) {
        final type = reader.readUint8();
        final length = reader.readVariableLengthQuantity();
        final metaData = reader.readBytes(length);
        final metaEvent = MidiMetaEvent.fromFileData(
          type: type,
          data: metaData,
        );
        if (metaEvent.trackName != null && trackName == null) {
          trackName = metaEvent.trackName;
        }
        if (metaEvent.isEndOfTrack) {
          sawEndOfTrack = true;
        }
        events.add(MidiTrackEvent(tick: tick, event: metaEvent));
        continue;
      }

      if (first == 0xf0 || first == 0xf7) {
        final length = reader.readVariableLengthQuantity();
        events.add(
          MidiTrackEvent(
            tick: tick,
            event: MidiSysExEvent(
              status: first,
              data: reader.readBytes(length),
            ),
          ),
        );
        continue;
      }

      throw FormatException(
        'Unsupported system event status in Standard MIDI File: $first.',
      );
    }

    if (!sawEndOfTrack) {
      throw const FormatException('MIDI track is missing end-of-track event.');
    }
    return MidiTrack(events: events, name: trackName);
  }

  MidiChannelMessage _readChannelMessage(
    _ByteReader reader,
    int status, {
    int? firstDataByte,
  }) {
    final type = MidiChannelMessage.typeForStatus(status);
    final data = <int>[];
    if (firstDataByte != null) {
      data.add(firstDataByte);
    }
    while (data.length < type.dataLength) {
      data.add(reader.readUint8());
    }
    return MidiChannelMessage.fromBytes(<int>[status, ...data]);
  }
}

class _StandardMidiFileWriter {
  _StandardMidiFileWriter(this.file);

  final MidiFile file;

  Uint8List write() {
    final writer = _ByteWriter();
    writer.writeAscii('MThd');
    writer.writeUint32(6);
    writer.writeUint16(file.format.value);
    writer.writeUint16(file.tracks.length);
    writer.writeUint16(_timeDivisionValue(file.timeDivision));
    for (final chunk in file.chunks) {
      switch (chunk) {
        case MidiTrackChunk(:final track):
          _writeTrack(writer, track);
        case MidiUnknownChunk(:final type, :final data):
          writer.writeAscii(type);
          writer.writeUint32(data.length);
          writer.writeBytes(data);
      }
    }
    return Uint8List.fromList(writer.bytes);
  }

  int _timeDivisionValue(MidiTimeDivision timeDivision) {
    return switch (timeDivision) {
      MidiTicksPerQuarter(:final ticksPerQuarter) => ticksPerQuarter,
      MidiSmpteTimeDivision(:final frameRate, :final ticksPerFrame) =>
        ((frameRate.signedDivisionByte & 0xff) << 8) | ticksPerFrame,
    };
  }

  void _writeTrack(_ByteWriter fileWriter, MidiTrack track) {
    final trackWriter = _ByteWriter();
    var lastTick = 0;
    for (final event in _orderedTrackEvents(track)) {
      final delta = event.tick - lastTick;
      trackWriter.writeVariableLengthQuantity(delta);
      _writeEvent(trackWriter, event.event);
      lastTick = event.tick;
    }
    fileWriter.writeAscii('MTrk');
    fileWriter.writeUint32(trackWriter.length);
    fileWriter.writeBytes(trackWriter.bytes);
  }

  List<MidiTrackEvent> _orderedTrackEvents(MidiTrack track) {
    final events = <MidiTrackEvent>[
      if (track.name != null && !_hasTrackNameEvent(track))
        MidiTrackEvent(tick: 0, event: MidiMetaEvent.trackName(track.name!)),
      ...track.events,
    ];
    final hasEndOfTrack = events.any(
      (event) =>
          event.event is MidiMetaEvent &&
          (event.event as MidiMetaEvent).isEndOfTrack,
    );
    if (!hasEndOfTrack) {
      final lastTick = events.fold<int>(
        0,
        (maxTick, event) => event.tick > maxTick ? event.tick : maxTick,
      );
      events.add(
        MidiTrackEvent(tick: lastTick, event: MidiMetaEvent.endOfTrack()),
      );
    }

    final indexedEvents = <({int index, MidiTrackEvent event})>[
      for (final indexed in events.indexed)
        (index: indexed.$1, event: indexed.$2),
    ];
    indexedEvents.sort((left, right) {
      final tickComparison = left.event.tick.compareTo(right.event.tick);
      if (tickComparison != 0) {
        return tickComparison;
      }
      return left.index.compareTo(right.index);
    });
    return <MidiTrackEvent>[for (final indexed in indexedEvents) indexed.event];
  }

  bool _hasTrackNameEvent(MidiTrack track) {
    return track.events.any(
      (event) =>
          event.event is MidiMetaEvent &&
          (event.event as MidiMetaEvent).type == MidiMetaEvent.trackNameType,
    );
  }

  void _writeEvent(_ByteWriter writer, MidiEvent event) {
    switch (event) {
      case MidiChannelEvent(:final message):
        writer.writeBytes(message.toBytes());
      case MidiMetaEvent(:final type, :final data):
        writer.writeByte(0xff);
        writer.writeByte(type);
        writer.writeVariableLengthQuantity(data.length);
        writer.writeBytes(data);
      case MidiSysExEvent(:final status, :final data):
        writer.writeByte(status);
        writer.writeVariableLengthQuantity(data.length);
        writer.writeBytes(data);
    }
  }
}

class _ByteReader {
  _ByteReader(this.bytes);

  final Uint8List bytes;
  int _offset = 0;

  bool get isDone => _offset == bytes.length;

  int readUint8() {
    _ensureAvailable(1);
    return bytes[_offset++];
  }

  int readUint16() {
    _ensureAvailable(2);
    final value = (bytes[_offset] << 8) | bytes[_offset + 1];
    _offset += 2;
    return value;
  }

  int readUint32() {
    _ensureAvailable(4);
    final value =
        (bytes[_offset] << 24) |
        (bytes[_offset + 1] << 16) |
        (bytes[_offset + 2] << 8) |
        bytes[_offset + 3];
    _offset += 4;
    return value;
  }

  Uint8List readBytes(int length) {
    _ensureAvailable(length);
    final data = Uint8List.sublistView(bytes, _offset, _offset + length);
    _offset += length;
    return data;
  }

  String readAscii(int length) {
    return ascii.decode(readBytes(length));
  }

  int readVariableLengthQuantity() {
    var value = 0;
    for (var index = 0; index < 4; index += 1) {
      final byte = readUint8();
      value = (value << 7) | (byte & 0x7f);
      if ((byte & 0x80) == 0) {
        return value;
      }
    }
    throw const FormatException('Variable-length quantity exceeds 4 bytes.');
  }

  void _ensureAvailable(int length) {
    if (_offset + length > bytes.length) {
      throw const FormatException('Unexpected end of Standard MIDI File data.');
    }
  }
}

class _ByteWriter {
  final List<int> _bytes = <int>[];

  int get length => _bytes.length;

  List<int> get bytes => List<int>.unmodifiable(_bytes);

  void writeByte(int value) {
    _bytes.add(value);
  }

  void writeBytes(Iterable<int> values) {
    for (final value in values) {
      writeByte(value);
    }
  }

  void writeUint16(int value) {
    if (value < 0 || value > 0xffff) {
      throw RangeError.range(value, 0, 0xffff, 'value');
    }
    writeByte((value >> 8) & 0xff);
    writeByte(value & 0xff);
  }

  void writeUint32(int value) {
    writeByte((value >> 24) & 0xff);
    writeByte((value >> 16) & 0xff);
    writeByte((value >> 8) & 0xff);
    writeByte(value & 0xff);
  }

  void writeAscii(String value) {
    writeBytes(ascii.encode(value));
  }

  void writeVariableLengthQuantity(int value) {
    if (value < 0 || value > 0x0fffffff) {
      throw RangeError.range(value, 0, 0x0fffffff, 'value');
    }
    var buffer = value & 0x7f;
    while ((value >>= 7) > 0) {
      buffer <<= 8;
      buffer |= (value & 0x7f) | 0x80;
    }
    while (true) {
      writeByte(buffer & 0xff);
      if ((buffer & 0x80) != 0) {
        buffer >>= 8;
      } else {
        break;
      }
    }
  }
}

void _validateChunkType(String type) {
  if (type.length != 4) {
    throw ArgumentError.value(type, 'type', 'Chunk type must be 4 characters.');
  }
  if (type == 'MThd' || type == 'MTrk') {
    throw ArgumentError.value(
      type,
      'type',
      'Unknown chunks must not use Standard MIDI File chunk types.',
    );
  }
  for (final codeUnit in type.codeUnits) {
    if (codeUnit < 0x20 || codeUnit > 0x7e) {
      throw ArgumentError.value(
        type,
        'type',
        'Chunk type must contain printable ASCII characters.',
      );
    }
  }
}

List<int> _validatedBytes(Iterable<int> bytes, String name) {
  return <int>[for (final byte in bytes) _byte(byte, name)];
}

int _byte(int value, String name) {
  if (value < 0 || value > 0xff) {
    throw RangeError.range(value, 0, 0xff, name);
  }
  return value;
}

bool _listEquals<T>(List<T> left, List<T> right) {
  if (left.length != right.length) {
    return false;
  }
  for (var index = 0; index < left.length; index += 1) {
    if (left[index] != right[index]) {
      return false;
    }
  }
  return true;
}
