import 'package:flutter/widgets.dart';

final class Notifier with ChangeNotifier {
  void update() {
    notifyListeners();
  }
}
