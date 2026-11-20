import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../models/settings.dart';
import 'data_link.dart';
import 'diag_log.dart';
import 'pairing_service.dart';
import 'save_location.dart';
import 'screen_capture.dart';
import 'signaling.dart';

enum SessionRole { sharer, viewer }

enum SessionPhase { connecting, live, ended }

/// The quality the viewer asks for. The sharing device applies it.
@immutable
class StreamQuality {
  const StreamQuality({
    required this.resolution,
    required this.fps,
    required this.autoBitrate,
    required this.mbps,
    required this.codec,
    required this.audio,
  });

  factory StreamQuality.fromSettings(BeamSettings s) => StreamQuality(
        resolution: s.resolution,
        fps: s.fps,
        autoBitrate: s.autoBitrate,
        mbps: s.bitrateMbps,
        codec: s.codec,
        audio: s.audioEnabled && s.audioOutput != AudioOutput.sender,
      );

  /// Parses untrusted input, clamping every value to a safe range.
  factory StreamQuality.fromJson(Object? j, StreamQuality fallback) {
    if (j is! Map) return fallback;
    int asInt(Object? v, int d, int lo, int hi) =>
        v is num ? v.round().clamp(lo, hi).toInt() : d;
    final codec = VideoCodec.values
        .where((c) => c.name == j['codec'])
        .firstOrNull;
    return StreamQuality(
      resolution: asInt(j['resolution'], fallback.resolution, 360, 2160),
      fps: asInt(j['fps'], fallback.fps, 10, 120),
      autoBitrate:
          j['autoBitrate'] is bool ? j['autoBitrate'] as bool : fallback.autoBitrate,
      mbps: j['mbps'] is num
          ? (j['mbps'] as num).toDouble().clamp(1, 80).toDouble()
          : fallback.mbps,
      codec: codec ?? fallback.codec,
      audio: j['audio'] is bool ? j['audio'] as bool : fallback.audio,
    );
  }

  final int resolution;
  final int fps;
  final bool autoBitrate;
  final double mbps;
  final VideoCodec codec;

  /// Whether the viewer wants the shared device's sound.
  final bool audio;

  Map<String, Object> toJson() => {
        'resolution': resolution,
        'fps': fps,
        'autoBitrate': autoBitrate,
        'mbps': mbps,
        'codec': codec.name,
        'audio': audio,
      };

  @override
  bool operator ==(Object other) =>
      other is StreamQuality &&
      other.resolution == resolution &&
      other.fps == fps &&
      other.autoBitrate == autoBitrate &&
      other.mbps == mbps &&
      other.codec == codec &&
      other.audio == audio;

  @override
  int get hashCode =>
      Object.hash(resolution, fps, autoBitrate, mbps, codec, audio);
}

/// Live numbers measured from WebRTC, shown in the stats overlay.
@immutable
class StreamStats {
  const StreamStats({
    this.fps,
    this.width,
    this.height,
    this.kbps,
    this.rttMs,
    this.codec,
  });

  final double? fps;
  final int? width;
  final int? height;
  final double? kbps;
  final double? rttMs;
  final String? codec;
}

/// One live screen-sharing connection with another device.
///
/// The sharing device captures its screen and sends the WebRTC offer; the
/// viewing device answers and shows the video. Media is end-to-end
/// encrypted by WebRTC (DTLS-SRTP). Offers and answers are authenticated
/// with the pairing code so they can't be swapped by another device.
class BeamSession extends ChangeNotifier {
  BeamSession({
    required this.role,
    required this.peerName,
    required this._channel,
    required this._code,
    required this._quality,
    required this.link,
    this.iceServers = const [],
    this.wantMic = false,
  });

  /// Viewer: send this device's microphone to the sharing device.
  final bool wantMic;

  /// STUN/TURN servers. Empty on the local network (direct connections).
  final List<Map<String, dynamic>> iceServers;

