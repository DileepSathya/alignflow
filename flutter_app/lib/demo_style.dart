import 'package:flutter/material.dart';

/// Visual tokens transcribed from the v3 demo. Keep all runtime styling here.
abstract final class DemoStyle {
  static const bg = Color(0xfff3f6f7);
  static const surface = Colors.white;
  static const surface2 = Color(0xffeaf0f2);
  static const ink = Color(0xff10242b);
  static const muted = Color(0xff4a6068);
  static const line = Color(0xffd8e2e6);
  static const accent = Color(0xff0b7a75);
  static const accentSoft = Color(0xffd9efed);
  static const danger = Color(0xffb3261e);

  static ThemeData theme() => ThemeData(
    useMaterial3: true,
    scaffoldBackgroundColor: bg,
    colorScheme: ColorScheme.fromSeed(seedColor: accent, primary: accent, surface: surface),
    fontFamily: 'InstrumentSans',
    textTheme: const TextTheme(
      headlineLarge: TextStyle(fontFamily: 'Bricolage', fontSize: 30, height: 1.1, fontWeight: FontWeight.w700, color: ink),
      headlineMedium: TextStyle(fontFamily: 'Bricolage', fontSize: 26, height: 1.15, fontWeight: FontWeight.w700, color: ink),
      titleLarge: TextStyle(fontFamily: 'Bricolage', fontSize: 19, fontWeight: FontWeight.w700, color: ink),
      bodyMedium: TextStyle(fontSize: 14, height: 1.5, color: ink),
      bodySmall: TextStyle(fontSize: 12, height: 1.4, color: muted),
    ),
    cardTheme: CardThemeData(color: surface, elevation: 0, shape: RoundedRectangleBorder(
      side: const BorderSide(color: line), borderRadius: BorderRadius.circular(14))),
    inputDecorationTheme: InputDecorationTheme(
      filled: true, fillColor: surface, isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      border: OutlineInputBorder(borderSide: const BorderSide(color: line), borderRadius: BorderRadius.circular(10)),
      enabledBorder: OutlineInputBorder(borderSide: const BorderSide(color: line), borderRadius: BorderRadius.circular(10)),
      focusedBorder: OutlineInputBorder(borderSide: const BorderSide(color: accent, width: 2), borderRadius: BorderRadius.circular(10)),
    ),
    filledButtonTheme: FilledButtonThemeData(style: FilledButton.styleFrom(
      backgroundColor: accent, foregroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11))),
  );
}

class DemoPanel extends StatelessWidget {
  final Widget child;
  const DemoPanel({super.key, required this.child});
  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(color: DemoStyle.surface, border: Border.all(color: DemoStyle.line),
      borderRadius: BorderRadius.circular(14)), clipBehavior: Clip.antiAlias, child: child);
}

class DemoPageHeading extends StatelessWidget {
  final String title, subtitle;
  final Widget? action;
  const DemoPageHeading({super.key, required this.title, required this.subtitle, this.action});
  @override
  Widget build(BuildContext context) => Wrap(
    alignment: WrapAlignment.spaceBetween, crossAxisAlignment: WrapCrossAlignment.end,
    spacing: 16, runSpacing: 16, children: [
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: Theme.of(context).textTheme.headlineLarge),
        const SizedBox(height: 6), Text(subtitle, style: const TextStyle(color: DemoStyle.muted)),
      ]), if (action != null) action!,
    ]);
}

class DemoStatusPill extends StatelessWidget {
  final String label;
  final Color color, background;
  const DemoStatusPill({super.key, required this.label, this.color = DemoStyle.muted,
    this.background = DemoStyle.surface2});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration: BoxDecoration(color: background, borderRadius: BorderRadius.circular(99)),
    child: Text(label, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w600)));
}

/// The two-line wave mark used by the v3 HTML pages.
class DemoBrandMark extends StatelessWidget {
  final double size;
  const DemoBrandMark({super.key, this.size = 38});
  @override
  Widget build(BuildContext context) => Container(width: size, height: size,
    decoration: BoxDecoration(color: DemoStyle.accent, borderRadius: BorderRadius.circular(size * .29)),
    child: CustomPaint(painter: _WavePainter()));
}

class _WavePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.width / 24;
    final paint = Paint()..color = Colors.white..style = PaintingStyle.stroke
      ..strokeWidth = 2.2 * scale..strokeCap = StrokeCap.round..strokeJoin = StrokeJoin.round;
    canvas.save();
    canvas.translate((size.width - 24 * scale) / 2, (size.height - 24 * scale) / 2);
    canvas.scale(scale);
    final top = Path()..moveTo(4, 15)..cubicTo(4, 10, 7, 6, 12, 6)
      ..cubicTo(17, 6, 20, 10, 20, 15);
    final wave = Path()..moveTo(4, 15)..cubicTo(6, 18, 9, 18, 12, 15)
      ..cubicTo(15, 18, 18, 18, 20, 15);
    canvas.drawPath(top, paint);
    canvas.drawPath(wave, paint);
    canvas.restore();
  }
  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
