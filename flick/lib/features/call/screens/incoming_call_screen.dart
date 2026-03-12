import 'package:flutter/material.dart';
import 'call_screen.dart';

class IncomingCallScreen extends StatelessWidget {
  final String chatId;
  final String callerName;

  const IncomingCallScreen({
    super.key,
    required this.chatId,
    required this.callerName,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0F),
      body: Stack(children: [

        // Фон
        const Positioned.fill(child: _AnimatedGradientBg()),

        // Контент
        Positioned.fill(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [

              // Верх — имя и статус
              Padding(
                padding: const EdgeInsets.only(top: 100),
                child: Column(children: [
                  // Пульсирующий аватар
                  Stack(alignment: Alignment.center, children: [
                    _PulseRing(color: const Color(0xFF7C6FFF).withOpacity(0.15), delay: 0),
                    _PulseRing(color: const Color(0xFF7C6FFF).withOpacity(0.25), delay: 400),
                    Container(
                      width: 110, height: 110,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: const LinearGradient(
                          colors: [Color(0xFF7C6FFF), Color(0xFF38BDF8)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight),
                        boxShadow: [BoxShadow(
                          color: const Color(0xFF7C6FFF).withOpacity(0.5),
                          blurRadius: 40, spreadRadius: 4)],
                      ),
                      child: Center(child: Text(
                        callerName.isNotEmpty ? callerName[0].toUpperCase() : '?',
                        style: const TextStyle(fontFamily: 'Syne', fontSize: 46,
                          fontWeight: FontWeight.w800, color: Colors.white))),
                    ),
                  ]),

                  const SizedBox(height: 32),

                  Text(callerName,
                    style: const TextStyle(fontFamily: 'Syne', fontSize: 28,
                      fontWeight: FontWeight.w800, color: Colors.white)),

                  const SizedBox(height: 12),

                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(20),
                      color: Colors.white.withOpacity(0.1),
                    ),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Container(
                        width: 8, height: 8,
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          color: Color(0xFF38BDF8)),
                      ),
                      const SizedBox(width: 8),
                      const Text('Входящий видеозвонок',
                        style: TextStyle(fontFamily: 'DM Sans', fontSize: 14,
                          color: Colors.white70)),
                    ]),
                  ),
                ]),
              ),

              // Низ — кнопки принять/отклонить
              Padding(
                padding: const EdgeInsets.only(bottom: 70),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [

                    // Отклонить
                    Column(children: [
                      GestureDetector(
                        onTap: () => Navigator.of(context).pop(),
                        child: Container(
                          width: 70, height: 70,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: const Color(0xFFFF5E7D),
                            boxShadow: [BoxShadow(
                              color: const Color(0xFFFF5E7D).withOpacity(0.5),
                              blurRadius: 20)],
                          ),
                          child: const Icon(Icons.call_end_rounded,
                              color: Colors.white, size: 32),
                        ),
                      ),
                      const SizedBox(height: 12),
                      const Text('Отклонить',
                        style: TextStyle(fontFamily: 'DM Sans', fontSize: 13,
                          color: Colors.white70)),
                    ]),

                    // Принять
                    Column(children: [
                      GestureDetector(
                        onTap: () {
                          Navigator.pushReplacement(context, MaterialPageRoute(
                            builder: (_) => CallScreen(
                              chatId:     chatId,
                              remoteName: callerName,
                              isCaller:   false,
                            ),
                          ));
                        },
                        child: Container(
                          width: 70, height: 70,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: const LinearGradient(
                              colors: [Color(0xFF43E97B), Color(0xFF38F9D7)],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight),
                            boxShadow: [BoxShadow(
                              color: const Color(0xFF43E97B).withOpacity(0.5),
                              blurRadius: 20)],
                          ),
                          child: const Icon(Icons.videocam_rounded,
                              color: Colors.white, size: 32),
                        ),
                      ),
                      const SizedBox(height: 12),
                      const Text('Принять',
                        style: TextStyle(fontFamily: 'DM Sans', fontSize: 13,
                          color: Colors.white70)),
                    ]),
                  ],
                ),
              ),
            ],
          ),
        ),
      ]),
    );
  }
}

// ── Анимированный градиент ────────────────────────────────────────────────────
class _AnimatedGradientBg extends StatefulWidget {
  const _AnimatedGradientBg();
  @override State<_AnimatedGradientBg> createState() => _AnimatedGradientBgState();
}

class _AnimatedGradientBgState extends State<_AnimatedGradientBg>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;

  final _colors = [
    [const Color(0xFF0D0B1F), const Color(0xFF1A0A3A), const Color(0xFF0A1830)],
    [const Color(0xFF1A0A3A), const Color(0xFF0A1830), const Color(0xFF200A40)],
    [const Color(0xFF0A1830), const Color(0xFF200A40), const Color(0xFF0D0B1F)],
  ];
  int _idx = 0;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 2500))
      ..addStatusListener((s) {
        if (s == AnimationStatus.completed) {
          setState(() => _idx = (_idx + 1) % _colors.length);
          _ctrl.forward(from: 0);
        }
      })
      ..forward();
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final next = (_idx + 1) % _colors.length;
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, __) {
        final t = Curves.easeInOut.transform(_ctrl.value);
        return Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                Color.lerp(_colors[_idx][0], _colors[next][0], t)!,
                Color.lerp(_colors[_idx][1], _colors[next][1], t)!,
                Color.lerp(_colors[_idx][2], _colors[next][2], t)!,
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              stops: const [0.0, 0.5, 1.0],
            ),
          ),
        );
      },
    );
  }
}

// ── Пульсирующее кольцо ───────────────────────────────────────────────────────
class _PulseRing extends StatefulWidget {
  final Color color;
  final int delay;
  const _PulseRing({required this.color, required this.delay});
  @override State<_PulseRing> createState() => _PulseRingState();
}

class _PulseRingState extends State<_PulseRing>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _scale;
  late Animation<double> _opacity;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1800))
      ..repeat();
    _scale   = Tween(begin: 1.0, end: 2.2).animate(
        CurvedAnimation(parent: _ctrl, curve: Curves.easeOut));
    _opacity = Tween(begin: 0.8, end: 0.0).animate(
        CurvedAnimation(parent: _ctrl, curve: Curves.easeOut));

    if (widget.delay > 0) {
      Future.delayed(Duration(milliseconds: widget.delay), () {
        if (mounted) _ctrl.forward(from: 0);
      });
    }
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _ctrl,
    builder: (_, __) => Transform.scale(
      scale: _scale.value,
      child: Opacity(
        opacity: _opacity.value,
        child: Container(
          width: 110, height: 110,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: widget.color),
        ),
      ),
    ),
  );
}
