import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class StoryScreen extends StatefulWidget {
  final List<Map<String, dynamic>> stories;
  final String ownerName;
  final int initialIndex;
  const StoryScreen({
    super.key,
    required this.stories,
    required this.ownerName,
    this.initialIndex = 0,
  });
  @override State<StoryScreen> createState() => _StoryScreenState();
}

class _StoryScreenState extends State<StoryScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _progress;
  late int _current;
  bool _paused = false;

  @override
  void initState() {
    super.initState();
    _current = widget.initialIndex;
    _progress = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 5),
    )..addStatusListener((s) {
        if (s == AnimationStatus.completed) _next();
      });
    _progress.forward();
  }

  void _next() {
    if (_current < widget.stories.length - 1) {
      setState(() => _current++);
      _progress.forward(from: 0);
    } else {
      Navigator.pop(context);
    }
  }

  void _prev() {
    if (_current > 0) {
      setState(() => _current--);
      _progress.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _progress.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final story = widget.stories[_current];
    final type  = story['type'] ?? 'text';
    final ts    = story['createdAt'] as Timestamp?;
    final time  = ts != null
        ? _timeAgo(ts.toDate())
        : '';

    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        onTapDown: (d) {
          _progress.stop();
          setState(() => _paused = true);
        },
        onTapUp: (d) {
          final w = MediaQuery.of(context).size.width;
          if (d.globalPosition.dx < w / 2) {
            _prev();
          } else {
            _next();
          }
          setState(() => _paused = false);
        },
        onLongPressStart: (_) {
          _progress.stop();
          setState(() => _paused = true);
        },
        onLongPressEnd: (_) {
          _progress.forward();
          setState(() => _paused = false);
        },
        child: Stack(children: [

          // Контент
          Positioned.fill(child: _buildContent(story, type)),

          // Прогресс бары
          Positioned(
            top: MediaQuery.of(context).padding.top + 12,
            left: 12, right: 12,
            child: Row(children: List.generate(widget.stories.length, (i) {
              return Expanded(
                child: Container(
                  height: 2.5,
                  margin: const EdgeInsets.symmetric(horizontal: 2),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(99),
                    color: Colors.white.withOpacity(0.3)),
                  child: i < _current
                      ? Container(decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(99),
                          color: Colors.white))
                      : i == _current
                          ? AnimatedBuilder(
                              animation: _progress,
                              builder: (_, __) => FractionallySizedBox(
                                alignment: Alignment.centerLeft,
                                widthFactor: _progress.value,
                                child: Container(decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(99),
                                  color: Colors.white))))
                          : const SizedBox(),
                ),
              );
            })),
          ),

          // Шапка
          Positioned(
            top: MediaQuery.of(context).padding.top + 24,
            left: 16, right: 16,
            child: Row(children: [
              // Аватар
              Container(
                width: 36, height: 36,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  gradient: const LinearGradient(
                    colors: [Color(0xFF7C6FFF), Color(0xFF38BDF8)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight),
                ),
                child: Center(child: Text(
                  widget.ownerName.isNotEmpty
                      ? widget.ownerName[0].toUpperCase() : '?',
                  style: const TextStyle(fontFamily: 'Syne', fontSize: 16,
                    fontWeight: FontWeight.w800, color: Colors.white))),
              ),
              const SizedBox(width: 10),
              Expanded(child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(widget.ownerName,
                    style: const TextStyle(fontFamily: 'Syne', fontSize: 14,
                      fontWeight: FontWeight.w700, color: Colors.white)),
                  Text(time,
                    style: TextStyle(fontFamily: 'DM Sans', fontSize: 12,
                      color: Colors.white.withOpacity(0.7))),
                ])),
              IconButton(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close_rounded,
                    color: Colors.white, size: 24)),
            ]),
          ),
        ]),
      ),
    );
  }

  Widget _buildContent(Map story, String type) {
    if (type == 'image') {
      return Image.network(
        story['imageUrl'] ?? '',
        fit: BoxFit.cover,
        width: double.infinity,
        height: double.infinity,
        errorBuilder: (_, __, ___) => _textContent(story),
      );
    }
    return _textContent(story);
  }

  Widget _textContent(Map story) {
    final text    = story['text'] ?? '';
    final colorHex = story['bgColor'] ?? '0xFF1A0A3A';
    final color2Hex = story['bgColor2'] ?? '0xFF0A1830';
    Color c1, c2;
    try {
      c1 = Color(int.parse(colorHex));
      c2 = Color(int.parse(color2Hex));
    } catch (_) {
      c1 = const Color(0xFF1A0A3A);
      c2 = const Color(0xFF0A1830);
    }
    return Container(
      width: double.infinity,
      height: double.infinity,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [c1, c2],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight)),
      child: Center(child: Padding(
        padding: const EdgeInsets.all(32),
        child: Text(text,
          textAlign: TextAlign.center,
          style: const TextStyle(fontFamily: 'Syne', fontSize: 26,
            fontWeight: FontWeight.w700, color: Colors.white,
            shadows: [Shadow(blurRadius: 16, color: Colors.black38)])),
      )),
    );
  }

  String _timeAgo(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return 'только что';
    if (diff.inMinutes < 60) return '${diff.inMinutes} мин назад';
    if (diff.inHours < 24) return '${diff.inHours} ч назад';
    return '${diff.inDays} д назад';
  }
}
