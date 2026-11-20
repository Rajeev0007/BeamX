import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../models/settings.dart';
import 'diag_log.dart';
import 'discovery_service.dart';
import 'input/input_injector.dart';
import 'prompts.dart';
import 'save_location.dart';
import 'settings_store.dart';
import 'transfer_service.dart';
import 'trust_store.dart';

/// Files, clipboard and trust keys, sent over the WebRTC data channel.
///
/// The data channel is end-to-end encrypted (DTLS) and authenticated by the
/// same pairing that protects the video. Everything received is untrusted
/// input and is size-limited and validated.
class DataLink {
  DataLink({
    required this.peerName,
    required this._settings,
    required this._transfers,
    required this._trust,
    required this.isSharer,
    bool allowControl = false,
    this.expectedPeerId,
    this.trustToSend,
  }) : controlAllowed = ValueNotifier(allowControl);

  /// True on the device whose screen is shared (and may be controlled).
  final bool isSharer;

  /// Sharer: whether the viewer may control this device. Only the owner of
  /// this device can change it.
  final ValueNotifier<bool> controlAllowed;

  /// Sharer: what the user must do before control can work, if anything.
  final ValueNotifier<String?> controlProblem = ValueNotifier(null);

  /// Viewer: whether the other device lets us control it, and its platform.
  final ValueNotifier<RemoteControlStatus> remote =
      ValueNotifier(const RemoteControlStatus(allowed: false, platform: ''));

  /// Session messages (quality, bye) arriving over the data channel.
  Future<void> Function(Map<String, dynamic>)? onSessionMessage;

  /// Sends a session message over the data channel.
  void sendSessionMessage(Map<String, Object?> m) =>
      _sendJson({'t': 'session', 'm': m});

  InputInjector? _injector;
  bool _injectorReady = false;
  Timer? _controlTimer;

  static const _chunk = 16 * 1024;
  static const _maxBuffered = 1024 * 1024;
  static const _maxText = 256 * 1024;
  static const maxFileSize = 4 * 1024 * 1024 * 1024; // 4 GB

  final String peerName;
  final SettingsStore _settings;
  final TransferService _transfers;
  final TrustStore _trust;

  /// The other device's permanent ID, if known from the handshake.
  final String? expectedPeerId;

  /// A trust key to give the other device once the channel opens.
  final Map<String, Object>? trustToSend;

  RTCDataChannel? _dc;
  final ValueNotifier<bool> ready = ValueNotifier(false);
  bool _closed = false;

  // Clipboard
  Timer? _clipTimer;
  String? _lastClip;

  // Outgoing files, one at a time.
  final List<_OutFile> _queue = [];
  bool _sending = false;
  final Map<String, Completer<bool>> _answers = {};
  TransferItem? _outgoing;

  // Incoming file.
  TransferItem? _incoming;
  IOSink? _sink;
  File? _file;

  void attach(RTCDataChannel dc) {
    _dc = dc;
    dc.onDataChannelState = (s) {
      if (s == RTCDataChannelState.RTCDataChannelOpen) {
        _onOpen();
      } else if (s == RTCDataChannelState.RTCDataChannelClosed) {
        DiagLog.add('data channel closed');
        ready.value = false;
      }
    };
    dc.onMessage = _onMessage;
    if (dc.state == RTCDataChannelState.RTCDataChannelOpen) _onOpen();
  }

  void _onOpen() {
    if (ready.value || _closed) return;
    ready.value = true;
    final t = trustToSend;
    if (t != null) _sendJson({'t': 'trust', ...t});
    if (isSharer) {
      _injector = InputInjector.create();
      _checkControl();
      // Re-check, so control starts working right after the user grants
      // the OS permission.
      _controlTimer =
          Timer.periodic(const Duration(seconds: 2), (_) => _checkControl());
    }
    _clipTimer = Timer.periodic(const Duration(seconds: 1), (_) => _pollClipboard());
    _pumpQueue();
  }

  Future<void> _sendJson(Map<String, Object?> m) async {
    final dc = _dc;
    if (dc == null || !ready.value) return;
    await dc.send(RTCDataChannelMessage(jsonEncode(m)));
  }

