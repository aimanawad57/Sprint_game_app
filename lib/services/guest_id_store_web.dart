// ignore: deprecated_member_use
import 'dart:html' as html;

String? readGuestId(String key) => html.window.localStorage[key];

void writeGuestId(String key, String value) {
  html.window.localStorage[key] = value;
}
