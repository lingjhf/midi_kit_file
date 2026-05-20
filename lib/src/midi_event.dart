import 'dart:collection';
import 'dart:convert';

import 'midi_channel_message.dart';
import 'midi_smpte.dart';

/// A MIDI event stored in a Standard MIDI File track.
sealed class MidiEvent {
  const MidiEvent();
}

/// A channel voice event.
class MidiChannelEvent extends MidiEvent {
  /// Creates a channel voice event for [message].
  const MidiChannelEvent(this.message);

  /// The channel voice message.
  final MidiChannelMessage message;

  @override
  bool operator ==(Object other) {
    return other is MidiChannelEvent && other.message == message;
  }

  @override
  int get hashCode => message.hashCode;

  @override
  String toString() => 'MidiChannelEvent($message)';
}

/// A Standard MIDI File meta event.
class MidiMetaEvent extends MidiEvent {
  /// Creates a meta event with raw [data].
  ///
  /// Standard fixed-length meta events are validated against their required
  /// lengths.
  MidiMetaEvent({required this.type, required Iterable<int> data})
    : data = UnmodifiableListView<int>(_validatedBytes(data, 'meta data')) {
    if (type < 0 || type > 0x7f) {
      throw RangeError.range(type, 0, 0x7f, 'type');
    }
    _validateMetaEventData(type, this.data);
  }

  /// Parses meta event data from a Standard MIDI File track.
  ///
  /// Throws a [FormatException] when [type] and [data] do not form a valid
  /// meta event.
  factory MidiMetaEvent.fromFileData({
    required int type,
    required Iterable<int> data,
  }) {
    try {
      return MidiMetaEvent(type: type, data: data);
    } on ArgumentError catch (error) {
      throw FormatException(error.toString());
    }
  }

  /// Creates an end-of-track meta event.
  factory MidiMetaEvent.endOfTrack() {
    return MidiMetaEvent(type: endOfTrackType, data: const <int>[]);
  }

  /// Creates a sequence number meta event.
  factory MidiMetaEvent.sequenceNumber(int sequenceNumber) {
    if (sequenceNumber < 0 || sequenceNumber > 0xffff) {
      throw RangeError.range(sequenceNumber, 0, 0xffff, 'sequenceNumber');
    }
    return MidiMetaEvent(
      type: sequenceNumberType,
      data: <int>[(sequenceNumber >> 8) & 0xff, sequenceNumber & 0xff],
    );
  }

  /// Creates a set-tempo meta event.
  ///
  /// The [microsecondsPerQuarter] value must be in `1..0xffffff`.
  factory MidiMetaEvent.setTempo(int microsecondsPerQuarter) {
    if (microsecondsPerQuarter <= 0 || microsecondsPerQuarter > 0xffffff) {
      throw RangeError.range(
        microsecondsPerQuarter,
        1,
        0xffffff,
        'microsecondsPerQuarter',
      );
    }
    return MidiMetaEvent(
      type: setTempoType,
      data: <int>[
        (microsecondsPerQuarter >> 16) & 0xff,
        (microsecondsPerQuarter >> 8) & 0xff,
        microsecondsPerQuarter & 0xff,
      ],
    );
  }

  /// Creates a time signature meta event.
  factory MidiMetaEvent.timeSignature({
    required int numerator,
    required int denominator,
    int clocksPerMetronomeClick = 24,
    int thirtySecondNotesPerQuarter = 8,
  }) {
    if (numerator <= 0 || numerator > 0xff) {
      throw RangeError.range(numerator, 1, 0xff, 'numerator');
    }
    final denominatorPower = _powerOfTwoExponent(denominator, 'denominator');
    return MidiMetaEvent(
      type: timeSignatureType,
      data: <int>[
        numerator,
        denominatorPower,
        _byte(clocksPerMetronomeClick, 'clocksPerMetronomeClick'),
        _byte(thirtySecondNotesPerQuarter, 'thirtySecondNotesPerQuarter'),
      ],
    );
  }

  /// Creates a key signature meta event.
  factory MidiMetaEvent.keySignature({
    required int sharpsFlats,
    required bool isMinor,
  }) {
    if (sharpsFlats < -7 || sharpsFlats > 7) {
      throw RangeError.range(sharpsFlats, -7, 7, 'sharpsFlats');
    }
    return MidiMetaEvent(
      type: keySignatureType,
      data: <int>[sharpsFlats & 0xff, isMinor ? 1 : 0],
    );
  }