  /// Files, clipboard and trust keys for this session.
  final DataLink link;

  final SessionRole role;
  final String peerName;
  final SignalingChannel _channel;
  final String _code;
  StreamQuality _quality;

  RTCPeerConnection? _pc;
  MediaStream? _localStream;
  RTCRtpSender? _sender;
  final RTCVideoRenderer renderer = RTCVideoRenderer();
  final List<RTCIceCandidate> _pendingIce = [];
  bool _remoteSet = false;
  Timer? _statsTimer;
  StreamSubscription<Map<String, dynamic>>? _messages;
  /// The captured screen's short side in pixels (e.g. 1080 for a
  /// 2400×1080 phone or a 1920×1080 PC), learned from the local preview.
  int? _sourceShortSide;
  double _scale = 1;
  int? _lastBytes;
  double? _lastTimestamp;

  SessionPhase phase = SessionPhase.connecting;

  /// True while the connection is interrupted and BeamX is trying to
  /// restore it.
  bool reconnecting = false;
  Timer? _graceTimer;
  bool _everConnected = false;

  /// How long to keep trying after the connection drops.
  static const _grace = Duration(seconds: 30);

  // Sound
  final List<MediaStreamTrack> _remoteAudio = [];
  bool _muted = false;

  // Microphone (viewer → sharer)
  MediaStream? _mic;
  bool _micOn = true;

  /// Viewer: whether the microphone is being sent.
  bool get micAttached => _mic != null;
  bool get micOn => _micOn;

  void setMicOn(bool on) {
    _micOn = on;
    for (final t in _mic?.getAudioTracks() ?? <MediaStreamTrack>[]) {
      t.enabled = on;
    }
    notifyListeners();
  }

  /// Puts the microphone on the offer's receive-only audio slot.
  Future<void> _attachMic(RTCPeerConnection pc, String offerSdp) async {
    try {
      // Find the mid of the audio section the sharer offered as recvonly.
      String? mid;
      for (final section in offerSdp.split(RegExp(r'\r?\nm=')).skip(1)) {
        if (!section.startsWith('audio') || !section.contains('a=recvonly')) continue;
        mid = RegExp(r'a=mid:(\S+)').firstMatch(section)?.group(1);
      }
      if (mid == null) return; // older BeamX on the other side
      final mic = await navigator.mediaDevices.getUserMedia(<String, dynamic>{
        'audio': {'echoCancellation': true, 'noiseSuppression': true},
        'video': false,
      });
      for (final t in await pc.getTransceivers()) {
        if (t.mid == mid) {
          await t.sender.replaceTrack(mic.getAudioTracks().first);
          await t.setDirection(TransceiverDirection.SendOnly);
          _mic = mic;
          DiagLog.add('microphone shared');
          notifyListeners();
          return;
        }
      }
      await mic.dispose();
    } catch (e) {
      DiagLog.add('microphone not shared: $e');
    }
  }

  // Screenshots and recording (viewer)
  MediaStreamTrack? _remoteVideo;
  MediaRecorder? _recorder;
  String? _recordingPath;

  /// Video recording works on Android, iPhone/iPad and Mac.
  static bool get recordingSupported =>
      Platform.isAndroid || Platform.isIOS || Platform.isMacOS;

  bool get canCapture => !isSharer && _remoteVideo != null;
  bool get recording => _recorder != null;

  /// Viewer: saves the current picture as a PNG. Returns the file path.
  Future<String> screenshot() async {
    final track = _remoteVideo;
    if (track == null) throw StateError('No video yet');
    final bytes = await track.captureFrame();
    final file = await SaveLocation.uniqueFile(
        await SaveLocation.dir(), SaveLocation.timestamped(peerName, 'png'));
    await file.writeAsBytes(bytes.asUint8List(), flush: true);
    return file.path;
  }

