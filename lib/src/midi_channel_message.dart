/// A Standard MIDI channel voice message kind.
enum MidiChannelMessageType {
  /// A note-off message.
  noteOff(0x80, 2),

  /// A note-on message.
  noteOn(0x90, 2),

  /// A polyphonic key pressure message.
  polyphonicKeyPressure(0xa0, 2),

  /// A control change message.
  controlChange(0xb0, 2),

  /// A program change message.
  programChange(0xc0, 1),

  /// A channel pressure message.
  channelPressure(0xd0, 1),

  /// A pitch bend change message.
  pitchBend(0xe0, 2);

  const MidiChannelMessageType(this.statusClass, this.dataLength);

  /// The high nibble used by this message type's status byte.
  final int statusClass;

  /// The number of data bytes carried by this message type.
  final int dataLength;
}

/// A Standard MIDI channel voice message.
class MidiChannelMessage {
  /// Creates a channel voice message.
  ///
  /// The [channel] must be in `0..15` and data bytes must be in `0..127`.
  MidiChannelMessage({
    required this.type,
    required this.channel,
    required this.data1,
    this.data2,
  }) {
    _validateChannel(channel);
    _validateDataByte(data1, 'data1');
    if (type.dataLength == 1) {
      if (data2 != null) {
        throw ArgumentError.value(
          data2,
          'data2',
          '${type.name} must not include a second data byte.',
        );
      }
    } else {
      final second = data2;
      if (second == null) {
        throw ArgumentError.notNull('data2');
      }
      _validateDataByte(second, 'data2');
    }
  }

  /// Creates a note-off message.
  factory MidiChannelMessage.noteOff({
    required int channel,
    required int note,
    int velocity = 0,
  }) {
    return MidiChannelMessage(
      type: MidiChannelMessageType.noteOff,
      channel: channel,
      data1: note,
      data2: velocity,
    );
  }

  /// Creates a note-on message.
  factory MidiChannelMessage.noteOn({
    required int channel,
    required int note,
    required int velocity,
  }) {
    return MidiChannelMessage(
      type: MidiChannelMessageType.noteOn,
      channel: channel,
      data1: note,
      data2: velocity,
    );
  }

  /// Creates a polyphonic key pressure message.
  factory MidiChannelMessage.polyphonicKeyPressure({
    required int channel,
    required int note,
    required int pressure,
  }) {
    return MidiChannelMessage(
      type: MidiChannelMessageType.polyphonicKeyPressure,
      channel: channel,
      data1: note,
      data2: pressure,
    );
  }

  /// Creates a control change message.
  factory MidiChannelMessage.controlChange({
    required int channel,
    required int controller,
    required int value,
  }) {
    return MidiChannelMessage(
      type: MidiChannelMessageType.controlChange,
      channel: channel,
      data1: controller,
      data2: value,
    );
  }

  /// Creates a program change message.
  factory MidiChannelMessage.programChange({
    required int channel,
    required int program,
  }) {
    return MidiChannelMessage(
      type: MidiChannelMessageType.programChange,
      channel: channel,
      data1: program,
    );
  }

  /// Creates a channel pressure message.
  factory MidiChannelMessage.channelPressure({
    required int channel,
    required int pressure,
  }) {
    return MidiChannelMessage(
      type: MidiChannelMessageType.channelPressure,
      channel: channel,
      data1: pressure,
    );
  }

  /// Creates a pitch bend message.
  ///
  /// The [value] must be the 14-bit MIDI pitch bend value in `0..0x3fff`.
  factory MidiChannelMessage.pitchBend({
    required int channel,
    required int value,
  }) {
    if (value < 0 || value > _pitchBendMax) {
      throw RangeError.range(value, 0, _pitchBendMax, 'value');
    }
    return MidiChannelMessage(
      type: MidiChannelMessageType.pitchBend,
      channel: channel,
      data1: value & _dataByteMax,
      data2: (value >> 7) & _dataByteMax,
    );
  }

