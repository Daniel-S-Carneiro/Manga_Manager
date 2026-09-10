import 'package:flutter/foundation.dart';

class RefreshController extends ChangeNotifier {
  void refresh() {
    notifyListeners();
  }
}

final RefreshController globalRefreshController = RefreshController();
