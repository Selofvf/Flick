import 'package:flutter/material.dart';
import 'dart:math' as math;

class GridBackground extends StatelessWidget {
  final Widget child;
  const GridBackground({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Stack(children: [
      // Фон
      Container(color: dark ? const Color(0xFF0A0A0F) : const Color(0xFFF0F2F8)),

      // Сетка
      CustomPaint(
        painter: _GridPainter(dark: dark),
        size: Size.infinite,
        child: const SizedBox.expand(),
      ),

      // Подсветка сверху
      Positioned(
        top: -120, left: -80,
        child: Container(
          width: 340, height: 340,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(
              colors: [
                const Color(0xFF7C6FFF).withOpacity(dark ? 0.35 : 0.15),
                Colors.transparent,
              ],
            ),
          ),
        ),
      ),
      Positioned(
        top: -100, right: -60,
        child: Container(
          width: 260, height: 260,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(
              colors: [
                const Color(0xFF38BDF8).withOpacity(dark ? 0.2 : 0.1),
                Colors.transparent,
              ],
            ),
          ),
        ),
      ),

      // Контент
      child,
    ]);
  }
}

class _GridPainter extends CustomPainter {
  final bool dark;
  _GridPainter({required this.dark});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = dark
          ? const Color(0xFFFFFFFF).withOpacity(0.04)
          : const Color(0xFF000000).withOpacity(0.06)
      ..strokeWidth = 1;

    const step = 32.0;

    // Вертикальные линии
    for (double x = 0; x < size.width; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }

    // Горизонтальные линии
    for (double y = 0; y < size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(_GridPainter old) => old.dark != dark;
}