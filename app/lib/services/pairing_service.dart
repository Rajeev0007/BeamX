import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';

/// Owns this device's 6-digit pairing code and verifies pairing proofs.
///
/// The code itself never travels over the network. A connecting device
/// proves it knows the code by sending HMAC-SHA256(code, nonce + its id),
/// where the nonce is a fresh random challenge from this device.
class PairingService {
  PairingService() : code = ValueNotifier(_newCode());

  /// After this many wrong proofs the code is replaced, so guessing
  /// all 1,000,000 codes is not practical.
  static const maxFailures = 5;

  final ValueNotifier<String> code;
  int _failures = 0;

  void regenerate() {
    code.value = _newCode();
    _failures = 0;
  }

  static String newNonce() {
    final r = Random.secure();
    return base64Url.encode(List<int>.generate(24, (_) => r.nextInt(256)));
  }

  static String proof(String code, String nonce, String clientId) =>
      _hmac(code, 'pair|$nonce|$clientId');

  /// Authenticates signaling payloads (SDP) with the shared code.
  static String mac(String code, String payload) =>
      _hmac(code, 'sdp|$payload');

  /// Returns true if [proofValue] matches the current code. Wrong proofs
  /// count towards [maxFailures].
  bool verify(String nonce, String clientId, String proofValue) {
    final expected = proof(code.value, nonce, clientId);
    final ok = constantTimeEquals(expected, proofValue);
    if (!ok && ++_failures >= maxFailures) regenerate();
    return ok;
  }

  static bool constantTimeEquals(String a, String b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
    }
    return diff == 0;
  }

  static String _hmac(String key, String msg) =>
      Hmac(sha256, utf8.encode(key)).convert(utf8.encode(msg)).toString();

  static String _newCode() {
    final r = Random.secure();
    return List.generate(6, (_) => r.nextInt(10)).join();
  }
}