  Future<void> _onMessage(RTCDataChannelMessage msg) async {
    if (_closed) return;
    if (msg.isBinary) {
      await _onChunk(msg.binary);
      return;
    }
    if (msg.text.length > _maxText + 1024) return;
    Object? m;
    try {
      m = jsonDecode(msg.text);
    } catch (_) {
      return;
    }
    if (m is! Map) return;
    switch (m['t']) {
      case 'session':
        final inner = m['m'];
        if (inner is Map<String, dynamic> && inner['t'] is String &&
            const {'quality', 'bye'}.contains(inner['t'])) {
          await onSessionMessage?.call(inner);
        }
      case 'clip':
        _onClip(m['text']);
      case 'in' when isSharer:
        await _onInput(m);
      case 'control' when !isSharer:
        final allowed = m['allowed'], platform = m['platform'];
        remote.value = RemoteControlStatus(
          allowed: allowed == true,
          platform: platform is String && platform.length <= 16 ? platform : '',
        );
      case 'trust':
        _onTrust(m);
      case 'file-offer':
        await _onFileOffer(m);
      case 'file-answer':
        final id = m['id'];
        if (id is String) _answers.remove(id)?.complete(m['ok'] == true);
      case 'file-done':
        await _onFileDone(m['id']);
      case 'file-cancel':
        await _failIncoming('${m['reason'] ?? 'Cancelled by sender'}');
    }
  }

  // ---------- Trust ----------

  void _onTrust(Map<dynamic, dynamic> m) {
    final id = m['id'], name = m['name'], platform = m['platform'];
    final secret = m['secret'];
    if (id is! String || id != expectedPeerId) return;
    if (name is! String || platform is! String) return;
    if (secret is! String || !RegExp(r'^[0-9a-f]{64}$').hasMatch(secret)) return;
    _trust.rememberKey(
      id: id,
      name: name.length > 40 ? name.substring(0, 40) : name,
      platform: platform.length > 16 ? platform.substring(0, 16) : platform,
      secret: secret,
    );
  }

  // ---------- Remote control ----------

  /// Sharer: turn remote control of this device on or off.
  Future<void> setControlAllowed(bool allowed) async {
    controlAllowed.value = allowed;
    if (!allowed) await _injector?.reset();
    await _checkControl(force: true);
  }

  /// Sharer: opens the OS setting that allows BeamX to control this device.
  Future<void> openControlSettings() async =>
      _injector?.openPermissionSettings();

  bool? _lastSentAllowed;

  Future<void> _checkControl({bool force = false}) async {
    if (!isSharer || _closed || !ready.value) return;
    final inj = _injector;
    _injectorReady = inj != null && await inj.isReady();
    controlProblem.value = !controlAllowed.value
        ? null
        : inj == null
            ? 'This device can\'t be controlled remotely.'
            : _injectorReady
                ? null
                : inj.permissionHelp;
    final effective = controlAllowed.value && _injectorReady;
    if (force || effective != _lastSentAllowed) {
      _lastSentAllowed = effective;
      await _sendJson({
        't': 'control',
        'allowed': effective,
        'platform': DiscoveryService.platform,
      });
    }
  }

  Future<void> _onInput(Map<dynamic, dynamic> m) async {
    final inj = _injector;
    if (!controlAllowed.value || !_injectorReady || inj == null) return;
    final input = RemoteInput.parse(m);
    if (input != null) await inj.handle(input);
  }

  /// Viewer: sends one input event. Ignored unless control is allowed.
  void sendInput(Map<String, Object> event) {
    if (isSharer || !remote.value.allowed) return;
    _sendJson({'t': 'in', ...event});
  }

  // ---------- Clipboard ----------

  bool get _clipOut {
    final c = _settings.value.clipboardSync;
    return c == ClipboardSync.both || c == ClipboardSync.fromThisDevice;
  }

  bool get _clipIn {
    final c = _settings.value.clipboardSync;
    return c == ClipboardSync.both || c == ClipboardSync.toThisDevice;
  }

  Future<void> _pollClipboard() async {
    if (!_clipOut || !ready.value) return;
    try {
      final text = (await Clipboard.getData(Clipboard.kTextPlain))?.text;
      if (text == null || text.isEmpty || text == _lastClip) return;
      // The first read only records what's already there.
      final first = _lastClip == null;
      _lastClip = text;
      if (first || text.length > _maxText) return;
      await _sendJson({'t': 'clip', 'text': text});
    } catch (_) {}
  }