  /// Viewer: starts recording the stream (with sound on Android) to MP4.
  Future<void> startRecording() async {
    final track = _remoteVideo;
    if (track == null || _recorder != null) return;
    final file = await SaveLocation.uniqueFile(
        await SaveLocation.dir(), SaveLocation.timestamped(peerName, 'mp4'));
    final r = MediaRecorder();
    await r.start(
      file.path,
      videoTrack: track,
      audioChannel: Platform.isAndroid && receivingAudio
          ? RecorderAudioChannel.OUTPUT
          : null,
    );
    _recorder = r;
    _recordingPath = file.path;
    notifyListeners();
  }

  /// Viewer: stops recording. Returns the saved file path.
  Future<String?> stopRecording() async {
    final r = _recorder;
    if (r == null) return null;
    _recorder = null;
    notifyListeners();
    try {
      await r.stop();
    } catch (_) {}
    return _recordingPath;
  }

  /// Sharer: whether this device's sound is being sent.
  bool sendingAudio = false;

  /// Viewer: whether sound is arriving from the other device.
  bool get receivingAudio => _remoteAudio.isNotEmpty;
  bool get muted => _muted;

  /// Viewer: mutes or unmutes the other device's sound on this device.
  void setMuted(bool muted) {
    _muted = muted;
    for (final t in _remoteAudio) {
      t.enabled = !muted;
    }
    notifyListeners();
  }
  String? endReason;
  final ValueNotifier<StreamStats> stats = ValueNotifier(const StreamStats());
  final _ended = Completer<String>();

  /// Completes with a reason when the session ends.
  Future<String> get ended => _ended.future;
  bool get isSharer => role == SessionRole.sharer;
  StreamQuality get quality => _quality;

  Future<void> start() async {
    try {
      await renderer.initialize();
      final pc = await createPeerConnection(<String, dynamic>{
        // Local network: none, so no outside server is contacted.
        // Internet: the relay's STUN and TURN servers.
        'iceServers': iceServers,
        'sdpSemantics': 'unified-plan',
      });
      _pc = pc;

      pc.onIceCandidate = (c) {
        if (c.candidate == null) return;
        _channel.send({
          't': 'ice',
          'candidate': c.candidate,
          'sdpMid': c.sdpMid,
          'sdpMLineIndex': c.sdpMLineIndex,
        });
      };
      pc.onConnectionState = (s) {
        DiagLog.add('webrtc state: ${s.name}');
        switch (s) {
          case RTCPeerConnectionState.RTCPeerConnectionStateConnected:
            _recovered();
          case RTCPeerConnectionState.RTCPeerConnectionStateDisconnected:
            _interrupted(restart: false);
          case RTCPeerConnectionState.RTCPeerConnectionStateFailed:
            _interrupted(restart: true);
          case RTCPeerConnectionState.RTCPeerConnectionStateClosed:
            if (_everConnected) close('Connection closed');
          default:
            break;
        }
      };
      pc.onIceConnectionState = (s) => DiagLog.add('ice state: ${s.name}');
      pc.onDataChannel = (dc) {
        if (dc.label == 'beamx') link.attach(dc);
        if (dc.label == 'beamx-input') link.attachInput(dc);
      };
      pc.onTrack = (e) {
        if (e.track.kind == 'audio') {
          _remoteAudio.add(e.track);
          e.track.enabled = !_muted;
          notifyListeners();
        }
        if (e.track.kind == 'video') _remoteVideo = e.track;
        if (e.track.kind == 'video' && e.streams.isNotEmpty) {
          renderer.srcObject = e.streams.first;
          notifyListeners();
        }
      };

      // Messages from the other device can also arrive over the data
      // channel, which keeps working if the setup connection drops.
      link.onSessionMessage = _onMessage;
      _messages = _channel.rest().listen(_onMessage, onDone: _signalingLost);
      unawaited(_channel.closed.then((_) => _signalingLost()));

      if (isSharer) await _startSharing(pc);
      _statsTimer =
          Timer.periodic(const Duration(seconds: 1), (_) => _pollStats());
    } catch (e) {
      close(e is CaptureDenied ? e.toString() : 'Could not start: $e');
    }
  }

