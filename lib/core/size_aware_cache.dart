import 'dart:collection';

class SizeAwareCache<K, V> {
  final int maxBytes;
  int _currentBytes = 0;
  final LinkedHashMap<K, _CacheEntry<V>> _map = LinkedHashMap();

  SizeAwareCache({required this.maxBytes});

  V? get(K key) {
    final entry = _map[key];
    if (entry == null) return null;
    _map.remove(key);
    _map[key] = entry;
    return entry.value;
  }

  void put(K key, V value, int sizeBytes) {
    _evictIfNeeded(sizeBytes);
    _map[key] = _CacheEntry(value, sizeBytes);
    _currentBytes += sizeBytes;
  }

  void remove(K key) {
    final entry = _map.remove(key);
    if (entry != null) {
      _currentBytes -= entry.sizeBytes;
    }
  }

  void clear() {
    _map.clear();
    _currentBytes = 0;
  }

  bool containsKey(K key) => _map.containsKey(key);

  int get length => _map.length;

  int get currentBytes => _currentBytes;

  void _evictIfNeeded(int incoming) {
    while (_currentBytes + incoming > maxBytes && _map.isNotEmpty) {
      final oldest = _map.entries.first;
      _currentBytes -= oldest.value.sizeBytes;
      _map.remove(oldest.key);
    }
  }
}

class _CacheEntry<V> {
  final V value;
  final int sizeBytes;

  _CacheEntry(this.value, this.sizeBytes);
}

class LruCache<K, V> {
  final int maxEntries;
  final LinkedHashMap<K, V> _map = LinkedHashMap();

  LruCache({required this.maxEntries});

  V? get(K key) {
    final value = _map[key];
    if (value == null) return null;
    _map.remove(key);
    _map[key] = value;
    return value;
  }

  void put(K key, V value) {
    if (_map.containsKey(key)) {
      _map.remove(key);
    } else if (_map.length >= maxEntries) {
      _map.remove(_map.keys.first);
    }
    _map[key] = value;
  }

  void remove(K key) => _map.remove(key);

  void clear() => _map.clear();

  bool containsKey(K key) => _map.containsKey(key);

  int get length => _map.length;
}