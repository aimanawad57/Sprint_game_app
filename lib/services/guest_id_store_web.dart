// This implementation is selected only by the web conditional import.
// ignore_for_file: avoid_web_libraries_in_flutter

// ignore: deprecated_member_use
import 'dart:html' as html;

String? readGuestId(String key) => html.window.localStorage[key];

void writeGuestId(String key, String value) {
  html.window.localStorage[key] = value;
}