  Future<void> _startSharing(RTCPeerConnection pc) async {
    final stream = await ScreenCapture.start(
        fps: _quality.fps, audio: _quality.audio);
    _localStream = stream;
    renderer.srcObject = stream; // local preview
    final track = stream.getVideoTracks().first;
    track.onEnded = () => close('Screen sharing was stopped');
    _sender = await pc.addTrack(track, stream);
    for (final a in stream.getAudioTracks()) {
      await pc.addTrack(a, stream);
    }
    sendingAudio = stream.getAudioTracks().isNotEmpty;
    await _preferCodec(pc, _quality.codec);
    link.attach(await pc.createDataChannel(
        'beamx', RTCDataChannelInit()..ordered = true));
    link.attachInput(await pc.createDataChannel(
        'beamx-input', RTCDataChannelInit()..ordered = true));
    // A receive-only audio slot, so the viewer can send its microphone.
    await pc.addTransceiver(
      kind: RTCRtpMediaType.RTCRtpMediaTypeAudio,
      init: RTCRtpTransceiverInit(direction: TransceiverDirection.RecvOnly),
    );

    final offer = await pc.createOffer();
    await pc.setLocalDescription(offer);
    _channel.send({
      't': 'offer',
      'sdp': offer.sdp,
      'mac': PairingService.mac(_code, offer.sdp ?? ''),
    });
    await _applyEncoding();
  }

  /// The setup connection closed. Before the video connects that ends the
  /// session; afterwards it's not needed, so streaming carries on.
  void _signalingLost() {
    if (phase == SessionPhase.ended) return;
    DiagLog.add('setup connection closed (${_everConnected ? 'stream continues' : 'before connecting'})');
    if (!_everConnected) close('The other device disconnected');
  }

  void _recovered() {
    _everConnected = true;
    _graceTimer?.cancel();
    _graceTimer = null;
    if (reconnecting) DiagLog.add('reconnected');
    reconnecting = false;
    if (phase == SessionPhase.live) {
      notifyListeners();
    } else {
      _setPhase(SessionPhase.live);
    }
  }

  /// The network dropped. Keep the session for [_grace] while WebRTC
  /// reconnects; on failure the sharing side also restarts ICE so a new
  /// network path (e.g. Wi-Fi → mobile data) can be found.
  void _interrupted({required bool restart}) {
    if (phase == SessionPhase.ended) return;
    if (!_everConnected) {
      if (restart) close('Could not connect. The devices may be on networks that block direct connections.');
      return;
    }
    if (!reconnecting) {
      reconnecting = true;
      notifyListeners();
    }
    _graceTimer ??= Timer(_grace, () => close('Connection lost'));
    if (restart && isSharer) unawaited(_restartIce());
  }

  Future<void> _restartIce() async {
    final pc = _pc;
    if (pc == null || _channel.isClosed) {
      DiagLog.add('ice restart skipped: setup connection closed');
      return;
    }
    try {
      DiagLog.add('ice restart');
      final offer = await pc.createOffer({'iceRestart': true});
      await pc.setLocalDescription(offer);
      _channel.send({
        't': 'offer',
        'sdp': offer.sdp,
        'mac': PairingService.mac(_code, offer.sdp ?? ''),
      });
    } catch (e) {
      DiagLog.add('ice restart failed: $e');
    }
  }

