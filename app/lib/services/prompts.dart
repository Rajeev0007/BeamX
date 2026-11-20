import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:material_ui/material_ui.dart';

/// Lets background services ask the user something.
final navigatorKey = GlobalKey<NavigatorState>();

String formatBytes(int b) {
  if (b < 1024) return '$b B';
  const units = ['KB', 'MB', 'GB'];
  var v = b / 1024;
  var i = 0;
  while (v >= 1024 && i < units.length - 1) {
    v /= 1024;
    i++;
  }
  return '${v.toStringAsFixed(v < 10 ? 1 : 0)} ${units[i]}';
}

class Prompts {
  Prompts._();

  /// Asks whether to save an incoming file. Returns false if no UI.
  static Future<bool> confirmIncomingFile({
    required String from,
    required String name,
    required int size,
  }) async {
    final ctx = navigatorKey.currentContext;
    if (ctx == null) return false;
    final ok = await showDialog<bool>(
      context: ctx,
      builder: (d) => AlertDialog(
        icon: const Icon(Icons.file_download_rounded, size: 36),
        title: Text('$from wants to send you a file'),
        content: Text('$name\n${formatBytes(size)}'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(d, false),
              child: const Text('Decline')),
          FilledButton(
              onPressed: () => Navigator.pop(d, true),
              child: const Text('Save')),
        ],
      ),
    );
    return ok ?? false;
  }

  /// Lets the user pick which monitor to share. Returns null if cancelled.
  static Future<DesktopCapturerSource?> chooseScreen(
      List<DesktopCapturerSource> sources) async {
    final ctx = navigatorKey.currentContext;
    if (ctx == null) return sources.first;
    return showDialog<DesktopCapturerSource>(
      context: ctx,
      builder: (d) => SimpleDialog(
        title: const Text('Which screen do you want to share?'),
        children: [
          for (var i = 0; i < sources.length; i++)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(d, sources[i]),
              child: ListTile(
                leading: const Icon(Icons.monitor_rounded),
                title: Text(sources[i].name.isEmpty
                    ? 'Screen ${i + 1}'
                    : sources[i].name),
                subtitle: i == 0 ? const Text('Main screen') : null,
              ),
            ),
        ],
      ),
    );
  }
}
