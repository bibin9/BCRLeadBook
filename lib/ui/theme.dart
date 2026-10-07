import 'package:flutter/material.dart';

import '../data/models.dart';

/// Exact signature text required by the brief.
const String kSignature = 'BCR (BibinCutRiver)';
const String kAppName = 'BCR LeadBook';
const String kAppVersion = '1.0.0';

const Color kBlue = Color(0xFF1565C0); // buttons, links, selected states
const Color kHeader = Color(0xFF0D47A1); // app bar (8.6:1 with white)
// Success / done: teal, distinct from the brand blue and from danger red.
const Color kSuccess = Color(0xFF00796B);
const Color kSuccessBg = Color(0xFFE0F2F1);
const Color kBlueDark = Color(0xFF0D47A1);
const Color kBlueSoft = Color(0xFFE8F1FB);
const Color kInk = Color(0xFF14202E);
const Color kMuted = Color(0xFF4A5A6B); // 7:1 on white

ThemeData buildTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: kBlue,
    brightness: Brightness.light,
  ).copyWith(
    primary: kBlue,
    onPrimary: Colors.white,
    surface: Colors.white,
    onSurface: kInk,
    error: const Color(0xFFB3261E),
  );
  const radius = BorderRadius.all(Radius.circular(12));
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: const Color(0xFFF5F8FC),
    visualDensity: VisualDensity.standard,
    appBarTheme: const AppBarTheme(
      backgroundColor: kHeader,
      foregroundColor: Colors.white,
      elevation: 0,
      centerTitle: false,
    ),
    cardTheme: CardThemeData(
      color: Colors.white,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: radius,
        side: BorderSide(color: Colors.blueGrey.shade100),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white,
      border: OutlineInputBorder(borderRadius: radius, borderSide: BorderSide(color: Colors.blueGrey.shade200)),
      enabledBorder: OutlineInputBorder(borderRadius: radius, borderSide: BorderSide(color: Colors.blueGrey.shade200)),
      focusedBorder: const OutlineInputBorder(borderRadius: radius, borderSide: BorderSide(color: kBlue, width: 2)),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      labelStyle: const TextStyle(color: kMuted),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(64, 52),
        shape: RoundedRectangleBorder(borderRadius: radius),
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(64, 48),
        shape: RoundedRectangleBorder(borderRadius: radius),
        side: const BorderSide(color: kBlue),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(minimumSize: const Size(64, 48)),
    ),
    chipTheme: ChipThemeData(
      labelStyle: const TextStyle(fontSize: 14, color: kInk),
      side: BorderSide(color: Colors.blueGrey.shade200),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: Colors.white,
      indicatorColor: kBlueSoft,
      labelTextStyle: WidgetStateProperty.resolveWith((s) => TextStyle(
            fontSize: 12,
            fontWeight: s.contains(WidgetState.selected) ? FontWeight.w700 : FontWeight.w500,
            color: s.contains(WidgetState.selected) ? kBlueDark : kMuted,
          )),
    ),
    dividerTheme: DividerThemeData(color: Colors.blueGrey.shade100, space: 1),
    snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
  );
}

/// Colour + always a text label (never colour alone).
class QualityStyle {
  const QualityStyle(this.fg, this.bg, this.label, [this.icon]);
  final Color fg;
  final Color bg;
  final String label;
  final IconData? icon;

  static QualityStyle of(LeadQuality? q) => switch (q) {
        LeadQuality.hot => const QualityStyle(Color(0xFF9F1515), Color(0xFFFFD6DA), 'Hot', Icons.local_fire_department),
        LeadQuality.warm => const QualityStyle(Color(0xFF8A3B00), Color(0xFFFFEFD9), 'Warm'),
        // Grey-teal, not blue: blue is reserved for actions.
        LeadQuality.cold => const QualityStyle(Color(0xFF37597A), Color(0xFFE6EEF5), 'Cold'),
        LeadQuality.future => const QualityStyle(Color(0xFF4527A0), Color(0xFFEDE7F6), 'Future Follow-Up'),
        null => const QualityStyle(kMuted, Color(0xFFECEFF3), 'Not rated'),
      };
}
