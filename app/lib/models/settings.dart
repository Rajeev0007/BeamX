import 'package:material_ui/material_ui.dart';

enum ConnectionMode { auto, usb, wifi, hotspot, internet }

enum VideoCodec { h264, h265, av1 }

enum Encoder { gpu, cpu }

enum AudioOutput { receiver, sender, both }

enum ClipboardSync { off, both, toThisDevice, fromThisDevice }

extension ConnectionModeLabel on ConnectionMode {
  String get label => switch (this) {
        ConnectionMode.auto => 'Auto (best available)',
        ConnectionMode.usb => 'USB cable',
        ConnectionMode.wifi => 'Same Wi-Fi',
        ConnectionMode.hotspot => 'Hotspot / Wi-Fi Direct',
        ConnectionMode.internet => 'Internet (anywhere)',
      };
}

extension VideoCodecLabel on VideoCodec {
  String get label => switch (this) {
        VideoCodec.h264 => 'H.264 (most compatible)',
        VideoCodec.h265 => 'H.265 (better quality)',
        VideoCodec.av1 => 'AV1 (best quality, newer devices)',
      };
}

extension AudioOutputLabel on AudioOutput {
  String get label => switch (this) {
        AudioOutput.receiver => 'Viewing device',
        AudioOutput.sender => 'Sharing device',
        AudioOutput.both => 'Both devices',
      };
}

extension ClipboardSyncLabel on ClipboardSync {
  String get label => switch (this) {
        ClipboardSync.off => 'Off',
        ClipboardSync.both => 'Both directions',
        ClipboardSync.toThisDevice => 'Only into this device',
        ClipboardSync.fromThisDevice => 'Only from this device',
      };
}

/// Every user-adjustable option in BeamX. Immutable; use [copyWith].
@immutable
class BeamSettings {
  const BeamSettings({
    this.deviceName = 'My device',
    this.themeMode = ThemeMode.system,
    this.accentIndex = 0,
    this.resolution = 1080,
    this.fps = 60,
    this.autoBitrate = true,
    this.bitrateMbps = 12,
    this.codec = VideoCodec.h264,
    this.encoder = Encoder.gpu,
    this.audioEnabled = true,
    this.audioOutput = AudioOutput.receiver,
    this.micSharing = false,
    this.connectionMode = ConnectionMode.auto,
    this.port = 47800,
    this.signalingServer = '',
    this.autoConnectTrusted = true,
    this.pointerSpeed = 1.0,
    this.viewOnly = false,
    this.showStatsOverlay = false,
    this.screenOffWhileMirroring = false,
    this.alwaysOnTop = false,
    this.requireApproval = true,
    this.clipboardSync = ClipboardSync.both,
    this.discoverable = true,
    this.activeProfile = 'Balanced',
    this.passwordAccess = false,
    this.passwordAsk = false,
    this.passwordControl = true,
    this.internetEnabled = false,
    this.saveFolder = '',
    this.orientation = 'auto',
    this.gamepadPreset = 'arrows',
  });

  final String deviceName;
  final ThemeMode themeMode;
  final int accentIndex;

  // Streaming
  final int resolution; // vertical pixels, e.g. 1080
  final int fps;
  final bool autoBitrate;
  final double bitrateMbps;
  final VideoCodec codec;
  final Encoder encoder;

  // Audio
  final bool audioEnabled;
  final AudioOutput audioOutput;
  final bool micSharing;

  // Connection
  final ConnectionMode connectionMode;
  final int port;
  final String signalingServer;
  final bool autoConnectTrusted;

  // Control & display
  final double pointerSpeed;
  final bool viewOnly;
  final bool showStatsOverlay;
  final bool screenOffWhileMirroring;
  final bool alwaysOnTop;

  // Security & privacy
  final bool requireApproval;
  final ClipboardSync clipboardSync;
  final bool discoverable;

  final String activeProfile;

