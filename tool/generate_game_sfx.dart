import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

const _sampleRate = 44100;
const _outputDirectory = 'assets/audio/game';

typedef Synth = double Function(double time, double duration);

void main() {
  final directory = Directory(_outputDirectory)..createSync(recursive: true);
  final cues = <String, ({double duration, Synth synth})>{
    'selection.wav': (duration: 0.08, synth: _selection),
    'illegal_move.wav': (duration: 0.19, synth: _illegalMove),
    'accepted_move.wav': (duration: 0.18, synth: _acceptedMove),
    'opponent_move.wav': (duration: 0.15, synth: _opponentMove),
    'pile_reset.wav': (duration: 0.43, synth: _pileReset()),
    'countdown_tick.wav': (duration: 0.08, synth: _countdownTick),
    'countdown_go.wav': (duration: 0.35, synth: _countdownGo),
    'win.wav': (duration: 0.73, synth: _win),
    'loss.wav': (duration: 0.57, synth: _loss),
    'neutral_end.wav': (duration: 0.46, synth: _neutralEnd),
    'reconnecting.wav': (duration: 0.39, synth: _reconnecting),
    'reconnected.wav': (duration: 0.43, synth: _reconnected),
  };

  for (final entry in cues.entries) {
    final path = '${directory.path}/${entry.key}';
    File(path).writeAsBytesSync(
      _encodeWav(entry.value.duration, entry.value.synth),
      flush: true,
    );
    stdout.writeln('Generated $path');
  }
}

Uint8List _encodeWav(double duration, Synth synth) {
  final sampleCount = (duration * _sampleRate).round();
  final bytes = ByteData(44 + sampleCount * 2);
  void ascii(int offset, String value) {
    for (var index = 0; index < value.length; index += 1) {
      bytes.setUint8(offset + index, value.codeUnitAt(index));
    }
  }

  ascii(0, 'RIFF');
  bytes.setUint32(4, 36 + sampleCount * 2, Endian.little);
  ascii(8, 'WAVE');
  ascii(12, 'fmt ');
  bytes.setUint32(16, 16, Endian.little);
  bytes.setUint16(20, 1, Endian.little);
  bytes.setUint16(22, 1, Endian.little);
  bytes.setUint32(24, _sampleRate, Endian.little);
  bytes.setUint32(28, _sampleRate * 2, Endian.little);
  bytes.setUint16(32, 2, Endian.little);
  bytes.setUint16(34, 16, Endian.little);
  ascii(36, 'data');
  bytes.setUint32(40, sampleCount * 2, Endian.little);

  for (var index = 0; index < sampleCount; index += 1) {
    final time = index / _sampleRate;
    final sample = (synth(time, duration) * 0.92).clamp(-1.0, 1.0);
    bytes.setInt16(44 + index * 2, (sample * 32767).round(), Endian.little);
  }
  return bytes.buffer.asUint8List();
}

double _envelope(
  double time,
  double duration, {
  double attack = 0.008,
  double release = 0.06,
}) {
  final attackGain = (time / attack).clamp(0.0, 1.0);
  final releaseGain = ((duration - time) / release).clamp(0.0, 1.0);
  return attackGain * releaseGain;
}

double _sine(double frequency, double time, [double phase = 0]) =>
    math.sin(math.pi * 2 * frequency * time + phase);

double _chirp(double from, double to, double time, double duration) {
  final rate = (to - from) / duration;
  return math.sin(math.pi * 2 * (from * time + rate * time * time / 2));
}

double _pulse(double time, double center, double width) {
  final distance = (time - center) / width;
  return math.exp(-distance * distance * 5);
}

double _selection(double time, double duration) =>
    _chirp(760, 1180, time, duration) *
    _envelope(time, duration, release: 0.045) *
    0.55;

double _illegalMove(double time, double duration) {
  final wobble = _sine(118, time) + 0.45 * _sine(177, time);
  final driven = wobble * 1.5;
  final softened = driven / (1 + driven.abs());
  return softened *
      _envelope(time, duration, attack: 0.005, release: 0.08) *
      0.52;
}

