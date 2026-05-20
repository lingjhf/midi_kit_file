/// A Standard MIDI File SMPTE frame rate.
enum MidiSmpteFrameRate {
  /// 24 frames per second.
  fps24(
    signedDivisionByte: -24,
    smpteOffsetCode: 0,
    nominalFramesPerSecond: 24,
    actualFramesPerSecondNumerator: 24,
    actualFramesPerSecondDenominator: 1,
  ),

  /// 25 frames per second.
  fps25(
    signedDivisionByte: -25,
    smpteOffsetCode: 1,
    nominalFramesPerSecond: 25,
    actualFramesPerSecondNumerator: 25,
    actualFramesPerSecondDenominator: 1,
  ),

  /// 29.97 drop-frame time code.
  fps29DropFrame(
    signedDivisionByte: -29,
    smpteOffsetCode: 2,
    nominalFramesPerSecond: 30,
    actualFramesPerSecondNumerator: 30000,
    actualFramesPerSecondDenominator: 1001,
  ),

  /// 30 frames per second.
  fps30(
    signedDivisionByte: -30,
    smpteOffsetCode: 3,
    nominalFramesPerSecond: 30,
    actualFramesPerSecondNumerator: 30,
    actualFramesPerSecondDenominator: 1,
  );

  const MidiSmpteFrameRate({
    required this.signedDivisionByte,
    required this.smpteOffsetCode,
    required this.nominalFramesPerSecond,
    required this.actualFramesPerSecondNumerator,
    required this.actualFramesPerSecondDenominator,
  });

  /// The signed byte stored in a Standard MIDI File time division.
  final int signedDivisionByte;

  /// The two-bit frame-rate code used by SMPTE offset meta events.
  final int smpteOffsetCode;

  /// The nominal whole-number frame rate.
  final int nominalFramesPerSecond;

  /// The numerator of the actual frame rate.
  final int actualFramesPerSecondNumerator;

  /// The denominator of the actual frame rate.
  final int actualFramesPerSecondDenominator;

  /// Returns the frame rate encoded by [signedDivisionByte].
  static MidiSmpteFrameRate fromSignedDivisionByte(int signedDivisionByte) {
    for (final frameRate in MidiSmpteFrameRate.values) {
      if (frameRate.signedDivisionByte == signedDivisionByte) {
        return frameRate;
      }
    }
    throw FormatException(
      'Unsupported SMPTE time division frame rate: $signedDivisionByte.',
    );
  }

  /// Returns the frame rate encoded by a SMPTE offset frame-rate code.
  static MidiSmpteFrameRate fromSmpteOffsetCode(int smpteOffsetCode) {
    for (final frameRate in MidiSmpteFrameRate.values) {
      if (frameRate.smpteOffsetCode == smpteOffsetCode) {
        return frameRate;
      }
    }
    throw ArgumentError.value(
      smpteOffsetCode,
      'smpteOffsetCode',
      'Supported SMPTE offset codes are 0 through 3.',
    );
  }
}