  // Access from anywhere
  /// Let devices connect with this device's ID and the owner's password.
  final bool passwordAccess;

  /// Still show the Allow prompt for password connections.
  final bool passwordAsk;

  /// Password connections may control this device.
  final bool passwordControl;

  /// Stay connected to the internet server so others can reach this device.
  final bool internetEnabled;

  /// Folder for received files, screenshots and recordings ('' = default).
  final String saveFolder;

  /// Phones: 'auto', 'portrait' or 'landscape'.
  final String orientation;

  /// Gamepad key layout: 'arrows' or 'wasd'.
  final String gamepadPreset;

  BeamSettings copyWith({
    String? deviceName,
    ThemeMode? themeMode,
    int? accentIndex,
    int? resolution,
    int? fps,
    bool? autoBitrate,
    double? bitrateMbps,
    VideoCodec? codec,
    Encoder? encoder,
    bool? audioEnabled,
    AudioOutput? audioOutput,
    bool? micSharing,
    ConnectionMode? connectionMode,
    int? port,
    String? signalingServer,
    bool? autoConnectTrusted,
    double? pointerSpeed,
    bool? viewOnly,
    bool? showStatsOverlay,
    bool? screenOffWhileMirroring,
    bool? alwaysOnTop,
    bool? requireApproval,
    ClipboardSync? clipboardSync,
    bool? discoverable,
    String? activeProfile,
    bool? passwordAccess,
    bool? passwordAsk,
    bool? passwordControl,
    bool? internetEnabled,
    String? saveFolder,
    String? orientation,
    String? gamepadPreset,
  }) {
    return BeamSettings(
      deviceName: deviceName ?? this.deviceName,
      themeMode: themeMode ?? this.themeMode,
      accentIndex: accentIndex ?? this.accentIndex,
      resolution: resolution ?? this.resolution,
      fps: fps ?? this.fps,
      autoBitrate: autoBitrate ?? this.autoBitrate,
      bitrateMbps: bitrateMbps ?? this.bitrateMbps,
      codec: codec ?? this.codec,
      encoder: encoder ?? this.encoder,
      audioEnabled: audioEnabled ?? this.audioEnabled,
      audioOutput: audioOutput ?? this.audioOutput,
      micSharing: micSharing ?? this.micSharing,
      connectionMode: connectionMode ?? this.connectionMode,
      port: port ?? this.port,
      signalingServer: signalingServer ?? this.signalingServer,
      autoConnectTrusted: autoConnectTrusted ?? this.autoConnectTrusted,
      pointerSpeed: pointerSpeed ?? this.pointerSpeed,
      viewOnly: viewOnly ?? this.viewOnly,
      showStatsOverlay: showStatsOverlay ?? this.showStatsOverlay,
      screenOffWhileMirroring:
          screenOffWhileMirroring ?? this.screenOffWhileMirroring,
      alwaysOnTop: alwaysOnTop ?? this.alwaysOnTop,
      requireApproval: requireApproval ?? this.requireApproval,
      clipboardSync: clipboardSync ?? this.clipboardSync,
      discoverable: discoverable ?? this.discoverable,
      activeProfile: activeProfile ?? this.activeProfile,
      passwordAccess: passwordAccess ?? this.passwordAccess,
      passwordAsk: passwordAsk ?? this.passwordAsk,
      passwordControl: passwordControl ?? this.passwordControl,
      internetEnabled: internetEnabled ?? this.internetEnabled,
      saveFolder: saveFolder ?? this.saveFolder,
      orientation: orientation ?? this.orientation,
      gamepadPreset: gamepadPreset ?? this.gamepadPreset,
    );
  }