  void _onClip(Object? text) {
    if (!_clipIn || text is! String || text.length > _maxText) return;
    _lastClip = text;
    Clipboard.setData(ClipboardData(text: text));
  }

  // ---------- Sending files ----------

  /// Opens the system file picker and sends the chosen files.
  Future<void> pickAndSend() async {
    final files = await FilePicker.pickFiles();
    if (files.isEmpty) return;
    _queue.addAll(files.map(_OutFile.picked));
    _pumpQueue();
  }

  /// Sends files from disk, e.g. dragged onto the window.
  void sendPaths(List<String> paths) {
    _queue.addAll(paths.map(_OutFile.path));
    _pumpQueue();
  }

  Future<void> _pumpQueue() async {
    if (_sending || !ready.value) return;
    _sending = true;
    try {
      while (_queue.isNotEmpty && ready.value && !_closed) {
        await _sendOne(_queue.removeAt(0));
      }
    } finally {
      _sending = false;
    }
  }

  Future<void> _sendOne(_OutFile f) async {
    final size = await f.length() ?? 0;
    final id = TrustStore.randomHex(8);
    final item = TransferItem(
      id: id,
      name: f.name,
      size: size,
      direction: TransferDirection.outgoing,
      peer: peerName,
    );
    _transfers.add(item);
    if (size > maxFileSize) {
      _finish(item, TransferStatus.failed, 'Files over 4 GB are not supported');
      return;
    }

    final answer = Completer<bool>();
    _answers[id] = answer;
    await _sendJson({'t': 'file-offer', 'id': id, 'name': f.name, 'size': size});
    final ok = await answer.future
        .timeout(const Duration(seconds: 120), onTimeout: () => false);
    if (!ok) {
      _finish(item, TransferStatus.declined, null);
      return;
    }

    item.status = TransferStatus.active;
    _outgoing = item;
    _transfers.changed();
    try {
      var lastUi = DateTime.now();
      await for (final chunk in f.read()) {
        final data = chunk is Uint8List ? chunk : Uint8List.fromList(chunk);
        for (var o = 0; o < data.length; o += _chunk) {
          if (_closed || !ready.value) throw StateError('Connection closed');
          final end = o + _chunk > data.length ? data.length : o + _chunk;
          await _waitForBuffer();
          await _dc!.send(RTCDataChannelMessage.fromBinary(
              Uint8List.sublistView(data, o, end)));
          item.transferred += end - o;
          if (DateTime.now().difference(lastUi).inMilliseconds > 200) {
            lastUi = DateTime.now();
            _transfers.changed();
          }
        }
      }
      await _sendJson({'t': 'file-done', 'id': id});
      _finish(item, TransferStatus.done, null);
    } catch (e) {
      await _sendJson({'t': 'file-cancel', 'id': id, 'reason': 'Sending failed'});
      _finish(item, TransferStatus.failed, '$e');
    } finally {
      _outgoing = null;
    }
  }