double _acceptedMove(double time, double duration) {
  // A muted, low card-placement sound. Keep this deliberately distinct from
  // the brighter selection cue and the sharper opponent-move notification.
  final softDrop = _chirp(310, 205, time, duration) * 0.30;
  final body = _sine(155, time) * _pulse(time, 0.055, 0.075) * 0.17;
  final feltTap = _sine(420, time) * _pulse(time, 0.018, 0.022) * 0.07;
  return (softDrop + body + feltTap) *
      _envelope(time, duration, attack: 0.006, release: 0.12);
}

double _opponentMove(double time, double duration) {
  final tone = _chirp(650, 410, time, duration);
  return tone * _envelope(time, duration, release: 0.075) * 0.48;
}

Synth _pileReset() {
  var noiseState = 0x51F15EED;
  return (time, duration) {
    noiseState = (noiseState ^ (noiseState << 13)) & 0xFFFFFFFF;
    noiseState = (noiseState ^ (noiseState >> 17)) & 0xFFFFFFFF;
    noiseState = (noiseState ^ (noiseState << 5)) & 0xFFFFFFFF;
    final noise = ((noiseState & 0xFFFF) / 32767.5) - 1;
    final swish = noise * (0.25 + 0.75 * math.sin(math.pi * time / duration));
    final cards =
        _pulse(time, 0.08, 0.025) * _sine(310, time) +
        _pulse(time, 0.20, 0.025) * _sine(360, time) +
        _pulse(time, 0.33, 0.025) * _sine(420, time);
    return (swish * 0.25 + cards * 0.34) *
        _envelope(time, duration, attack: 0.01, release: 0.08);
  };
}

double _countdownTick(double time, double duration) =>
    (_sine(880, time) + 0.35 * _sine(1760, time)) *
    _envelope(time, duration, attack: 0.002, release: 0.045) *
    0.42;

double _countdownGo(double time, double duration) {
  final body = _chirp(390, 780, time, duration) * 0.40;
  final chord = (_sine(660, time) + _sine(990, time)) * 0.20;
  return (body + chord) * _envelope(time, duration, release: 0.14);
}

double _win(double time, double duration) {
  const notes = [523.25, 659.25, 783.99, 1046.50];
  var value = 0.0;
  for (var index = 0; index < notes.length; index += 1) {
    final center = 0.09 + index * 0.14;
    value += _sine(notes[index], time) * _pulse(time, center, 0.12) * 0.46;
  }
  value +=
      (_sine(523.25, time) + _sine(659.25, time) + _sine(783.99, time)) *
      _pulse(time, 0.63, 0.18) *
      0.22;
  return value * _envelope(time, duration, release: 0.16);
}

double _loss(double time, double duration) {
  final descent = _chirp(440, 196, time, duration) * 0.32;
  final minor = (_sine(261.63, time) + _sine(311.13, time)) * 0.14;
  return (descent + minor) *
      _envelope(time, duration, attack: 0.02, release: 0.20);
}

double _neutralEnd(double time, double duration) {
  final bell = _sine(392, time) * 0.28 + _sine(587.33, time) * 0.18;
  final settle = _chirp(440, 349.23, time, duration) * 0.18;
  return (bell + settle) *
      _envelope(time, duration, attack: 0.012, release: 0.19);
}

double _reconnecting(double time, double duration) {
  final pulses = _pulse(time, 0.10, 0.06) + _pulse(time, 0.27, 0.06);
  return (_sine(294, time) + 0.35 * _sine(588, time)) * pulses * 0.40;
}

double _reconnected(double time, double duration) {
  final rise = _chirp(392, 784, time, duration) * 0.34;
  final resolve =
      (_sine(523.25, time) + _sine(659.25, time)) *
      _pulse(time, 0.32, 0.13) *
      0.22;
  return (rise + resolve) * _envelope(time, duration, release: 0.14);
}