  Map<String, Object> toJson() => {
        'deviceName': deviceName,
        'themeMode': themeMode.name,
        'accentIndex': accentIndex,
        'resolution': resolution,
        'fps': fps,
        'autoBitrate': autoBitrate,
        'bitrateMbps': bitrateMbps,
        'codec': codec.name,
        'encoder': encoder.name,
        'audioEnabled': audioEnabled,
        'audioOutput': audioOutput.name,
        'micSharing': micSharing,
        'connectionMode': connectionMode.name,
        'port': port,
        'signalingServer': signalingServer,
        'autoConnectTrusted': autoConnectTrusted,
        'pointerSpeed': pointerSpeed,
        'viewOnly': viewOnly,
        'showStatsOverlay': showStatsOverlay,
        'screenOffWhileMirroring': screenOffWhileMirroring,
        'alwaysOnTop': alwaysOnTop,
        'requireApproval': requireApproval,
        'clipboardSync': clipboardSync.name,
        'discoverable': discoverable,
        'activeProfile': activeProfile,
        'passwordAccess': passwordAccess,
        'passwordAsk': passwordAsk,
        'passwordControl': passwordControl,
        'internetEnabled': internetEnabled,
        'saveFolder': saveFolder,
        'orientation': orientation,
        'gamepadPreset': gamepadPreset,
      };

  /// Tolerant parser: unknown or malformed values fall back to defaults,
  /// so a corrupted or older settings file never crashes the app.
  factory BeamSettings.fromJson(Map<String, dynamic> j) {
    const d = BeamSettings();
    T pick<T>(String key, T fallback) {
      final v = j[key];
      if (v is T) return v;
      if (fallback is double && v is num) return v.toDouble() as T;
      return fallback;
    }

    E pickEnum<E extends Enum>(String key, List<E> values, E fallback) {
      final v = j[key];
      for (final e in values) {
        if (e.name == v) return e;
      }
      return fallback;
    }

    return BeamSettings(
      deviceName: pick('deviceName', d.deviceName),
      themeMode: pickEnum('themeMode', ThemeMode.values, d.themeMode),
      accentIndex: pick('accentIndex', d.accentIndex),
      resolution: pick('resolution', d.resolution),
      fps: pick('fps', d.fps),
      autoBitrate: pick('autoBitrate', d.autoBitrate),
      bitrateMbps: pick('bitrateMbps', d.bitrateMbps),
      codec: pickEnum('codec', VideoCodec.values, d.codec),
      encoder: pickEnum('encoder', Encoder.values, d.encoder),
      audioEnabled: pick('audioEnabled', d.audioEnabled),
      audioOutput: pickEnum('audioOutput', AudioOutput.values, d.audioOutput),
      micSharing: pick('micSharing', d.micSharing),
      connectionMode:
          pickEnum('connectionMode', ConnectionMode.values, d.connectionMode),
      port: pick('port', d.port),
      signalingServer: pick('signalingServer', d.signalingServer),
      autoConnectTrusted: pick('autoConnectTrusted', d.autoConnectTrusted),
      pointerSpeed: pick('pointerSpeed', d.pointerSpeed),
      viewOnly: pick('viewOnly', d.viewOnly),
      showStatsOverlay: pick('showStatsOverlay', d.showStatsOverlay),
      screenOffWhileMirroring:
          pick('screenOffWhileMirroring', d.screenOffWhileMirroring),
      alwaysOnTop: pick('alwaysOnTop', d.alwaysOnTop),
      requireApproval: pick('requireApproval', d.requireApproval),
      clipboardSync:
          pickEnum('clipboardSync', ClipboardSync.values, d.clipboardSync),
      discoverable: pick('discoverable', d.discoverable),
      activeProfile: pick('activeProfile', d.activeProfile),
      passwordAccess: pick('passwordAccess', d.passwordAccess),
      passwordAsk: pick('passwordAsk', d.passwordAsk),
      passwordControl: pick('passwordControl', d.passwordControl),
      internetEnabled: pick('internetEnabled', d.internetEnabled),
      saveFolder: pick('saveFolder', d.saveFolder),
      orientation: pick('orientation', d.orientation),
      gamepadPreset: pick('gamepadPreset', d.gamepadPreset),
    );
  }
}
