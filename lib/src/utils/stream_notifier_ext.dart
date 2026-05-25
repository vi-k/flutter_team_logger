import 'package:flutter/foundation.dart';

import 'stream_notifier.dart';

extension StreamNotifierAsListenable on StreamNotifier {
  Listenable asListenable() => _StreamListenable(this);
}

final class _StreamListenable implements Listenable {
  final StreamNotifier _notifier;

  _StreamListenable(StreamNotifier notifier) : _notifier = notifier;

  @override
  void addListener(VoidCallback listener) {
    _notifier.addListener(listener);
  }

  @override
  void removeListener(VoidCallback listener) {
    _notifier.removeListener(listener);
  }
}
