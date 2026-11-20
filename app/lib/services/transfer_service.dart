import 'package:flutter/foundation.dart';

enum TransferDirection { outgoing, incoming }

enum TransferStatus { waiting, active, done, declined, failed }

/// One file sent or received, shown on the Transfers screen.
class TransferItem {
  TransferItem({
    required this.id,
    required this.name,
    required this.size,
    required this.direction,
    required this.peer,
  });

  final String id;
  final String name;
  final int size;
  final TransferDirection direction;
  final String peer;
  int transferred = 0;
  TransferStatus status = TransferStatus.waiting;
  String? path;
  String? error;

  double get progress => size == 0 ? 1 : transferred / size;
}

/// The list of transfers in this app session.
class TransferService extends ChangeNotifier {
  final List<TransferItem> _items = [];

  List<TransferItem> get items => List.unmodifiable(_items.reversed);

  void add(TransferItem item) {
    _items.add(item);
    if (_items.length > 200) _items.removeAt(0);
    notifyListeners();
  }

  /// Call after changing an item's fields.
  void changed() => notifyListeners();

  void clearFinished() {
    _items.removeWhere((i) =>
        i.status != TransferStatus.waiting && i.status != TransferStatus.active);
    notifyListeners();
  }
}