  /// Parses a complete MIDI channel voice message.
  ///
  /// Throws a [FormatException] if [bytes] does not contain exactly one
  /// channel voice message.
  factory MidiChannelMessage.fromBytes(List<int> bytes) {
    if (bytes.isEmpty) {
      throw const FormatException('MIDI channel message bytes are empty.');
    }
    final status = bytes.first;
    if (status < 0x80 || status > 0xef) {
      throw FormatException(
        'MIDI channel message status must be 0x80 through 0xef: $status.',
      );
    }
    final type = typeForStatus(status);
    final expectedLength = 1 + type.dataLength;
    if (bytes.length != expectedLength) {
      throw FormatException(
        'MIDI channel message ${type.name} must have $expectedLength bytes.',
      );
    }
    for (var index = 1; index < bytes.length; index += 1) {
      _validateParsedDataByte(bytes[index], 'data');
    }
    return MidiChannelMessage(
      type: type,
      channel: status & 0x0f,
      data1: bytes[1],
      data2: type.dataLength == 2 ? bytes[2] : null,
    );
  }

  /// The message type.
  final MidiChannelMessageType type;

  /// The zero-based MIDI channel number.
  final int channel;

  /// The first MIDI data byte.
  final int data1;

  /// The second MIDI data byte, when the message type has one.
  final int? data2;

  /// The note number for note and polyphonic key pressure messages.
  int? get note {
    return switch (type) {
      MidiChannelMessageType.noteOff ||
      MidiChannelMessageType.noteOn ||
      MidiChannelMessageType.polyphonicKeyPressure => data1,
      _ => null,
    };
  }

  /// The velocity for note-on and note-off messages.
  int? get velocity {
    return switch (type) {
      MidiChannelMessageType.noteOff || MidiChannelMessageType.noteOn => data2,
      _ => null,
    };
  }

  /// The controller number for control change messages.
  int? get controller {
    return type == MidiChannelMessageType.controlChange ? data1 : null;
  }

  /// The program number for program change messages.
  int? get program {
    return type == MidiChannelMessageType.programChange ? data1 : null;
  }

  /// The 14-bit value for pitch bend messages.
  int? get pitchBendValue {
    if (type != MidiChannelMessageType.pitchBend) {
      return null;
    }
    final second = data2;
    return second == null ? null : data1 | (second << 7);
  }

  /// Encodes this message to status and data bytes.
  List<int> toBytes() {
    final status = type.statusClass | channel;
    return <int>[status, data1, ?data2];
  }

  /// Returns the channel message type for [status].
  static MidiChannelMessageType typeForStatus(int status) {
    final statusClass = status & 0xf0;
    for (final type in MidiChannelMessageType.values) {
      if (type.statusClass == statusClass) {
        return type;
      }
    }
    throw FormatException('Unsupported MIDI channel status byte: $status.');
  }

  @override
  bool operator ==(Object other) {
    return other is MidiChannelMessage &&
        other.type == type &&
        other.channel == channel &&
        other.data1 == data1 &&
        other.data2 == data2;
  }

  @override
  int get hashCode => Object.hash(type, channel, data1, data2);

  @override
  String toString() {
    return 'MidiChannelMessage(type: ${type.name}, channel: $channel, '
        'data1: $data1, data2: $data2)';
  }
}

const int _dataByteMax = 0x7f;
const int _pitchBendMax = 0x3fff;

void _validateChannel(int channel) {
  if (channel < 0 || channel > 0x0f) {
    throw RangeError.range(channel, 0, 0x0f, 'channel');
  }
}

void _validateDataByte(int value, String name) {
  if (value < 0 || value > _dataByteMax) {
    throw RangeError.range(value, 0, _dataByteMax, name);
  }
}

void _validateParsedDataByte(int value, String name) {
  if (value < 0 || value > _dataByteMax) {
    throw FormatException('MIDI $name byte must be 0 through 127: $value.');
  }
}
