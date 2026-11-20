import 'package:cupertino_ui/cupertino_ui.dart' show CupertinoPageTransitionsBuilder;
import 'package:material_ui/material_ui.dart';

class AppTheme {
  AppTheme._();

  static const accents = <Color>[
    Color(0xFF6C5CE7), // violet
    Color(0xFF0EA5E9), // sky
    Color(0xFF10B981), // emerald
    Color(0xFFF97316), // orange
    Color(0xFFEC4899), // pink
    Color(0xFFEF4444), // red
  ];

  static Color accent(int index) =>
      accents[index.clamp(0, accents.length - 1).toInt()];

  static ThemeData build(Color seed, Brightness brightness) {
    final scheme =
        ColorScheme.fromSeed(seedColor: seed, brightness: brightness);
    final background = brightness == Brightness.dark
        ? const Color(0xFF0D0E13)
        : const Color(0xFFF5F6FA);

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: background,
      visualDensity: VisualDensity.adaptivePlatformDensity,
      cardTheme: CardThemeData(
        elevation: 0,
        margin: EdgeInsets.zero,
        color: scheme.surfaceContainerLow,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: background,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: background,
        indicatorColor: scheme.primaryContainer,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: scheme.surfaceContainer,
        indicatorColor: scheme.primaryContainer,
      ),
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: ZoomPageTransitionsBuilder(),
          TargetPlatform.windows: ZoomPageTransitionsBuilder(),
          TargetPlatform.linux: ZoomPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
        },
      ),
    );
  }
}
