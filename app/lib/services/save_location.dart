import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// Where BeamX saves received files, screenshots and recordings.
///
/// - Windows / macOS / Linux: Downloads/BeamX
/// - Android: Download/BeamX (falls back to the app's own folder)
/// - iOS: the app's Documents folder, shown in the Files app
class SaveLocation {
  SaveLocation._();

  static Future<Directory> dir() async {
    Directory dir;
    if (Platform.isAndroid) {
      dir = Directory('/storage/emulated/0/Download/BeamX');
      try {
        await dir.create(recursive: true);
        final probe = File('${dir.path}/.beamx-write-test');
        await probe.writeAsString('ok');
        await probe.delete();
        return dir;
      } catch (_) {
        final base = await getExternalStorageDirectory() ??
            await getApplicationDocumentsDirectory();
        dir = Directory('${base.path}/BeamX');
      }
    } else if (Platform.isIOS) {
      dir = await getApplicationDocumentsDirectory();
    } else {
      final base =
          await getDownloadsDirectory() ?? await getApplicationDocumentsDirectory();
      dir = Directory('${base.path}${Platform.pathSeparator}BeamX');
    }
    await dir.create(recursive: true);
    return dir;
  }

  /// A file in [dir] named [name], adding " (2)", " (3)"… if it exists.
  static Future<File> uniqueFile(Directory dir, String name) async {
    final dot = name.lastIndexOf('.');
    final stem = dot > 0 ? name.substring(0, dot) : name;
    final ext = dot > 0 ? name.substring(dot) : '';
    var f = File('${dir.path}${Platform.pathSeparator}$name');
    for (var i = 2; await f.exists(); i++) {
      f = File('${dir.path}${Platform.pathSeparator}$stem ($i)$ext');
    }
    return f;
  }

  /// A file name like "BeamX Desktop 2026-11-20 14.05.33.png".
  static String timestamped(String peer, String ext) {
    final t = DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    final safePeer = peer.replaceAll(RegExp(r'[\\/:*?"<>|\u0000-\u001F]'), '_');
    return 'BeamX $safePeer ${t.year}-${two(t.month)}-${two(t.day)} '
        '${two(t.hour)}.${two(t.minute)}.${two(t.second)}.$ext';
  }
}
