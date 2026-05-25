import 'dart:async';

import 'package:meta/meta.dart';

base class StreamNotifier with Stream<void>, StreamNotifierMixin {}

mixin StreamNotifierMixin on Stream<void> {
  final _controller = StreamController<void>.broadcast(sync: true);
  final _subscriptions = <(void Function(), StreamSubscription<void>)>[];

  @mustCallSuper
  Future<void> dispose() => _controller.close();

  bool get hasListeners => _controller.hasListener;

  bool get isClosed => _controller.isClosed;

  var _isFiring = false;

  @protected
  @visibleForTesting
  void notifyListeners() {
    if (_isFiring || !_controller.hasListener) return;

    try {
      _isFiring = true;
      _controller.add(null);
    } finally {
      _isFiring = false;
    }
  }

  StreamSubscription<void> subscribe(
    void Function() onData, {
    void Function()? onDone,
  }) =>
      listen((_) => onData(), onDone: onDone);

  void addListener(void Function() listener) {
    _subscriptions.add((listener, subscribe(listener)));
  }

  void removeListener(void Function() listener) {
    final index = _subscriptions.indexWhere((e) => identical(e.$1, listener));
    if (index != -1) {
      _subscriptions[index].$2.cancel();
      _subscriptions.removeAt(index);
    }
  }

  @override
  @nonVirtual
  @visibleForTesting
  StreamSubscription<void> listen(
    void Function(void event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) =>
      _controller.stream.listen(
        onData,
        onError: onError,
        onDone: onDone,
        cancelOnError: cancelOnError,
      );
}
