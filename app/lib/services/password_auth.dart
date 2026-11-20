import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';

/// Owner-set password for connecting by ID ("unattended access").
///
/// The password is never stored or sent. Both devices turn it into a key
/// with PBKDF2-HMAC-SHA256 (salted with the host's device ID), and the
/// connecting device proves it has the key with the usual HMAC challenge.
/// The many iterations make guessing passwords offline slow.
class PasswordAuth {
  PasswordAuth._();

  static const iterations = 150000;
  static const minLength = 8;

  /// Returns a reason the password is too weak, or null if it's acceptable.
  static String? weakness(String p) {
    if (p.length < minLength) return 'Use at least $minLength characters';
    if (p.length > 128) return 'Use at most 128 characters';
    if (RegExp(r'^\d+$').hasMatch(p) && p.length < 12) {
      return 'Number-only passwords need at least 12 digits';
    }
    if (p.toLowerCase().split('').toSet().length < 4) {
      return 'Use more different characters';
    }
    return null;
  }

  /// Derives the 256-bit key (hex) in a background isolate, so the UI
  /// doesn't freeze. [hostId] is the device being connected to.
  static Future<String> deriveKey(String password, String hostId) =>
      compute(_derive, [password, hostId]);

  static String _derive(List<String> args) {
    final key = pbkdf2Sha256(
        utf8.encode(args[0]), utf8.encode('beamx-password|${args[1]}'), iterations);
    return key.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  /// PBKDF2-HMAC-SHA256 producing one 32-byte block (RFC 8018).
  @visibleForTesting
  static Uint8List pbkdf2Sha256(List<int> password, List<int> salt, int iterations) {
    final hmac = Hmac(sha256, password);
    var u = hmac.convert([...salt, 0, 0, 0, 1]).bytes;
    final out = Uint8List.fromList(u);
    for (var i = 1; i < iterations; i++) {
      u = hmac.convert(u).bytes;
      for (var j = 0; j < out.length; j++) {
        out[j] ^= u[j];
      }
    }
    return out;
  }
}

/// Limits password guessing: after [maxFailures] wrong passwords within
/// [window], password access is refused until the window passes.
class PasswordLockout {
  PasswordLockout({this.maxFailures = 5, this.window = const Duration(minutes: 10)});

  final int maxFailures;
  final Duration window;
  final List<DateTime> _failures = [];

  void _prune() {
    final cutoff = DateTime.now().subtract(window);
    _failures.removeWhere((t) => t.isBefore(cutoff));
  }

  bool get locked {
    _prune();
    return _failures.length >= maxFailures;
  }

  void fail() {
    _prune();
    _failures.add(DateTime.now());
  }

  void success() => _failures.clear();
}
