import 'package:flutter/material.dart';
import 'dart:ui' as ui;
import '../database/db_helper.dart';

class GeometricBackground extends StatelessWidget {
  final Widget child;

  const GeometricBackground({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;

    return Stack(
      fit: StackFit.expand,
      children: [
        CustomPaint(
          painter: GeometricPainter(isDarkMode: isDark),
          size: Size.infinite,
        ),
        child,
      ],
    );
  }
}

class GeometricPainter extends CustomPainter {
  final bool isDarkMode;

  GeometricPainter({required this.isDarkMode});

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;

    final Paint paint = Paint()
      ..strokeWidth = 4.0
      ..style = PaintingStyle.stroke;

    final List<Offset> points = [
      Offset(size.width * -0.05, size.height * 0.1),
      Offset(size.width * 0.3, size.height * -0.05),
      Offset(size.width * 0.5, size.height * 0.2),
      Offset(size.width * 0.95, size.height * -0.05),
      Offset(size.width * 1.05, size.height * 0.35),
      Offset(size.width * -0.05, size.height * 0.5),
      Offset(size.width * 0.3, size.height * 0.85),
      Offset(size.width * 0.85, size.height * 0.6),
      Offset(size.width * -0.05, size.height * 0.95),
      Offset(size.width * 0.4, size.height * 1.05),
      Offset(size.width * 1.05, size.height * 0.95),
    ];

    final List<List<int>> connections = [
      [0, 1],
      [1, 2],
      [2, 3],
      [3, 4],
      [0, 5],
      [1, 5],
      [2, 5],
      [2, 6],
      [3, 6],
      [4, 7],
      [5, 6],
      [6, 7],
      [5, 8],
      [6, 9],
      [7, 10],
      [8, 9],
      [9, 10],
      [0, 2],
      [3, 7],
      [6, 10],
    ];

    for (var conn in connections) {
      final p1 = points[conn[0]];
      final p2 = points[conn[1]];

      paint.shader = ui.Gradient.linear(
        p1,
        p2,
        isDarkMode
            ? [const Color(0xFF00C49F), Colors.purpleAccent, Colors.blueAccent]
            : [Colors.teal, Colors.indigo, Colors.deepPurple],
        [0.0, 0.5, 1.0],
      );

      canvas.drawLine(p1, p2, paint);
    }

    final Paint glowPaint = Paint()..style = PaintingStyle.fill;
    for (var point in points) {
      glowPaint.color = isDarkMode
          ? const Color(0xFF00C49F).withValues(alpha: 0.8)
          : Colors.teal.withValues(alpha: 0.8);
      canvas.drawCircle(point, 8.0, glowPaint);
    }
  }

  @override
  bool shouldRepaint(covariant GeometricPainter oldDelegate) {
    return oldDelegate.isDarkMode != isDarkMode;
  }
}

class ThemeController {
  static final ValueNotifier<ThemeMode> themeNotifier = ValueNotifier(
    ThemeMode.dark,
  );

  static bool get isDarkMode => themeNotifier.value == ThemeMode.dark;

  static Future<void> initTheme() async {
    final dbHelper = DbHelper();
    final temaSalvo = await dbHelper.getTema();

    themeNotifier.value = temaSalvo == 'light'
        ? ThemeMode.light
        : ThemeMode.dark;
  }

  static void toggleTheme() async {
    final novoTema = isDarkMode ? ThemeMode.light : ThemeMode.dark;

    themeNotifier.value = novoTema;

    final dbHelper = DbHelper();
    await dbHelper.setTema(novoTema == ThemeMode.light ? 'light' : 'dark');
  }

  static ThemeData get darkTheme => ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    scaffoldBackgroundColor: const Color(0xFF0A0A0A),
    cardColor: const Color(0xFF141414),
    colorScheme: const ColorScheme.dark(
      primary: Color(0xFF00C49F),
      surface: Color(0xFF141414),
      onSurface: Color(0xFFE0E0E0),
    ),
  );

  static ThemeData get lightTheme => ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    scaffoldBackgroundColor: const Color.fromARGB(255, 233, 233, 232),
    cardColor: const Color(0xFFF4F4F6),
    colorScheme: const ColorScheme.light(
      primary: Color(0xFF00C49F),
      surface: Colors.white,
      onSurface: Color(0xFF1F1F1F),
    ),
  );
}
