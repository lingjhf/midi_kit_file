import 'dart:convert';
import 'dart:typed_data';

import 'package:midi_kit_file/midi_kit_file.dart';
import 'package:test/test.dart';

void main() {
  group('MidiFile.fromBytes', () {
    test('parses format 1 tracks, tempo events, and running status', () {
      final file = MidiFile.fromBytes(
        _smf(
          format: 1,
          division: 480,
          tracks: <List<int>>[
            <int>[
              0x00,
              0xff,
              0x03,
              0x05,
              ...ascii.encode('Tempo'),
              0x00,
              0xff,
              0x51,
              0x03,
              0x07,
              0xa1,
              0x20,
              0x83,
              0x60,
              0xff,
              0x51,
              0x03,
              0x03,
              0xd0,
              0x90,
              0x00,
              0xff,
              0x2f,
              0x00,
            ],
            <int>[
              0x00,
              0xc0,
              0x00,
              0x00,
              0x90,
              0x3c,
              0x40,
              0x81,
              0x70,
              0x3e,
              0x45,
              0x81,
              0x70,
              0x80,
              0x3c,
              0x00,
              0x00,
              0x3e,
              0x00,
              0x00,
              0xff,
              0x2f,
              0x00,
            ],
          ],
        ),
      );

      expect(file.format, MidiFileFormat.simultaneousTracks);
      expect(file.timeDivision, MidiTicksPerQuarter(480));
      expect(file.tracks, hasLength(2));
      expect(file.tracks.first.effectiveName, 'Tempo');

      final tempoEvents = file.tracks.first.events
          .map((event) => event.event)
          .whereType<MidiMetaEvent>()
          .where((event) => event.microsecondsPerQuarter != null)
          .toList();
      expect(tempoEvents.map((event) => event.microsecondsPerQuarter), <int>[
        500000,
        250000,
      ]);

      final channelEvents = file.tracks[1].events
          .map((event) => event.event)
          .whereType<MidiChannelEvent>()
          .toList();
      expect(channelEvents, hasLength(5));
      expect(
        channelEvents[0].message.type,
        MidiChannelMessageType.programChange,
      );
      expect(channelEvents[1].message.note, 60);
      expect(channelEvents[2].message.note, 62);
      expect(channelEvents[2].message.velocity, 69);
      expect(file.tracks[1].events[2].tick, 240);
      expect(file.tracks[1].events[4].tick, 480);
    });

    test('preserves SysEx and unknown meta events', () {
      final file = MidiFile.fromBytes(
        _smf(
          tracks: <List<int>>[
            <int>[
              0x00,
              0xf0,
              0x03,
              0x01,
              0x02,
              0xf7,
              0x00,
              0xff,
              0x7f,
              0x02,
              0x7d,
              0x01,
              0x00,
              0xff,
              0x2f,
              0x00,
            ],
          ],
        ),
      );

      expect(file.tracks.single.events[0].event, isA<MidiSysExEvent>());
      final sysEx = file.tracks.single.events[0].event as MidiSysExEvent;
      expect(sysEx.status, 0xf0);
      expect(sysEx.data, <int>[0x01, 0x02, 0xf7]);

      final meta = file.tracks.single.events[1].event as MidiMetaEvent;
      expect(meta.type, MidiMetaEvent.sequencerSpecificType);
      expect(meta.data, <int>[0x7d, 0x01]);
    });

    test('accepts extended headers and preserves chunk order', () {
      final firstTrack = <int>[0x00, 0xff, 0x2f, 0x00];
      final secondTrack = <int>[0x00, 0xff, 0x2f, 0x00];
      final file = MidiFile.fromBytes(
        _smfChunks(
          format: 1,
          division: 480,
          trackCount: 2,
          headerExtension: <int>[0x12, 0x34],
          chunks: <_Chunk>[
            const _Chunk('Xpre', <int>[1]),
            _Chunk('MTrk', firstTrack),
            const _Chunk('Xmid', <int>[2]),
            _Chunk('MTrk', secondTrack),
            const _Chunk('Xend', <int>[3]),
          ],
        ),
      );

      expect(file.tracks, hasLength(2));
      expect(
        file.chunks.map((chunk) {
          return switch (chunk) {
            MidiTrackChunk() => 'MTrk',
            MidiUnknownChunk(:final type) => type,
          };
        }),
        <String>['Xpre', 'MTrk', 'Xmid', 'MTrk', 'Xend'],
      );
      expect(MidiFile.fromBytes(file.toBytes()), file);
    });

    test('parses SMPTE time divisions including drop-frame', () {
      final file = MidiFile.fromBytes(
        _smf(
          division: 0xe328,
          tracks: <List<int>>[
            <int>[0x00, 0xff, 0x2f, 0x00],
          ],
        ),
      );

      final division = file.timeDivision as MidiSmpteTimeDivision;
      expect(division.frameRate, MidiSmpteFrameRate.fps29DropFrame);
      expect(division.framesPerSecond, 30);
      expect(division.ticksPerFrame, 40);
    });

    test('throws for invalid files', () {
      expect(
        () => MidiFile.fromBytes(Uint8List.fromList(ascii.encode('bad!'))),
        throwsFormatException,
      );
      expect(
        () => MidiFile.fromBytes(
          _smf(
            tracks: <List<int>>[
              <int>[0x00, 0x90, 0x3c, 0x80],
            ],
          ),
        ),
        throwsFormatException,
      );
      expect(
        () => MidiFile.fromBytes(
          _smf(
            tracks: <List<int>>[
              <int>[0x00, 0x90, 0x3c, 0x40],
            ],
          ),
        ),
        throwsFormatException,
      );
      expect(
        () => MidiFile.fromBytes(
          _smfChunks(trackCount: 0, chunks: const <_Chunk>[]),
        ),
        throwsFormatException,
      );
      expect(
        () => MidiFile.fromBytes(
          _smfChunks(
            trackCount: 1,
            chunks: const <_Chunk>[
              _Chunk('MTrk', <int>[0x00, 0xff, 0x2f, 0x00]),
              _Chunk('MTrk', <int>[0x00, 0xff, 0x2f, 0x00]),
            ],
          ),
        ),
        throwsFormatException,
      );
      expect(
        () => MidiFile.fromBytes(
          _smfChunks(
            trackCount: 2,
            chunks: const <_Chunk>[
              _Chunk('MTrk', <int>[0x00, 0xff, 0x2f, 0x00]),
            ],
          ),
        ),
        throwsFormatException,
      );
      expect(
        () => MidiFile.fromBytes(
          _smfChunks(
            headerLength: 5,
            trackCount: 1,
            chunks: const <_Chunk>[
              _Chunk('MTrk', <int>[0x00, 0xff, 0x2f, 0x00]),
            ],
          ),
        ),
        throwsFormatException,
      );
      expect(
        () => MidiFile.fromBytes(
          _smf(
            division: 0x8001,
            tracks: <List<int>>[
              <int>[0x00, 0xff, 0x2f, 0x00],
            ],
          ),
        ),
        throwsFormatException,
      );
      expect(
        () => MidiFile.fromBytes(
          _smf(
            tracks: <List<int>>[
              <int>[0x00, 0xff, 0x2f, 0x00, 0x00, 0xff, 0x2f, 0x00],
            ],
          ),
        ),
        throwsFormatException,
      );
      expect(
        () => MidiFile.fromBytes(
          _smf(
            tracks: <List<int>>[
              <int>[0x00, 0xf1, 0x00, 0xff, 0x2f, 0x00],
            ],
          ),
        ),
        throwsFormatException,
      );
      expect(
        () => MidiFile.fromBytes(
          _smf(
            tracks: <List<int>>[
              <int>[0x81, 0x81, 0x81, 0x81, 0x00, 0xff, 0x2f, 0x00],
            ],
          ),
        ),
        throwsFormatException,
      );
      expect(
        () => MidiFile.fromBytes(
          _smf(
            tracks: <List<int>>[
              <int>[0x00, 0xff, 0x51, 0x02, 0x01, 0x02],
            ],
          ),
        ),
        throwsFormatException,
      );
    });
  });

  group('MidiFile.toBytes', () {
    test(
      'writes a parseable Standard MIDI File and preserves unknown chunks',
      () {
        final file = MidiFile(
          format: MidiFileFormat.singleTrack,
          timeDivision: MidiTicksPerQuarter(480),
          tracks: <MidiTrack>[
            MidiTrack(
              name: 'Lead',
              events: <MidiTrackEvent>[
                MidiTrackEvent(
                  tick: 0,
                  event: MidiChannelEvent(
                    MidiChannelMessage.programChange(channel: 0, program: 4),
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
          unknownChunks: <MidiUnknownChunk>[
            MidiUnknownChunk(type: 'Xtra', data: <int>[1, 2, 3]),
          ],
        );

        final bytes = file.toBytes();
        expect(ascii.decode(bytes.sublist(0, 4)), 'MThd');
        final parsed = MidiFile.fromBytes(bytes);

        expect(parsed.format, file.format);
        expect(parsed.timeDivision, file.timeDivision);
        expect(parsed.tracks.single.effectiveName, 'Lead');
        expect(parsed.unknownChunks.single.type, 'Xtra');
        expect(parsed.unknownChunks.single.data, <int>[1, 2, 3]);
        expect(
          parsed.tracks.single.events
              .map((event) => event.event)
              .whereType<MidiMetaEvent>()
              .any((event) => event.isEndOfTrack),
          isTrue,
        );
      },
    );

    test('roundtrips explicit end-of-track and same-tick ordering', () {
      final source = MidiFile(
        format: MidiFileFormat.singleTrack,
        timeDivision: MidiTicksPerQuarter(960),
        tracks: <MidiTrack>[
          MidiTrack(
            events: <MidiTrackEvent>[
              MidiTrackEvent(tick: 0, event: MidiMetaEvent.setTempo(600000)),
              MidiTrackEvent(
                tick: 0,
                event: MidiChannelEvent(
                  MidiChannelMessage.noteOn(channel: 1, note: 67, velocity: 90),
                ),
              ),
              MidiTrackEvent(
                tick: 960,
                event: MidiChannelEvent(
                  MidiChannelMessage.noteOff(channel: 1, note: 67),
                ),
              ),
              MidiTrackEvent(tick: 960, event: MidiMetaEvent.endOfTrack()),
            ],
          ),
        ],
      );

      final restored = MidiFile.fromBytes(source.toBytes());
      expect(restored, source);
    });

    test('writes SysEx events and SMPTE time divisions', () {
      final file = MidiFile(
        format: MidiFileFormat.singleTrack,
        timeDivision: MidiSmpteTimeDivision(
          frameRate: MidiSmpteFrameRate.fps25,
          ticksPerFrame: 80,
        ),
        tracks: <MidiTrack>[
          MidiTrack(
            events: <MidiTrackEvent>[
              MidiTrackEvent(
                tick: 0,
                event: MidiSysExEvent(status: 0xf7, data: <int>[0x01, 0x02]),
              ),
            ],
          ),
        ],
      );

      final restored = MidiFile.fromBytes(file.toBytes());
      expect(restored.timeDivision, file.timeDivision);
      expect(restored.tracks.single.events.first.event, isA<MidiSysExEvent>());
    });

    test('does not duplicate explicit track name events', () {
      final file = MidiFile(
        format: MidiFileFormat.singleTrack,
        timeDivision: MidiTicksPerQuarter(480),
        tracks: <MidiTrack>[
          MidiTrack(
            name: 'Fallback',
            events: <MidiTrackEvent>[
              MidiTrackEvent(tick: 0, event: MidiMetaEvent.trackName('Real')),
            ],
          ),
        ],
      );

      final restored = MidiFile.fromBytes(file.toBytes());
      expect(
        restored.tracks.single.events
            .map((event) => event.event)
            .whereType<MidiMetaEvent>()
            .where((event) => event.type == MidiMetaEvent.trackNameType),
        hasLength(1),
      );
      expect(restored.tracks.single.effectiveName, 'Real');
    });

    test('rejects tracks that exceed the MIDI delta-time range', () {
      final file = MidiFile(
        format: MidiFileFormat.singleTrack,
        timeDivision: MidiTicksPerQuarter(480),
        tracks: <MidiTrack>[
          MidiTrack(
            events: <MidiTrackEvent>[
              MidiTrackEvent(
                tick: 0x10000000,
                event: MidiMetaEvent.endOfTrack(),
              ),
            ],
          ),
        ],
      );

      expect(file.toBytes, throwsRangeError);
    });
  });

  group('MidiTempoMap', () {
    test('converts PPQ ticks through tempo changes', () {
      final file = MidiFile(
        format: MidiFileFormat.singleTrack,
        timeDivision: MidiTicksPerQuarter(480),
        tracks: <MidiTrack>[
          MidiTrack(
            events: <MidiTrackEvent>[
              MidiTrackEvent(tick: 0, event: MidiMetaEvent.setTempo(500000)),
              MidiTrackEvent(tick: 480, event: MidiMetaEvent.setTempo(250000)),
              MidiTrackEvent(tick: 960, event: MidiMetaEvent.endOfTrack()),
            ],
          ),
        ],
      );

      final tempoMap = MidiTempoMap.fromFile(file);

      expect(tempoMap.changes, hasLength(2));
      expect(
        tempoMap.tickToDuration(480, file.timeDivision),
        const Duration(milliseconds: 500),
      );
      expect(
        tempoMap.tickToDuration(960, file.timeDivision),
        const Duration(milliseconds: 750),
      );
    });

    test('converts SMPTE ticks independently of tempo', () {
      final tempoMap = MidiTempoMap(const <MidiTempoChange>[]);

      expect(
        tempoMap.tickToDuration(
          300,
          MidiSmpteTimeDivision(
            frameRate: MidiSmpteFrameRate.fps30,
            ticksPerFrame: 10,
          ),
        ),
        const Duration(seconds: 1),
      );
      expect(
        tempoMap.tickToDuration(
          3000,
          MidiSmpteTimeDivision(
            frameRate: MidiSmpteFrameRate.fps29DropFrame,
            ticksPerFrame: 100,
          ),
        ),
        const Duration(milliseconds: 1001),
      );
    });

    test('builds maps per track and rejects format 2 file-level maps', () {
      final firstTrack = MidiTrack(
        events: <MidiTrackEvent>[
          MidiTrackEvent(tick: 0, event: MidiMetaEvent.setTempo(400000)),
          MidiTrackEvent(tick: 0, event: MidiMetaEvent.endOfTrack()),
        ],
      );
      final secondTrack = MidiTrack(
        events: <MidiTrackEvent>[
          MidiTrackEvent(tick: 0, event: MidiMetaEvent.setTempo(700000)),
          MidiTrackEvent(tick: 0, event: MidiMetaEvent.endOfTrack()),
        ],
      );
      final file = MidiFile(
        format: MidiFileFormat.independentSequences,
        timeDivision: MidiTicksPerQuarter(100),
        tracks: <MidiTrack>[firstTrack, secondTrack],
      );

      expect(() => MidiTempoMap.fromFile(file), throwsArgumentError);
      expect(
        MidiTempoMap.fromTrack(
          secondTrack,
        ).tickToDuration(100, file.timeDivision),
        const Duration(milliseconds: 700),
      );
    });

    test('normalizes tempo changes and validates inputs', () {
      final map = MidiTempoMap(<MidiTempoChange>[
        MidiTempoChange(tick: 240, microsecondsPerQuarter: 400000),
        MidiTempoChange(tick: 0, microsecondsPerQuarter: 500000),
        MidiTempoChange(tick: 240, microsecondsPerQuarter: 250000),
      ]);

      expect(map.changes, <MidiTempoChange>[
        MidiTempoChange(tick: 0, microsecondsPerQuarter: 500000),
        MidiTempoChange(tick: 240, microsecondsPerQuarter: 250000),
      ]);
      expect(
        () => map.tickToDuration(-1, MidiTicksPerQuarter(480)),
        throwsRangeError,
      );
      expect(
        () => MidiTempoChange(tick: -1, microsecondsPerQuarter: 1),
        throwsRangeError,
      );
      expect(
        () => MidiTempoChange(tick: 0, microsecondsPerQuarter: 0),
        throwsRangeError,
      );
    });
  });

  group('MidiChannelMessage', () {
    test('builds all channel message types and exposes typed getters', () {
      final noteOff = MidiChannelMessage.noteOff(channel: 0, note: 60);
      final noteOn = MidiChannelMessage.noteOn(
        channel: 1,
        note: 61,
        velocity: 90,
      );
      final pressure = MidiChannelMessage.polyphonicKeyPressure(
        channel: 2,
        note: 62,
        pressure: 70,
      );
      final control = MidiChannelMessage.controlChange(
        channel: 3,
        controller: 64,
        value: 127,
      );
      final program = MidiChannelMessage.programChange(channel: 4, program: 5);
      final channelPressure = MidiChannelMessage.channelPressure(
        channel: 5,
        pressure: 80,
      );
      final pitchBend = MidiChannelMessage.pitchBend(channel: 6, value: 0x2000);

      expect(noteOff.velocity, 0);
      expect(noteOn.note, 61);
      expect(noteOn.velocity, 90);
      expect(pressure.note, 62);
      expect(control.controller, 64);
      expect(program.program, 5);
      expect(channelPressure.note, isNull);
      expect(channelPressure.velocity, isNull);
      expect(channelPressure.controller, isNull);
      expect(channelPressure.program, isNull);
      expect(channelPressure.pitchBendValue, isNull);
      expect(pitchBend.pitchBendValue, 0x2000);
      expect(pitchBend.toBytes(), <int>[0xe6, 0x00, 0x40]);
      expect(pitchBend, MidiChannelMessage.fromBytes(<int>[0xe6, 0x00, 0x40]));
      expect(
        pitchBend.hashCode,
        MidiChannelMessage.pitchBend(channel: 6, value: 0x2000).hashCode,
      );
      expect(pitchBend.toString(), contains('pitchBend'));
    });

    test('validates channel message construction and parsing', () {
      expect(
        () => MidiChannelMessage(
          type: MidiChannelMessageType.programChange,
          channel: 0,
          data1: 1,
          data2: 2,
        ),
        throwsArgumentError,
      );
      expect(
        () => MidiChannelMessage(
          type: MidiChannelMessageType.noteOn,
          channel: 0,
          data1: 1,
        ),
        throwsArgumentError,
      );
      expect(
        () => MidiChannelMessage.noteOn(channel: 0, note: 128, velocity: 0),
        throwsRangeError,
      );
      expect(
        () => MidiChannelMessage.fromBytes(<int>[]),
        throwsFormatException,
      );
      expect(
        () => MidiChannelMessage.fromBytes(<int>[0x70, 0x00, 0x00]),
        throwsFormatException,
      );
      expect(
        () => MidiChannelMessage.fromBytes(<int>[0x90, 0x00]),
        throwsFormatException,
      );
      expect(
        () => MidiChannelMessage.fromBytes(<int>[0x90, 0x80, 0x00]),
        throwsFormatException,
      );
      expect(
        () => MidiChannelMessage.typeForStatus(0xf0),
        throwsFormatException,
      );
    });
  });

  group('MidiMetaEvent', () {
    test('builds standard meta events and exposes typed views', () {
      final sequence = MidiMetaEvent.sequenceNumber(0x1234);
      final tempo = MidiMetaEvent.setTempo(750000);
      final time = MidiMetaEvent.timeSignature(
        numerator: 7,
        denominator: 8,
        clocksPerMetronomeClick: 36,
        thirtySecondNotesPerQuarter: 12,
      );
      final key = MidiMetaEvent.keySignature(sharpsFlats: -3, isMinor: true);
      final prefix = MidiMetaEvent.midiChannelPrefix(9);
      final port = MidiMetaEvent.midiPort(200);
      final offset = MidiMetaEvent.smpteOffset(
        frameRate: MidiSmpteFrameRate.fps29DropFrame,
        hours: 1,
        minutes: 2,
        seconds: 3,
        frames: 4,
        fractionalFrames: 5,
      );
      final sequencer = MidiMetaEvent.sequencerSpecific(<int>[0x7d, 0x01]);
      final programName = MidiMetaEvent.text(
        type: MidiTextMetaEventType.programName,
        text: 'Piano',
      );
      final reservedText = MidiMetaEvent.textByType(type: 0x0f, text: 'Text');

      expect(sequence.sequenceNumber, 0x1234);
      expect(sequence.microsecondsPerQuarter, isNull);
      expect(sequence.smpteOffset, isNull);
      expect(sequence.timeSignature, isNull);
      expect(sequence.keySignature, isNull);
      expect(sequence.sequencerSpecific, isNull);
      expect(sequence.text, isNull);
      expect(tempo.microsecondsPerQuarter, 750000);
      expect(prefix.midiChannelPrefix, 9);
      expect(prefix.midiPort, isNull);
      expect(port.midiPort, 200);
      expect(time.timeSignature!.numerator, 7);
      expect(time.timeSignature!.denominatorPower, 3);
      expect(time.timeSignature!.denominator, BigInt.from(8));
      expect(time.timeSignature!.clocksPerMetronomeClick, 36);
      expect(time.timeSignature!.thirtySecondNotesPerQuarter, 12);
      expect(key.keySignature!.sharpsFlats, -3);
      expect(key.keySignature!.isMinor, isTrue);
      expect(
        offset.smpteOffset,
        const MidiSmpteOffset(
          frameRate: MidiSmpteFrameRate.fps29DropFrame,
          hours: 1,
          minutes: 2,
          seconds: 3,
          frames: 4,
          fractionalFrames: 5,
        ),
      );
      expect(offset.smpteOffset.hashCode, offset.smpteOffset.hashCode);
      expect(sequencer.sequencerSpecific, <int>[0x7d, 0x01]);
      expect(programName.text, 'Piano');
      expect(reservedText.text, 'Text');
      expect(MidiMetaEvent.trackName('Track').trackName, 'Track');
      expect(MidiMetaEvent.endOfTrack().isEndOfTrack, isTrue);
      expect(tempo.toString(), contains('0x51'));
      expect(tempo.hashCode, MidiMetaEvent.setTempo(750000).hashCode);
    });

    test('validates standard meta event construction and file data', () {
      expect(
        () => MidiMetaEvent(type: -1, data: const <int>[]),
        throwsRangeError,
      );
      expect(() => MidiMetaEvent.sequenceNumber(0x10000), throwsRangeError);
      expect(() => MidiMetaEvent.setTempo(0), throwsRangeError);
      expect(
        () => MidiMetaEvent.timeSignature(numerator: 0, denominator: 4),
        throwsRangeError,
      );
      expect(
        () => MidiMetaEvent.timeSignature(numerator: 1, denominator: 3),
        throwsArgumentError,
      );
      expect(
        () => MidiMetaEvent.keySignature(sharpsFlats: 8, isMinor: false),
        throwsRangeError,
      );
      expect(() => MidiMetaEvent.midiChannelPrefix(16), throwsRangeError);
      expect(() => MidiMetaEvent.midiPort(256), throwsRangeError);
      expect(
        () => MidiMetaEvent.smpteOffset(
          frameRate: MidiSmpteFrameRate.fps24,
          hours: 24,
          minutes: 0,
          seconds: 0,
          frames: 0,
          fractionalFrames: 0,
        ),
        throwsRangeError,
      );
      expect(
        () => MidiMetaEvent.smpteOffset(
          frameRate: MidiSmpteFrameRate.fps24,
          hours: 0,
          minutes: 60,
          seconds: 0,
          frames: 0,
          fractionalFrames: 0,
        ),
        throwsRangeError,
      );
      expect(
        () => MidiMetaEvent.smpteOffset(
          frameRate: MidiSmpteFrameRate.fps24,
          hours: 0,
          minutes: 0,
          seconds: 60,
          frames: 0,
          fractionalFrames: 0,
        ),
        throwsRangeError,
      );
      expect(
        () => MidiMetaEvent.smpteOffset(
          frameRate: MidiSmpteFrameRate.fps24,
          hours: 0,
          minutes: 0,
          seconds: 0,
          frames: 24,
          fractionalFrames: 0,
        ),
        throwsRangeError,
      );
      expect(
        () => MidiMetaEvent.smpteOffset(
          frameRate: MidiSmpteFrameRate.fps24,
          hours: 0,
          minutes: 0,
          seconds: 0,
          frames: 0,
          fractionalFrames: 256,
        ),
        throwsRangeError,
      );
      expect(
        () => MidiMetaEvent.textByType(type: 0x10, text: 'bad'),
        throwsRangeError,
      );
      expect(
        () => MidiMetaEvent(type: MidiMetaEvent.endOfTrackType, data: <int>[0]),
        throwsArgumentError,
      );
      expect(
        () => MidiMetaEvent(
          type: MidiMetaEvent.midiChannelPrefixType,
          data: <int>[16],
        ),
        throwsRangeError,
      );
      expect(
        () => MidiMetaEvent(
          type: MidiMetaEvent.smpteOffsetType,
          data: <int>[24, 0, 0, 0, 0],
        ),
        throwsRangeError,
      );
      expect(
        () => MidiMetaEvent(
          type: MidiMetaEvent.smpteOffsetType,
          data: <int>[0, 60, 0, 0, 0],
        ),
        throwsRangeError,
      );
      expect(
        () => MidiMetaEvent(
          type: MidiMetaEvent.smpteOffsetType,
          data: <int>[0, 0, 60, 0, 0],
        ),
        throwsRangeError,
      );
      expect(
        () => MidiMetaEvent(
          type: MidiMetaEvent.smpteOffsetType,
          data: <int>[0, 0, 0, 24, 0],
        ),
        throwsRangeError,
      );
      expect(
        () => MidiMetaEvent(
          type: MidiMetaEvent.timeSignatureType,
          data: <int>[0, 2, 24, 8],
        ),
        throwsRangeError,
      );
      expect(
        () => MidiMetaEvent(
          type: MidiMetaEvent.keySignatureType,
          data: <int>[8, 0],
        ),
        throwsRangeError,
      );
      expect(
        () => MidiMetaEvent(
          type: MidiMetaEvent.keySignatureType,
          data: <int>[0, 2],
        ),
        throwsRangeError,
      );
      expect(
        () => MidiMetaEvent.fromFileData(
          type: MidiMetaEvent.setTempoType,
          data: <int>[0, 0],
        ),
        throwsFormatException,
      );
    });
  });

  group('value semantics', () {
    test('covers hashes, strings, and fallback names', () {
      final channelEvent = MidiChannelEvent(
        MidiChannelMessage.noteOn(channel: 0, note: 60, velocity: 1),
      );
      final sysex = MidiSysExEvent(status: 0xf0, data: <int>[1, 2]);
      final track = MidiTrack(
        name: 'Name',
        events: <MidiTrackEvent>[MidiTrackEvent(tick: 0, event: channelEvent)],
      );
      final chunk = MidiTrackChunk(track);
      final unknown = MidiUnknownChunk(type: 'Test', data: <int>[1]);
      final file = MidiFile(
        format: MidiFileFormat.singleTrack,
        timeDivision: MidiTicksPerQuarter(480),
        tracks: <MidiTrack>[track],
        unknownChunks: <MidiUnknownChunk>[unknown],
      );
      final tempoChange = MidiTempoChange(
        tick: 1,
        microsecondsPerQuarter: 500000,
      );
      final event = MidiTrackEvent(tick: 1, event: sysex);
      final smpte = MidiSmpteTimeDivision(
        frameRate: MidiSmpteFrameRate.fps30,
        ticksPerFrame: 10,
      );

      expect(channelEvent.hashCode, channelEvent.message.hashCode);
      expect(channelEvent.toString(), contains('MidiChannelEvent'));
      expect(sysex, MidiSysExEvent(status: 0xf0, data: <int>[1, 2]));
      expect(
        sysex.hashCode,
        MidiSysExEvent(status: 0xf0, data: <int>[1, 2]).hashCode,
      );
      expect(sysex.toString(), contains('0xf0'));
      expect(
        MidiTicksPerQuarter(480).hashCode,
        MidiTicksPerQuarter(480).hashCode,
      );
      expect(MidiTicksPerQuarter(480).toString(), 'MidiTicksPerQuarter(480)');
      expect(
        smpte.hashCode,
        MidiSmpteTimeDivision(
          frameRate: MidiSmpteFrameRate.fps30,
          ticksPerFrame: 10,
        ).hashCode,
      );
      expect(smpte.toString(), contains('fps30'));
      expect(file.hashCode, file.hashCode);
      expect(chunk.hashCode, track.hashCode);
      expect(track.effectiveName, 'Name');
      expect(track.hashCode, track.hashCode);
      expect(event.hashCode, event.hashCode);
      expect(event.toString(), contains('tick: 1'));
      expect(unknown.hashCode, unknown.hashCode);
      expect(tempoChange.hashCode, tempoChange.hashCode);
    });
  });

  group('model validation', () {
    test('validates channel messages and format 0 track count', () {
      expect(
        () => MidiChannelMessage.noteOn(channel: 16, note: 60, velocity: 90),
        throwsRangeError,
      );
      expect(
        () => MidiChannelMessage.pitchBend(channel: 0, value: 0x4000),
        throwsRangeError,
      );
      expect(
        () => MidiFile(
          format: MidiFileFormat.singleTrack,
          timeDivision: MidiTicksPerQuarter(480),
          tracks: <MidiTrack>[
            MidiTrack(events: <MidiTrackEvent>[]),
            MidiTrack(events: <MidiTrackEvent>[]),
          ],
        ),
        throwsArgumentError,
      );
      expect(
        () => MidiFile(
          format: MidiFileFormat.simultaneousTracks,
          timeDivision: MidiTicksPerQuarter(480),
          tracks: <MidiTrack>[],
        ),
        throwsArgumentError,
      );
      expect(() => MidiFileFormat.fromValue(3), throwsFormatException);
      expect(() => MidiTicksPerQuarter(0), throwsRangeError);
      expect(() => MidiTicksPerQuarter(0x8000), throwsRangeError);
      expect(
        () => MidiSmpteTimeDivision(
          frameRate: MidiSmpteFrameRate.fps24,
          ticksPerFrame: 0,
        ),
        throwsRangeError,
      );
      expect(
        () => MidiFile(
          format: MidiFileFormat.simultaneousTracks,
          timeDivision: MidiTicksPerQuarter(480),
          tracks: List<MidiTrack>.filled(
            0x10000,
            MidiTrack(events: <MidiTrackEvent>[]),
          ),
        ).toBytes(),
        throwsRangeError,
      );
      expect(
        () => MidiTrack(
          events: <MidiTrackEvent>[
            MidiTrackEvent(tick: 0, event: MidiMetaEvent.endOfTrack()),
            MidiTrackEvent(tick: 1, event: MidiMetaEvent.endOfTrack()),
          ],
        ),
        throwsArgumentError,
      );
      expect(
        () => MidiTrackEvent(tick: -1, event: MidiMetaEvent.endOfTrack()),
        throwsRangeError,
      );
      expect(
        () => MidiUnknownChunk(type: 'Bad', data: const <int>[]),
        throwsArgumentError,
      );
      expect(
        () => MidiUnknownChunk(type: 'Bad\n', data: const <int>[]),
        throwsArgumentError,
      );
      expect(
        () => MidiUnknownChunk(type: 'Good', data: const <int>[256]),
        throwsRangeError,
      );
      expect(
        () => MidiSysExEvent(status: 0xf1, data: const <int>[]),
        throwsArgumentError,
      );
      expect(
        MidiSmpteFrameRate.fromSignedDivisionByte(-24),
        MidiSmpteFrameRate.fps24,
      );
      expect(
        MidiSmpteFrameRate.fromSignedDivisionByte(-25),
        MidiSmpteFrameRate.fps25,
      );
      expect(
        MidiSmpteFrameRate.fromSignedDivisionByte(-30),
        MidiSmpteFrameRate.fps30,
      );
      expect(
        () => MidiSmpteFrameRate.fromSignedDivisionByte(-26),
        throwsFormatException,
      );
      expect(
        MidiSmpteFrameRate.fromSmpteOffsetCode(3),
        MidiSmpteFrameRate.fps30,
      );
      expect(
        () => MidiSmpteFrameRate.fromSmpteOffsetCode(4),
        throwsArgumentError,
      );
    });
  });
}

Uint8List _smf({
  int format = 0,
  int division = 480,
  required List<List<int>> tracks,
}) {
  return _smfChunks(
    format: format,
    division: division,
    trackCount: tracks.length,
    chunks: <_Chunk>[for (final track in tracks) _Chunk('MTrk', track)],
  );
}

Uint8List _smfChunks({
  int format = 0,
  int division = 480,
  int? headerLength,
  int trackCount = 1,
  List<int> headerExtension = const <int>[],
  required List<_Chunk> chunks,
}) {
  final actualHeaderLength = headerLength ?? 6 + headerExtension.length;
  final bytes = <int>[
    ...ascii.encode('MThd'),
    (actualHeaderLength >> 24) & 0xff,
    (actualHeaderLength >> 16) & 0xff,
    (actualHeaderLength >> 8) & 0xff,
    actualHeaderLength & 0xff,
    (format >> 8) & 0xff,
    format & 0xff,
    (trackCount >> 8) & 0xff,
    trackCount & 0xff,
    (division >> 8) & 0xff,
    division & 0xff,
    ...headerExtension,
  ];
  for (final chunk in chunks) {
    bytes
      ..addAll(ascii.encode(chunk.type))
      ..addAll(<int>[
        (chunk.data.length >> 24) & 0xff,
        (chunk.data.length >> 16) & 0xff,
        (chunk.data.length >> 8) & 0xff,
        chunk.data.length & 0xff,
      ])
      ..addAll(chunk.data);
  }
  return Uint8List.fromList(bytes);
}

class _Chunk {
  const _Chunk(this.type, this.data);

  final String type;
  final List<int> data;
}
