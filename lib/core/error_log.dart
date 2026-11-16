import 'package:flutter/foundation.dart';

class LoggedError {
  LoggedError(this.area, this.message) : time = DateTime.now();
  final String area;
  final String message;
  final DateTime time;
}

/// In-memory ring buffer for the hidden debug screen. Never contains message
/// bodies or audio; only error codes / short descriptions.
class ErrorLog extends ChangeNotifier {
  ErrorLog({this.capacity = 50});
  final int capacity;
  final List<LoggedError> _items = [];
  List<LoggedError> get items => List.unmodifiable(_items.reversed);

  void add(String area, String message) {
    _items.add(LoggedError(area, message));
    if (_items.length > capacity) _items.removeAt(0);
    if (kDebugMode) debugPrint('[$area] $message');
    notifyListeners();
  }

  void clear() {
    _items.clear();
    notifyListeners();
  }
}
