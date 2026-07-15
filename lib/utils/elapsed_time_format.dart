String formatElapsedTimeMs(int milliseconds) {
  final totalSeconds = milliseconds < 0 ? 0 : milliseconds ~/ 1000;
  if (totalSeconds < 60) {
    return '$totalSeconds s';
  }

  final minutes = totalSeconds ~/ 60;
  final seconds = totalSeconds % 60;
  final minuteText = minutes.toString().padLeft(2, '0');
  final secondText = seconds.toString().padLeft(2, '0');
  return '$minuteText:$secondText';
}
