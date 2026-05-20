enum MidiChannelMessageType {
  noteOff(0x80, 2),
  noteOn(0x90, 2),
  polyphonicKeyPressure(0xa0, 2),
  controlChange(0xb0, 2),
  programChange(0xc0, 1),
  channelPressure(0xd0, 1),
  pitchBend(0xe0, 2);

  const MidiChannelMessageType(this.statusClass, this.dataLength);

  final int statusClass;
  final int dataLength;
}

class MidiChannelMessage {
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

  final MidiChannelMessageType type;
  final int channel;
  final int data1;
  final int? data2;

  int? get note {
    return switch (type) {
      MidiChannelMessageType.noteOff ||
      MidiChannelMessageType.noteOn ||
      MidiChannelMessageType.polyphonicKeyPressure => data1,
      _ => null,
    };
  }

  int? get velocity {
    return switch (type) {
      MidiChannelMessageType.noteOff || MidiChannelMessageType.noteOn => data2,
      _ => null,
    };
  }

  int? get controller {
    return type == MidiChannelMessageType.controlChange ? data1 : null;
  }

  int? get program {
    return type == MidiChannelMessageType.programChange ? data1 : null;
  }

  int? get pitchBendValue {
    if (type != MidiChannelMessageType.pitchBend) {
      return null;
    }
    return data1 | (data2! << 7);
  }

  List<int> toBytes() {
    final status = type.statusClass | channel;
    return <int>[status, data1, ?data2];
  }

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