  Future<void> _onMessage(Map<String, dynamic> m) async {
    final pc = _pc;
    if (pc == null || phase == SessionPhase.ended) return;
    try {
      switch (m['t']) {
        case 'offer' when !isSharer:
          final sdp = _verifiedSdp(m);
          await pc.setRemoteDescription(RTCSessionDescription(sdp, 'offer'));
          await _flushIce(pc);
          if (wantMic && _mic == null) await _attachMic(pc, sdp);
          final answer = await pc.createAnswer();
          await pc.setLocalDescription(answer);
          _channel.send({
            't': 'answer',
            'sdp': answer.sdp,
            'mac': PairingService.mac(_code, answer.sdp ?? ''),
          });
        case 'answer' when isSharer:
          final sdp = _boostStartBitrate(_verifiedSdp(m));
          await pc.setRemoteDescription(RTCSessionDescription(sdp, 'answer'));
          await _flushIce(pc);
        case 'ice':
          final c = m['candidate'];
          final mid = m['sdpMid'];
          final idx = m['sdpMLineIndex'];
          if (c is! String || c.length > 1024) return;
          final cand = RTCIceCandidate(
              c, mid is String ? mid : null, idx is int ? idx : null);
          if (_remoteSet) {
            await pc.addCandidate(cand);
          } else if (_pendingIce.length < 100) {
            _pendingIce.add(cand);
          }
        case 'quality' when isSharer && m['quality'] is Map:
          _quality = StreamQuality.fromJson(m['quality'], _quality);
          await _applyEncoding();
          notifyListeners();
        case 'bye':
          close('The other device ended the session');
      }
    } on SignalingException catch (e) {
      close(e.message);
    } catch (e) {
      debugPrint('BeamX session message error: $e');
    }
  }

  String _verifiedSdp(Map<String, dynamic> m) {
    final sdp = m['sdp'];
    final mac = m['mac'];
    if (sdp is! String ||
        mac is! String ||
        !PairingService.constantTimeEquals(PairingService.mac(_code, sdp), mac)) {
      throw SignalingException('Security check failed: connection rejected');
    }
    return sdp;
  }

  Future<void> _flushIce(RTCPeerConnection pc) async {
    _remoteSet = true;
    for (final c in _pendingIce) {
      await pc.addCandidate(c);
    }
    _pendingIce.clear();
  }

  /// Puts the chosen codec first; the others stay as fallbacks in case the
  /// viewing device can't decode it.
  Future<void> _preferCodec(RTCPeerConnection pc, VideoCodec codec) async {
    final mime = switch (codec) {
      VideoCodec.h264 => 'video/h264',
      VideoCodec.h265 => 'video/h265',
      VideoCodec.av1 => 'video/av1',
    };
    try {
      final caps = await getRtpSenderCapabilities('video');
      final all = caps.codecs ?? [];
      final preferred =
          all.where((c) => c.mimeType.toLowerCase() == mime).toList();
      if (preferred.isEmpty) return;
      final others =
          all.where((c) => c.mimeType.toLowerCase() != mime).toList();
      for (final t in await pc.getTransceivers()) {
        if (t.sender.senderId == _sender?.senderId) {
          await t.setCodecPreferences([...preferred, ...others]);
        }
      }
    } catch (e) {
      debugPrint('BeamX: codec preference not supported here ($e)');
    }
  }

  /// Applies frame rate, bitrate and resolution limits to the outgoing video.
  Future<void> _applyEncoding() async {
    final sender = _sender;
    if (sender == null) return;
    final q = _quality;
    // "1080p" means the short side, so a portrait phone (1080×2400) stays
    // sharp. Scaling by the height used to shrink phones to ~486 px wide.
    final short = _sourceShortSide;
    if (short != null && short > 0) {
      _scale = (short / q.resolution).clamp(1.0, 8.0);
    }
    try {
      final params = sender.parameters;
      final encodings = params.encodings;
      if (encodings == null || encodings.isEmpty) {
        params.encodings = [RTCRtpEncoding()];
      }
      final e = params.encodings!.first;
      e.maxFramerate = q.fps;
      // Without a limit, WebRTC caps screen sharing at ~2.5 Mbps, which made
      // the picture blurry and the frame rate drop. Auto now allows enough
      // for sharp text, and congestion control still lowers it on weak
      // networks.
      e.maxBitrate = (q.autoBitrate ? autoMaxBitrate(q) : q.mbps * 1000000).round();
      e.scaleResolutionDownBy = _scale;
      // Screens default to "keep resolution, drop frames", which felt laggy.
      // Smooth profiles keep the frame rate; others balance both.
      params.degradationPreference = q.fps >= 60
          ? RTCDegradationPreference.MAINTAIN_FRAMERATE
          : RTCDegradationPreference.BALANCED;
      await sender.setParameters(params);
      DiagLog.add('encoding: short side ${short ?? '?'} → ${q.resolution}p '
          '(scale ${_scale.toStringAsFixed(2)}), ${q.fps} FPS, '
          'max ${(e.maxBitrate! / 1e6).toStringAsFixed(1)} Mbps');
    } catch (err) {
      debugPrint('BeamX: could not apply encoding ($err)');
    }
  }

