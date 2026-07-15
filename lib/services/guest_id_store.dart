import 'dart:math';

import 'guest_id_store_stub.dart'
    if (dart.library.html) 'guest_id_store_web.dart' as storage;

const _guestIdKey = 'sprint_guest_device_id';

String getOrCreateGuestId() {
  final savedId = storage.readGuestId(_guestIdKey);
  if (savedId != null && savedId.isNotEmpty) {
    return savedId;
  }

  final random = Random.secure();
  final randomPart = List.generate(
    24,
    (_) => random.nextInt(16).toRadixString(16),
  ).join();
  final guestId = 'sprint-guest-$randomPart';
  storage.writeGuestId(_guestIdKey, guestId);
  return guestId;
}
