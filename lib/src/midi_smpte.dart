enum MidiSmpteFrameRate {
  fps24(
    signedDivisionByte: -24,
    smpteOffsetCode: 0,
    nominalFramesPerSecond: 24,
    actualFramesPerSecondNumerator: 24,
    actualFramesPerSecondDenominator: 1,
  ),
  fps25(
    signedDivisionByte: -25,
    smpteOffsetCode: 1,
    nominalFramesPerSecond: 25,
    actualFramesPerSecondNumerator: 25,
    actualFramesPerSecondDenominator: 1,
  ),
  fps29DropFrame(
    signedDivisionByte: -29,
    smpteOffsetCode: 2,
    nominalFramesPerSecond: 30,
    actualFramesPerSecondNumerator: 30000,
    actualFramesPerSecondDenominator: 1001,
  ),
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

  final int signedDivisionByte;
  final int smpteOffsetCode;
  final int nominalFramesPerSecond;
  final int actualFramesPerSecondNumerator;
  final int actualFramesPerSecondDenominator;

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