  /// Creates a MIDI channel prefix meta event.
  factory MidiMetaEvent.midiChannelPrefix(int channel) {
    if (channel < 0 || channel > 0x0f) {
      throw RangeError.range(channel, 0, 0x0f, 'channel');
    }
    return MidiMetaEvent(type: midiChannelPrefixType, data: <int>[channel]);
  }

  /// Creates a MIDI port meta event.
  factory MidiMetaEvent.midiPort(int port) {
    return MidiMetaEvent(type: midiPortType, data: <int>[_byte(port, 'port')]);
  }

  /// Creates a SMPTE offset meta event.
  factory MidiMetaEvent.smpteOffset({
    required MidiSmpteFrameRate frameRate,
    required int hours,
    required int minutes,
    required int seconds,
    required int frames,
    required int fractionalFrames,
  }) {
    if (hours < 0 || hours > 23) {
      throw RangeError.range(hours, 0, 23, 'hours');
    }
    if (minutes < 0 || minutes > 59) {
      throw RangeError.range(minutes, 0, 59, 'minutes');
    }
    if (seconds < 0 || seconds > 59) {
      throw RangeError.range(seconds, 0, 59, 'seconds');
    }
    if (frames < 0 || frames >= frameRate.nominalFramesPerSecond) {
      throw RangeError.range(
        frames,
        0,
        frameRate.nominalFramesPerSecond - 1,
        'frames',
      );
    }
    return MidiMetaEvent(
      type: smpteOffsetType,
      data: <int>[
        (frameRate.smpteOffsetCode << 6) | hours,
        minutes,
        seconds,
        frames,
        _byte(fractionalFrames, 'fractionalFrames'),
      ],
    );
  }

  /// Creates a sequencer-specific meta event.
  factory MidiMetaEvent.sequencerSpecific(Iterable<int> data) {
    return MidiMetaEvent(type: sequencerSpecificType, data: data);
  }

  /// Creates a track-name meta event.
  factory MidiMetaEvent.trackName(String name) {
    return MidiMetaEvent(type: trackNameType, data: utf8.encode(name));
  }

  /// Creates a text meta event.
  factory MidiMetaEvent.text({
    required MidiTextMetaEventType type,
    required String text,
  }) {
    return MidiMetaEvent(type: type.metaType, data: utf8.encode(text));
  }

  /// Creates a text meta event by raw meta event type.
  ///
  /// The [type] must be in `0x01..0x0f`.
  factory MidiMetaEvent.textByType({required int type, required String text}) {
    if (!_isTextMetaType(type)) {
      throw RangeError.range(type, textType, textType + 0x0e, 'type');
    }
    return MidiMetaEvent(type: type, data: utf8.encode(text));
  }

  /// The sequence number meta event type.
  static const int sequenceNumberType = 0x00;

  /// The text meta event type.
  static const int textType = 0x01;

  /// The copyright notice meta event type.
  static const int copyrightType = 0x02;

  /// The track-name meta event type.
  static const int trackNameType = 0x03;

  /// The instrument-name meta event type.
  static const int instrumentNameType = 0x04;

  /// The lyric meta event type.
  static const int lyricType = 0x05;

  /// The marker meta event type.
  static const int markerType = 0x06;

  /// The cue-point meta event type.
  static const int cuePointType = 0x07;

  /// The program-name meta event type.
  static const int programNameType = 0x08;

  /// The device-name meta event type.
  static const int deviceNameType = 0x09;

  /// The MIDI channel prefix meta event type.
  static const int midiChannelPrefixType = 0x20;

  /// The MIDI port meta event type.
  static const int midiPortType = 0x21;

  /// The end-of-track meta event type.
  static const int endOfTrackType = 0x2f;

  /// The set-tempo meta event type.
  static const int setTempoType = 0x51;

  /// The SMPTE offset meta event type.
  static const int smpteOffsetType = 0x54;

  /// The time signature meta event type.
  static const int timeSignatureType = 0x58;

  /// The key signature meta event type.
  static const int keySignatureType = 0x59;

  /// The sequencer-specific meta event type.
  static const int sequencerSpecificType = 0x7f;

  /// The meta event type byte.
  final int type;

  /// The raw meta event data.
  final UnmodifiableListView<int> data;

  /// Whether this meta event is an end-of-track event.
  bool get isEndOfTrack => type == endOfTrackType;

  /// The sequence number, when this is a sequence number meta event.
  int? get sequenceNumber {
    if (type != sequenceNumberType) {
      return null;
    }
    return (data[0] << 8) | data[1];
  }

