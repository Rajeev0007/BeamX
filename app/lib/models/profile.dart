import 'package:material_ui/material_ui.dart';

import 'settings.dart';

/// A one-tap preset that applies a group of streaming settings.
class StreamProfile {
  const StreamProfile({
    required this.name,
    required this.description,
    required this.icon,
    required this.apply,
  });

  final String name;
  final String description;
  final IconData icon;
  final BeamSettings Function(BeamSettings) apply;

  static final builtIn = <StreamProfile>[
    StreamProfile(
      name: 'Battery Saver',
      description: '720p · 30 FPS · low data use',
      icon: Icons.battery_saver_rounded,
      apply: (s) => s.copyWith(
        resolution: 720,
        fps: 30,
        autoBitrate: false,
        bitrateMbps: 4,
        codec: VideoCodec.h265,
        activeProfile: 'Battery Saver',
      ),
    ),
    StreamProfile(
      name: 'Balanced',
      description: '1080p · 60 FPS · auto bitrate',
      icon: Icons.tune_rounded,
      apply: (s) => s.copyWith(
        resolution: 1080,
        fps: 60,
        autoBitrate: true,
        codec: VideoCodec.h264,
        activeProfile: 'Balanced',
      ),
    ),
    StreamProfile(
      name: 'High Quality',
      description: '1440p · 60 FPS · sharp text for work',
      icon: Icons.hd_rounded,
      apply: (s) => s.copyWith(
        resolution: 1440,
        fps: 60,
        autoBitrate: false,
        bitrateMbps: 30,
        codec: VideoCodec.h265,
        activeProfile: 'High Quality',
      ),
    ),
    StreamProfile(
      name: 'Gaming',
      description: '1080p · 120 FPS · lowest lag',
      icon: Icons.sports_esports_rounded,
      apply: (s) => s.copyWith(
        resolution: 1080,
        fps: 120,
        autoBitrate: false,
        bitrateMbps: 40,
        codec: VideoCodec.h264,
        encoder: Encoder.gpu,
        showStatsOverlay: true,
        activeProfile: 'Gaming',
      ),
    ),
    StreamProfile(
      name: 'Movies',
      description: '4K · 30 FPS · best picture and sound',
      icon: Icons.movie_rounded,
      apply: (s) => s.copyWith(
        resolution: 2160,
        fps: 30,
        autoBitrate: true,
        codec: VideoCodec.av1,
        audioEnabled: true,
        activeProfile: 'Movies',
      ),
    ),
  ];
}
