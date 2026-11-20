import 'package:flutter/foundation.dart';

/// A small in-memory log of connection events, for troubleshooting.
///
/// Users can copy it from Settings → About and send it in a bug report.
/// Never log secrets: no codes, passwords, keys or SDP.
class DiagLog {
  DiagLog._();

  static const _max = 400;
  static final List<String> _lines = [];

  static void add(String event) {
    final t = DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    final line = '${two(t.hour)}:${two(t.minute)}:${two(t.second)}.'
        '${t.millisecond.toString().padLeft(3, '0')} $event';
    _lines.add(line);
    if (_lines.length > _max) _lines.removeAt(0);
    debugPrint('BeamX: $event');
  }

  static String get text => _lines.join('\n');
  static bool get isEmpty => _lines.isEmpty;
}
