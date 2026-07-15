import 'package:flutter_test/flutter_test.dart';
import 'package:sprint_app/utils/elapsed_time_format.dart';

void main() {
  test('formats sub-minute durations as whole seconds', () {
    expect(formatElapsedTimeMs(0), '0 s');
    expect(formatElapsedTimeMs(999), '0 s');
    expect(formatElapsedTimeMs(37250), '37 s');
    expect(formatElapsedTimeMs(59999), '59 s');
  });

  test('formats minute-plus durations as padded minutes and seconds', () {
    expect(formatElapsedTimeMs(60000), '01:00');
    expect(formatElapsedTimeMs(90500), '01:30');
    expect(formatElapsedTimeMs(5999000), '99:59');
  });

  test('defensively clamps negative durations to zero', () {
    expect(formatElapsedTimeMs(-1), '0 s');
  });
}