  /// Keeps the send buffer small so memory use stays low and the video
  /// isn't starved.
  Future<void> _waitForBuffer() async {
    var waited = 0;
    while ((_dc?.bufferedAmount ?? 0) > _maxBuffered && waited < 30000) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
      waited += 20;
    }
  }

  // ---------- Receiving files ----------

  Future<void> _onFileOffer(Map<dynamic, dynamic> m) async {
    final id = m['id'], name = m['name'], size = m['size'];
    if (id is! String || id.length > 32 || name is! String || size is! int) return;
    if (size < 0 || size > maxFileSize || _incoming != null) {
      await _sendJson({'t': 'file-answer', 'id': id, 'ok': false});
      return;
    }
    final safe = safeFileName(name);
    final ok = await Prompts.confirmIncomingFile(from: peerName, name: safe, size: size);
    if (!ok || _closed) {
      await _sendJson({'t': 'file-answer', 'id': id, 'ok': false});
      return;
    }
    try {
      final dir = await SaveLocation.dir();
      final file = await SaveLocation.uniqueFile(dir, safe);
      _sink = file.openWrite();
      _file = file;
      final item = TransferItem(
        id: id,
        name: safe,
        size: size,
        direction: TransferDirection.incoming,
        peer: peerName,
      )
        ..status = TransferStatus.active
        ..path = file.path;
      _incoming = item;
      _transfers.add(item);
      await _sendJson({'t': 'file-answer', 'id': id, 'ok': true});
    } catch (e) {
      await _sendJson({'t': 'file-answer', 'id': id, 'ok': false});
    }
  }

  DateTime _lastRecvUi = DateTime.now();

  Future<void> _onChunk(Uint8List data) async {
    final item = _incoming;
    final sink = _sink;
    if (item == null || sink == null) return;
    if (item.transferred + data.length > item.size) {
      await _sendJson({'t': 'file-cancel', 'id': item.id, 'reason': 'Too much data'});
      await _failIncoming('Received more data than announced');
      return;
    }
    sink.add(data);
    item.transferred += data.length;
    if (DateTime.now().difference(_lastRecvUi).inMilliseconds > 200) {
      _lastRecvUi = DateTime.now();
      _transfers.changed();
    }
  }

  Future<void> _onFileDone(Object? id) async {
    final item = _incoming;
    if (item == null || id != item.id) return;
    if (item.transferred != item.size) {
      await _failIncoming('File is incomplete');
      return;
    }
    await _sink?.flush();
    await _sink?.close();
    _sink = null;
    _file = null;
    _incoming = null;
    _finish(item, TransferStatus.done, null);
  }

  Future<void> _failIncoming(String reason) async {
    final item = _incoming;
    if (item == null) return;
    _incoming = null;
    try {
      await _sink?.close();
      await _file?.delete();
    } catch (_) {}
    _sink = null;
    _file = null;
    item.path = null;
    _finish(item, TransferStatus.failed, reason);
  }

  void _finish(TransferItem item, TransferStatus status, String? error) {
    item.status = status;
    item.error = error;
    _transfers.changed();
  }

  /// Keeps only a plain file name: no folders, control or reserved characters.
  @visibleForTesting
  static String safeFileName(String name) {
    var n = name.split(RegExp(r'[\\/]')).last;
    n = n.replaceAll(RegExp(r'[\u0000-\u001F\u007F<>:"|?*]'), '_').trim();
    n = n.replaceAll(RegExp(r'^[.\s]+'), '');
    if (n.length > 120) {
      final dot = n.lastIndexOf('.');
      final ext = dot > 0 && n.length - dot <= 10 ? n.substring(dot) : '';
      n = n.substring(0, 120 - ext.length) + ext;
    }
    return n.isEmpty ? 'file' : n;
  }


  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    ready.value = false;
    _clipTimer?.cancel();
    _controlTimer?.cancel();
    await _injector?.reset();
    for (final c in _answers.values) {
      if (!c.isCompleted) c.complete(false);
    }
    _answers.clear();
    for (final f in _queue) {
      final item = TransferItem(
          id: TrustStore.randomHex(8),
          name: f.name,
          size: 0,
          direction: TransferDirection.outgoing,
          peer: peerName);
      _transfers.add(item);
      _finish(item, TransferStatus.failed, 'Disconnected before sending');
    }
    _queue.clear();
    final out = _outgoing;
    if (out != null) _finish(out, TransferStatus.failed, 'Disconnected');
    await _failIncoming('Disconnected');
    try {
      await _dc?.close();
    } catch (_) {}
  }
}

/// What the viewer knows about remote control of the sharing device.
@immutable
class RemoteControlStatus {
  const RemoteControlStatus({required this.allowed, required this.platform});
  final bool allowed;

  /// The sharing device's platform: windows, macos, linux or android.
  final String platform;
}

/// A file to send: picked with the file picker, or a path on disk.
class _OutFile {
  _OutFile(this.name, this.length, this.read);

  factory _OutFile.picked(PlatformFile f) =>
      _OutFile(f.name, f.length, f.readAsByteStream);

  factory _OutFile.path(String p) {
    final f = File(p);
    return _OutFile(
      p.split(RegExp(r'[\\/]')).last,
      () async {
        try {
          return await f.length();
        } catch (_) {
          return null;
        }
      },
      f.openRead,
    );
  }

  final String name;
  final Future<int?> Function() length;
  final Stream<List<int>> Function() read;
}
