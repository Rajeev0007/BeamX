import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../models/settings.dart';
import 'pairing_service.dart';
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
  });

  factory StreamQuality.fromSettings(BeamSettings s) => StreamQuality(
        resolution: s.resolution,
        fps: s.fps,
        autoBitrate: s.autoBitrate,
        mbps: s.bitrateMbps,
        codec: s.codec,
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
    );
  }

  final int resolution;
  final int fps;
  final bool autoBitrate;
  final double mbps;
  final VideoCodec codec;

  Map<String, Object> toJson() => {
        'resolution': resolution,
        'fps': fps,
        'autoBitrate': autoBitrate,
        'mbps': mbps,
        'codec': codec.name,
      };

  @override
  bool operator ==(Object other) =>
      other is StreamQuality &&
      other.resolution == resolution &&
      other.fps == fps &&
      other.autoBitrate == autoBitrate &&
      other.mbps == mbps &&
      other.codec == codec;

  @override
  int get hashCode => Object.hash(resolution, fps, autoBitrate, mbps, codec);
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
    required SignalingChannel channel,
    required String code,
    required StreamQuality quality,
  })  : _channel = channel,
        _code = code,
        _quality = quality;

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
  int? _sourceHeight;
  double _scale = 1;
  int? _lastBytes;
  double? _lastTimestamp;

  SessionPhase phase = SessionPhase.connecting;
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
        // Local network only for now: no STUN/TURN servers are contacted.
        'iceServers': <Map<String, dynamic>>[],
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
        if (s == RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
          _setPhase(SessionPhase.live);
        } else if (s == RTCPeerConnectionState.RTCPeerConnectionStateFailed) {
          close('Connection lost');
        }
      };
      pc.onTrack = (e) {
        if (e.track.kind == 'video' && e.streams.isNotEmpty) {
          renderer.srcObject = e.streams.first;
          notifyListeners();
        }
      };

      _messages = _channel.rest().listen(_onMessage,
          onDone: () => close('The other device disconnected'));
      unawaited(_channel.closed.then((r) => close('The other device disconnected')));

      if (isSharer) await _startSharing(pc);
      _statsTimer =
          Timer.periodic(const Duration(seconds: 1), (_) => _pollStats());
    } catch (e) {
      close(e is CaptureDenied ? e.toString() : 'Could not start: $e');
    }
  }

  Future<void> _startSharing(RTCPeerConnection pc) async {
    final stream = await ScreenCapture.start(fps: _quality.fps);
    _localStream = stream;
    renderer.srcObject = stream; // local preview
    final track = stream.getVideoTracks().first;
    track.onEnded = () => close('Screen sharing was stopped');
    _sender = await pc.addTrack(track, stream);
    await _preferCodec(pc, _quality.codec);

    final offer = await pc.createOffer();
    await pc.setLocalDescription(offer);
    _channel.send({
      't': 'offer',
      'sdp': offer.sdp,
      'mac': PairingService.mac(_code, offer.sdp ?? ''),
    });
    await _applyEncoding();
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
          final answer = await pc.createAnswer();
          await pc.setLocalDescription(answer);
          _channel.send({
            't': 'answer',
            'sdp': answer.sdp,
            'mac': PairingService.mac(_code, answer.sdp ?? ''),
          });
        case 'answer' when isSharer:
          final sdp = _verifiedSdp(m);
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
        case 'quality' when isSharer:
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
    if (_sourceHeight != null) {
      _scale = (_sourceHeight! / q.resolution).clamp(1.0, 8.0);
    }
    try {
      final params = sender.parameters;
      final encodings = params.encodings;
      if (encodings == null || encodings.isEmpty) {
        params.encodings = [RTCRtpEncoding()];
      }
      final e = params.encodings!.first;
      e.maxFramerate = q.fps;
      e.maxBitrate = q.autoBitrate ? null : (q.mbps * 1000000).round();
      e.scaleResolutionDownBy = _scale;
      await sender.setParameters(params);
    } catch (err) {
      debugPrint('BeamX: could not apply encoding ($err)');
    }
  }

  /// Viewer side: ask the sharing device for a new quality.
  void requestQuality(StreamQuality q) {
    if (isSharer || q == _quality) return;
    _quality = q;
    _channel.send({'t': 'quality', 'quality': q.toJson()});
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
      if (isSharer && _sourceHeight == null && h != null && h > 0) {
        _sourceHeight = (h * _scale).round();
        await _applyEncoding();
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
    _statsTimer?.cancel();
    _channel.send({'t': 'bye'});
    _channel.close(reason);
    await _messages?.cancel();
    try {
      for (final t in _localStream?.getTracks() ?? <MediaStreamTrack>[]) {
        await t.stop();
      }
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
