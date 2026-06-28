import 'dart:async';

enum HeadphoneGesture {
  singlePress,
  doublePress,
  triplePress,
  longPress,
}

class HeadphoneGestureRecognizer {
  HeadphoneGestureRecognizer({
    this.singlePressDelay = const Duration(milliseconds: 300),
    this.longPressThreshold = const Duration(milliseconds: 800),
    this.maxPressCount = 3,
  });

  final Duration singlePressDelay;
  final Duration longPressThreshold;
  final int maxPressCount;

  int _pressCount = 0;
  Timer? _debounceTimer;
  Timer? _longPressTimer;
  bool _longPressFired = false;

  void Function(HeadphoneGesture gesture)? onGesture;

  void onButtonPress() {
    _longPressFired = false;
    _pressCount++;

    if (_pressCount == 1) {
      _longPressTimer?.cancel();
      _longPressTimer = Timer(longPressThreshold, () {
        if (_pressCount == 1 && !_longPressFired) {
          _longPressFired = true;
          _reset();
          onGesture?.call(HeadphoneGesture.longPress);
        }
      });
    } else {
      _longPressTimer?.cancel();
    }

    _debounceTimer?.cancel();
    _debounceTimer = Timer(singlePressDelay, _resolve);
  }

  void _resolve() {
    _longPressTimer?.cancel();
    final count = _pressCount;
    _reset();

    if (_longPressFired) return;

    switch (count) {
      case 1:
        onGesture?.call(HeadphoneGesture.singlePress);
        break;
      case 2:
        onGesture?.call(HeadphoneGesture.doublePress);
        break;
      case 3:
      default:
        onGesture?.call(HeadphoneGesture.triplePress);
        break;
    }
  }

  void _reset() {
    _pressCount = 0;
    _debounceTimer?.cancel();
    _longPressTimer?.cancel();
  }

  void dispose() {
    _debounceTimer?.cancel();
    _longPressTimer?.cancel();
  }
}