  /// Bitrate ceiling for automatic mode: about 0.1 bits per pixel per frame,
  /// e.g. 1080p30 ≈ 8 Mbps, 1080p60 ≈ 14 Mbps, 4K30 ≈ 30 Mbps.
  static double autoMaxBitrate(StreamQuality q) {
    final h = q.resolution.toDouble();
    final pixels = h * h * 16 / 9;
    final fpsFactor = q.fps <= 30 ? q.fps : 30 + (q.fps - 30) * 0.6;
    return (pixels * fpsFactor * 0.13).clamp(2e6, 60e6);
  }

  /// Starts the encoder near its target instead of WebRTC's slow ~300 kbps
  /// ramp-up, which made the first seconds blurry. Applied to the remote
  /// answer locally, after its authenticity check.
  String _boostStartBitrate(String sdp) {
    final maxKbps = (autoMaxBitrate(_quality) / 1000).round();
    final startKbps = iceServers.isEmpty ? (maxKbps * 0.6).round() : 2500;
    final minKbps = iceServers.isEmpty ? 1500 : 300;
    final lines = sdp.split('\r\n');
    final video = <String>{};
    var inVideo = false;
    for (final l in lines) {
      if (l.startsWith('m=')) inVideo = l.startsWith('m=video');
      final m = RegExp(r'^a=rtpmap:(\d+) (H264|VP8|VP9|AV1|H265)/').firstMatch(l);
      if (inVideo && m != null) video.add(m.group(1)!);
    }
    final extra = 'x-google-start-bitrate=$startKbps;x-google-min-bitrate=$minKbps;'
        'x-google-max-bitrate=$maxKbps';
    final out = <String>[];
    final hasFmtp = <String>{};
    for (final l in lines) {
      final m = RegExp(r'^a=fmtp:(\d+) ').firstMatch(l);
      if (m != null && video.contains(m.group(1)) && !l.contains('x-google-start-bitrate')) {
        hasFmtp.add(m.group(1)!);
        out.add('$l;$extra');
      } else {
        out.add(l);
      }
    }
    // Codecs without an fmtp line (e.g. VP8) get one after their rtpmap.
    final result = <String>[];
    for (final l in out) {
      result.add(l);
      final m = RegExp(r'^a=rtpmap:(\d+) ').firstMatch(l);
      if (m != null && video.contains(m.group(1)) && !hasFmtp.contains(m.group(1))) {
        result.add('a=fmtp:${m.group(1)} $extra');
      }
    }
    return result.join('\r\n');
  }

  /// Viewer side: ask the sharing device for a new quality.
  void requestQuality(StreamQuality q) {
    if (isSharer || q == _quality) return;
    _quality = q;
    _sendSession({'t': 'quality', 'quality': q.toJson()});
  }

  /// Sends a session message over the data channel when it's open (it
  /// survives a dropped setup connection), otherwise over the setup channel.
  void _sendSession(Map<String, Object?> m) {
    if (link.ready.value) {
      link.sendSessionMessage(m);
    } else {
      _channel.send(m);
    }
  }

