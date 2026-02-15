import 'package:flutter/material.dart';

enum PageType { home, favorite, playlist }

class PageState with ChangeNotifier {
  PageType _currentPage = PageType.home;

  PageType get currentPage => _currentPage;

  void setPage(PageType page) {
    _currentPage = page;
    notifyListeners();
  }
}