  /// The tempo in microseconds per quarter note, when this is a tempo event.
  int? get microsecondsPerQuarter {
    if (type != setTempoType) {
      return null;
    }
    return (data[0] << 16) | (data[1] << 8) | data[2];
  }

  /// The channel prefix, when this is a MIDI channel prefix meta event.
  int? get midiChannelPrefix {
    return type == midiChannelPrefixType ? data[0] : null;
  }

  /// The MIDI port, when this is a MIDI port meta event.
  int? get midiPort {
    return type == midiPortType ? data[0] : null;
  }

  /// The SMPTE offset, when this is a SMPTE offset meta event.
  MidiSmpteOffset? get smpteOffset {
    if (type != smpteOffsetType) {
      return null;
    }
    final frameRate = MidiSmpteFrameRate.fromSmpteOffsetCode(data[0] >> 6);
    return MidiSmpteOffset(
      frameRate: frameRate,
      hours: data[0] & 0x1f,
      minutes: data[1],
      seconds: data[2],
      frames: data[3],
      fractionalFrames: data[4],
    );
  }

  /// The time signature, when this is a time signature meta event.
  ({
    int numerator,
    int denominatorPower,
    BigInt denominator,
    int clocksPerMetronomeClick,
    int thirtySecondNotesPerQuarter,
  })?
  get timeSignature {
    if (type != timeSignatureType) {
      return null;
    }
    return (
      numerator: data[0],
      denominatorPower: data[1],
      denominator: BigInt.one << data[1],
      clocksPerMetronomeClick: data[2],
      thirtySecondNotesPerQuarter: data[3],
    );
  }

  /// The key signature, when this is a key signature meta event.
  ({int sharpsFlats, bool isMinor})? get keySignature {
    if (type != keySignatureType) {
      return null;
    }
    return (sharpsFlats: _signedByte(data[0]), isMinor: data[1] == 1);
  }

  /// The raw data, when this is a sequencer-specific meta event.
  UnmodifiableListView<int>? get sequencerSpecific {
    return type == sequencerSpecificType ? data : null;
  }

  /// The decoded text, when this is a text meta event.
  String? get text {
    if (!_isTextMetaType(type)) {
      return null;
    }
    return utf8.decode(data, allowMalformed: true);
  }

  /// The track name, when this is a track-name meta event.
  String? get trackName {
    return type == trackNameType ? text : null;
  }

  @override
  bool operator ==(Object other) {
    return other is MidiMetaEvent &&
        other.type == type &&
        _listEquals(other.data, data);
  }

  @override
  int get hashCode => Object.hash(type, Object.hashAll(data));

  @override
  String toString() {
    return 'MidiMetaEvent(type: 0x${type.toRadixString(16)}, '
        'dataLength: ${data.length})';
  }
}

/// A Standard MIDI File text meta event kind.
enum MidiTextMetaEventType {
  /// A generic text event.
  text(MidiMetaEvent.textType),

  /// A copyright notice event.
  copyright(MidiMetaEvent.copyrightType),

  /// A track-name event.
  trackName(MidiMetaEvent.trackNameType),

  /// An instrument-name event.
  instrumentName(MidiMetaEvent.instrumentNameType),

  /// A lyric event.
  lyric(MidiMetaEvent.lyricType),

  /// A marker event.
  marker(MidiMetaEvent.markerType),

  /// A cue-point event.
  cuePoint(MidiMetaEvent.cuePointType),

  /// A program-name event.
  programName(MidiMetaEvent.programNameType),

  /// A device-name event.
  deviceName(MidiMetaEvent.deviceNameType);

  const MidiTextMetaEventType(this.metaType);

  /// The raw meta event type byte.
  final int metaType;
}

/// A SMPTE offset encoded by a meta event.
class MidiSmpteOffset {
  /// Creates a SMPTE offset.
  const MidiSmpteOffset({
    required this.frameRate,
    required this.hours,
    required this.minutes,
    required this.seconds,
    required this.frames,
    required this.fractionalFrames,
  });

  /// The SMPTE frame rate.
  final MidiSmpteFrameRate frameRate;

  /// The hour component.
  final int hours;

  /// The minute component.
  final int minutes;

  /// The second component.
  final int seconds;

  /// The frame component.
  final int frames;

  /// The fractional-frame component.
  final int fractionalFrames;