  Future<void> _pollStats() async {
    final pc = _pc;
    if (pc == null || phase == SessionPhase.ended) return;
    try {
      final reports = await pc.getStats();
      final rtpType = isSharer ? 'outbound-rtp' : 'inbound-rtp';
      double? fps, rtt;
      int? w, h, bytes;
      String? codecId;
      double? ts;
      final codecs = <String, String>{};
      for (final r in reports) {
        final v = r.values;
        if (r.type == 'codec') {
          codecs[r.id] = '${v['mimeType'] ?? ''}'.replaceFirst('video/', '');
        } else if (r.type == rtpType &&
            (v['kind'] == 'video' || v['mediaType'] == 'video')) {
          fps = _num(v['framesPerSecond'])?.toDouble();
          w = _num(v['frameWidth'])?.toInt();
          h = _num(v['frameHeight'])?.toInt();
          bytes = _num(isSharer ? v['bytesSent'] : v['bytesReceived'])?.toInt();
          codecId = v['codecId']?.toString();
          ts = r.timestamp;
        } else if (r.type == 'candidate-pair' &&
            (v['nominated'] == true || v['nominated'] == 'true') &&
            v['state'] == 'succeeded') {
          final s = _num(v['currentRoundTripTime']);
          if (s != null) rtt = s * 1000;
        }
      }

      double? kbps;
      if (bytes != null && ts != null && _lastBytes != null && _lastTimestamp != null) {
        // Timestamps are in milliseconds on most platforms, microseconds on some.
        var dt = ts - _lastTimestamp!;
        if (dt > 100000) dt /= 1000;
        if (dt > 0) kbps = (bytes - _lastBytes!) * 8 / dt;
      }
      _lastBytes = bytes;
      _lastTimestamp = ts;

      // Learn the real screen height once, then scale to the target.
      // Learn the real screen size once from the local preview (the
      // captured frames), then scale to the target.
      if (isSharer && _sourceShortSide == null) {
        final vw = renderer.videoWidth, vh = renderer.videoHeight;
        if (vw > 0 && vh > 0) {
          _sourceShortSide = vw < vh ? vw : vh;
          DiagLog.add('capturing ${vw}x$vh');
          await _applyEncoding();
        }
      }

      stats.value = StreamStats(
        fps: fps,
        width: w,
        height: h,
        kbps: kbps,
        rttMs: rtt,
        codec: codecId == null ? null : codecs[codecId],
      );
    } catch (_) {
      // Stats are best-effort.
    }
  }

  static num? _num(Object? v) => v is num ? v : num.tryParse('$v');

  void _setPhase(SessionPhase p) {
    if (phase == p || phase == SessionPhase.ended) return;
    phase = p;
    notifyListeners();
  }

  /// Ends the session and releases the camera/screen, renderer and network.
  Future<void> close([String reason = 'Session ended']) async {
    if (phase == SessionPhase.ended) return;
    phase = SessionPhase.ended;
    endReason = reason;
    DiagLog.add('session ended: $reason');
    _statsTimer?.cancel();
    _graceTimer?.cancel();
    if (link.ready.value) link.sendSessionMessage({'t': 'bye'});
    _channel.send({'t': 'bye'});
    _channel.close(reason);
    await _messages?.cancel();
    await stopRecording();
    await link.close();
    try {
      for (final t in [
        ...?_localStream?.getTracks(),
        ...?_mic?.getTracks(),
      ]) {
        await t.stop();
      }
      await _mic?.dispose();
      await _localStream?.dispose();
      renderer.srcObject = null;
      await _pc?.close();
      await _pc?.dispose();
      await renderer.dispose();
    } catch (_) {}
    if (isSharer) await ScreenCapture.stopService();
    if (!_ended.isCompleted) _ended.complete(reason);
    notifyListeners();
  }
}
