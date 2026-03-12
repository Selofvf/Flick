import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:firebase_auth/firebase_auth.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});
  @override State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _scale, _fade, _textFade;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 1600));
    _scale    = Tween(begin: 0.5, end: 1.0).animate(CurvedAnimation(parent: _ctrl, curve: const Interval(0.0, 0.6, curve: Curves.elasticOut)));
    _fade     = Tween(begin: 0.0, end: 1.0).animate(CurvedAnimation(parent: _ctrl, curve: const Interval(0.0, 0.4, curve: Curves.easeOut)));
    _textFade = Tween(begin: 0.0, end: 1.0).animate(CurvedAnimation(parent: _ctrl, curve: const Interval(0.5, 1.0, curve: Curves.easeOut)));
    _ctrl.forward();
    Future.delayed(const Duration(milliseconds: 2200), _navigate);
  }

  void _navigate() {
    if (!mounted) return;
    FirebaseAuth.instance.currentUser != null
        ? context.go('/home')
        : context.go('/login');
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0F),
      body: Stack(children: [
        Positioned.fill(child: CustomPaint(painter: _GridPainter())),
        Positioned(top: -120, left: -150, child: _glow(500, const Color(0xFF7C6FFF), 0.15)),
        Positioned(bottom: -100, right: -100, child: _glow(400, const Color(0xFF38BDF8), 0.10)),
        Center(
          child: AnimatedBuilder(
            animation: _ctrl,
            builder: (_, __) => Column(mainAxisSize: MainAxisSize.min, children: [
              FadeTransition(opacity: _fade,
                child: ScaleTransition(scale: _scale, child: _logo())),
              const SizedBox(height: 24),
              FadeTransition(opacity: _textFade, child: _title()),
              const SizedBox(height: 8),
              FadeTransition(opacity: _textFade,
                child: const Text('Общайся без границ',
                  style: TextStyle(fontFamily: 'DM Sans', fontSize: 15,
                    color: Color(0xFF8B8B9E)))),
              const SizedBox(height: 56),
              FadeTransition(opacity: _textFade, child: const _Dots()),
            ]),
          ),
        ),
      ]),
    );
  }

  Widget _logo() => Container(
    width: 110, height: 110,
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(30),
      boxShadow: [BoxShadow(
        color: const Color(0xFF7C6FFF).withOpacity(0.4),
        blurRadius: 50, spreadRadius: 8)],
    ),
    child: ClipRRect(
      borderRadius: BorderRadius.circular(30),
      child: Image.asset(
        'assets/icons/flick_logo.png',
        fit: BoxFit.cover,
      ),
    ),
  );

  Widget _title() => ShaderMask(
    shaderCallback: (b) => const LinearGradient(
      colors: [Colors.white, Color(0xFFB49FFF), Color(0xFF38BDF8)],
      stops: [0.0, 0.55, 1.0],
    ).createShader(b),
    child: const Text('Flick',
      style: TextStyle(fontFamily: 'Syne', fontSize: 48,
        fontWeight: FontWeight.w800, color: Colors.white, letterSpacing: -2)),
  );

  Widget _glow(double size, Color color, double opacity) => Container(
    width: size, height: size,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      color: color.withOpacity(opacity)),
  );
}

class _Dots extends StatefulWidget {
  const _Dots();
  @override State<_Dots> createState() => _DotsState();
}

class _DotsState extends State<_Dots> with TickerProviderStateMixin {
  late List<AnimationController> _ctrls;

  @override
  void initState() {
    super.initState();
    _ctrls = List.generate(3, (i) {
      final c = AnimationController(vsync: this,
        duration: const Duration(milliseconds: 600));
      Future.delayed(Duration(milliseconds: i * 200),
        () { if (mounted) c.repeat(reverse: true); });
      return c;
    });
  }

  @override
  void dispose() { for (final c in _ctrls) c.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: List.generate(3, (i) => AnimatedBuilder(
      animation: _ctrls[i],
      builder: (_, __) => Transform.translate(
        offset: Offset(0, Tween(begin: 0.0, end: -8.0).evaluate(
          CurvedAnimation(parent: _ctrls[i], curve: Curves.easeInOut))),
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 4),
          width: 8, height: 8,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: const Color(0xFF7C6FFF).withOpacity(0.7)),
        ),
      ),
    )),
  );
}

class _GridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final h = Paint()..color = const Color(0xFF7C6FFF).withOpacity(0.05)..strokeWidth = 1;
    final v = Paint()..color = const Color(0xFF38BDF8).withOpacity(0.04)..strokeWidth = 1;
    for (double y = 0; y < size.height; y += 40)
      canvas.drawLine(Offset(0, y), Offset(size.width, y), h);
    for (double x = 0; x < size.width; x += 40)
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), v);
  }
  @override bool shouldRepaint(_) => false;
}