  @override
  bool operator ==(Object other) {
    return other is MidiSmpteOffset &&
        other.frameRate == frameRate &&
        other.hours == hours &&
        other.minutes == minutes &&
        other.seconds == seconds &&
        other.frames == frames &&
        other.fractionalFrames == fractionalFrames;
  }

  @override
  int get hashCode {
    return Object.hash(
      frameRate,
      hours,
      minutes,
      seconds,
      frames,
      fractionalFrames,
    );
  }
}

/// A Standard MIDI File SysEx or escape event.
class MidiSysExEvent extends MidiEvent {
  /// Creates a SysEx event.
  ///
  /// The [status] must be `0xf0` or `0xf7`.
  MidiSysExEvent({required this.status, required Iterable<int> data})
    : data = UnmodifiableListView<int>(_validatedBytes(data, 'SysEx data')) {
    if (status != 0xf0 && status != 0xf7) {
      throw ArgumentError.value(
        status,
        'status',
        'SysEx event status must be 0xf0 or 0xf7.',
      );
    }
  }

  /// The SysEx status byte.
  final int status;

  /// The raw SysEx event data.
  final UnmodifiableListView<int> data;

  @override
  bool operator ==(Object other) {
    return other is MidiSysExEvent &&
        other.status == status &&
        _listEquals(other.data, data);
  }

  @override
  int get hashCode => Object.hash(status, Object.hashAll(data));

  @override
  String toString() {
    return 'MidiSysExEvent(status: 0x${status.toRadixString(16)}, '
        'dataLength: ${data.length})';
  }
}

void _validateMetaEventData(int type, List<int> data) {
  final expectedLength = switch (type) {
    MidiMetaEvent.sequenceNumberType => 2,
    MidiMetaEvent.midiChannelPrefixType => 1,
    MidiMetaEvent.midiPortType => 1,
    MidiMetaEvent.endOfTrackType => 0,
    MidiMetaEvent.setTempoType => 3,
    MidiMetaEvent.smpteOffsetType => 5,
    MidiMetaEvent.timeSignatureType => 4,
    MidiMetaEvent.keySignatureType => 2,
    _ => null,
  };
  if (expectedLength != null && data.length != expectedLength) {
    throw ArgumentError.value(
      data,
      'data',
      'Meta event 0x${type.toRadixString(16)} data must be exactly '
          '$expectedLength bytes.',
    );
  }

  switch (type) {
    case MidiMetaEvent.midiChannelPrefixType:
      if (data[0] > 0x0f) {
        throw RangeError.range(data[0], 0, 0x0f, 'midiChannelPrefix');
      }
    case MidiMetaEvent.smpteOffsetType:
      final frameRate = MidiSmpteFrameRate.fromSmpteOffsetCode(data[0] >> 6);
      final hours = data[0] & 0x1f;
      if (hours > 23) {
        throw RangeError.range(hours, 0, 23, 'hours');
      }
      if (data[1] > 59) {
        throw RangeError.range(data[1], 0, 59, 'minutes');
      }
      if (data[2] > 59) {
        throw RangeError.range(data[2], 0, 59, 'seconds');
      }
      if (data[3] >= frameRate.nominalFramesPerSecond) {
        throw RangeError.range(
          data[3],
          0,
          frameRate.nominalFramesPerSecond - 1,
          'frames',
        );
      }
    case MidiMetaEvent.timeSignatureType:
      if (data[0] == 0) {
        throw RangeError.range(data[0], 1, 0xff, 'numerator');
      }
    case MidiMetaEvent.keySignatureType:
      final sharpsFlats = _signedByte(data[0]);
      if (sharpsFlats < -7 || sharpsFlats > 7) {
        throw RangeError.range(sharpsFlats, -7, 7, 'sharpsFlats');
      }
      if (data[1] != 0 && data[1] != 1) {
        throw RangeError.range(data[1], 0, 1, 'isMinor');
      }
  }
}

bool _isTextMetaType(int type) {
  return type >= MidiMetaEvent.textType &&
      type <= MidiMetaEvent.textType + 0x0e;
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

int _signedByte(int value) {
  return value >= 0x80 ? value - 0x100 : value;
}

int _powerOfTwoExponent(int value, String name) {
  if (value <= 0 || value & (value - 1) != 0) {
    throw ArgumentError.value(value, name, 'Must be a power of two.');
  }
  var exponent = 0;
  var current = value;
  while (current > 1) {
    current >>= 1;
    exponent += 1;
  }
  return exponent;
}

bool _listEquals(List<int> left, List<int> right) {
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
