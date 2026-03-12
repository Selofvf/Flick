import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_auth/firebase_auth.dart';

class CallScreen extends StatefulWidget {
  final String chatId;
  final String remoteName;
  final bool isCaller;
  const CallScreen({
    super.key,
    required this.chatId,
    required this.remoteName,
    required this.isCaller,
  });
  @override State<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends State<CallScreen> {
  final _db = FirebaseDatabase.instance;

  RTCPeerConnection? _peer;
  MediaStream?       _localStream;
  MediaStream?       _remoteStream;

  final _localRenderer  = RTCVideoRenderer();
  final _remoteRenderer = RTCVideoRenderer();

  bool _micOn     = true;
  bool _camOn     = true;
  bool _connected = false;
  bool _hangingUp = false;

  late DatabaseReference _callRef;

  final _iceServers = {
    'iceServers': [
      {'urls': 'stun:stun.l.google.com:19302'},
      {'urls': 'stun:stun1.l.google.com:19302'},
    ]
  };

  @override
  void initState() {
    super.initState();
    _callRef = _db.ref('calls/${widget.chatId}');
    _init();
  }

  Future<void> _init() async {
    await _localRenderer.initialize();
    await _remoteRenderer.initialize();
    _localStream = await navigator.mediaDevices.getUserMedia({
      'audio': true,
      'video': {'facingMode': 'user'},
    });
    _localRenderer.srcObject = _localStream;
    setState(() {});

    _peer = await createPeerConnection(_iceServers);
    _localStream!.getTracks().forEach((t) => _peer!.addTrack(t, _localStream!));

    _peer!.onTrack = (event) {
      if (event.streams.isNotEmpty) {
        setState(() {
          _remoteStream = event.streams[0];
          _remoteRenderer.srcObject = _remoteStream;
          _connected = true;
        });
      }
    };

    _peer!.onIceCandidate = (candidate) {
      if (candidate.candidate == null || candidate.candidate!.isEmpty) return;
      _callRef
          .child(widget.isCaller ? 'callerCandidates' : 'calleeCandidates')
          .push()
          .set(candidate.toMap());
    };

    // Подписываемся на кандидатов ДО offer/answer — чтобы не потерять ранние
    _listenForCandidates();

    if (widget.isCaller) {
      await _createOffer();
    } else {
      await _listenForOffer();
    }
  }

  Future<void> _createOffer() async {
    final offer = await _peer!.createOffer();
    await _peer!.setLocalDescription(offer);
    await _callRef.child('offer').set({'type': offer.type, 'sdp': offer.sdp});

    // Ждём answer через stream
    _callRef.child('answer').onValue.listen((event) async {
      final data = event.snapshot.value as Map?;
      if (data == null) return;
      final remote = await _peer!.getRemoteDescription();
      if (remote == null) {
        await _peer!.setRemoteDescription(RTCSessionDescription(
            data['sdp'] as String, data['type'] as String));
      }
    });
  }

  Future<void> _listenForOffer() async {
    // Polling — ждём offer до 10 секунд
    Map? data;
    for (int i = 0; i < 20; i++) {
      if (!mounted) return;
      final snap = await _callRef.child('offer').get();
      data = snap.value as Map?;
      if (data != null) break;
      await Future.delayed(const Duration(milliseconds: 500));
    }
    if (data == null || !mounted) {
      if (mounted) Navigator.of(context).pop();
      return;
    }
    await _peer!.setRemoteDescription(RTCSessionDescription(
        data['sdp'] as String, data['type'] as String));
    final answer = await _peer!.createAnswer();
    await _peer!.setLocalDescription(answer);
    await _callRef
        .child('answer')
        .set({'type': answer.type, 'sdp': answer.sdp});
  }

  void _listenForCandidates() {
    final path = widget.isCaller ? 'calleeCandidates' : 'callerCandidates';
    _callRef.child(path).onChildAdded.listen((event) async {
      if (_peer == null) return;
      final data = event.snapshot.value as Map?;
      if (data == null) return;
      try {
        await _peer!.addCandidate(RTCIceCandidate(
            data['candidate'] as String?,
            data['sdpMid'] as String?,
            data['sdpMLineIndex'] as int?));
      } catch (_) {}
    });
  }

  Future<void> _hangUp() async {
    if (_hangingUp) return;
    setState(() => _hangingUp = true);

    try {
      // Сначала закрываем медиа и peer
      _localStream?.getTracks().forEach((t) => t.stop());
      _remoteStream?.getTracks().forEach((t) => t.stop());
      await _peer?.close();
      _peer = null;

      // Потом удаляем из БД с таймаутом
      await _callRef.remove().timeout(
        const Duration(seconds: 3),
        onTimeout: () {},
      );
    } catch (_) {}

    if (mounted) Navigator.of(context).pop();
  }

  void _toggleMic() {
    final track = _localStream?.getAudioTracks().firstOrNull;
    if (track != null) {
      track.enabled = !track.enabled;
      setState(() => _micOn = track.enabled);
    }
  }

  void _toggleCam() {
    final track = _localStream?.getVideoTracks().firstOrNull;
    if (track != null) {
      track.enabled = !track.enabled;
      setState(() => _camOn = track.enabled);
    }
  }

  @override
  void dispose() {
    _localRenderer.dispose();
    _remoteRenderer.dispose();
    _localStream?.dispose();
    _remoteStream?.dispose();
    _peer?.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0F),
      body: Stack(children: [

        // Фон — градиент или удалённое видео
        Positioned.fill(
          child: _connected
              ? RTCVideoView(_remoteRenderer,
                  objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover)
              : const _AnimatedGradientBg(),
        ),

        // Локальное видео
        Positioned(
          top: 60, right: 16,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: SizedBox(
              width: 100, height: 140,
              child: RTCVideoView(_localRenderer, mirror: true,
                objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover),
            ),
          ),
        ),

        // Имя + статус вверху
        Positioned(
          top: 60, left: 20,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(widget.remoteName,
              style: const TextStyle(fontFamily: 'Syne', fontSize: 22,
                fontWeight: FontWeight.w800, color: Colors.white,
                shadows: [Shadow(blurRadius: 8, color: Colors.black54)])),
            Text(_connected ? 'Соединено' : 'Звоним...',
              style: TextStyle(fontFamily: 'DM Sans', fontSize: 14,
                color: Colors.white.withOpacity(0.7))),
          ]),
        ),

        // Центр — аватар + имя (только когда не соединено)
        if (!_connected) Positioned.fill(
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Container(
              width: 100, height: 100,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: const LinearGradient(
                  colors: [Color(0xFF7C6FFF), Color(0xFF38BDF8)],
                  begin: Alignment.topLeft, end: Alignment.bottomRight),
                boxShadow: [BoxShadow(
                  color: const Color(0xFF7C6FFF).withOpacity(0.5),
                  blurRadius: 40, spreadRadius: 4)],
              ),
              child: Center(child: Text(
                widget.remoteName.isNotEmpty
                    ? widget.remoteName[0].toUpperCase() : '?',
                style: const TextStyle(fontFamily: 'Syne', fontSize: 42,
                  fontWeight: FontWeight.w800, color: Colors.white))),
            ),
            const SizedBox(height: 20),
            Text(widget.remoteName,
              style: const TextStyle(fontFamily: 'Syne', fontSize: 26,
                fontWeight: FontWeight.w800, color: Colors.white)),
            const SizedBox(height: 8),
            const Text('Ожидание ответа...',
              style: TextStyle(fontFamily: 'DM Sans', fontSize: 15,
                color: Color(0xFF8B8B9E))),
            const SizedBox(height: 16),
            _PulseRing(),
          ]),
        ),

        // Кнопки внизу
        Positioned(
          bottom: 48, left: 0, right: 0,
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            _btn(
              icon: _micOn ? Icons.mic_rounded : Icons.mic_off_rounded,
              color: _micOn
                  ? Colors.white.withOpacity(0.15)
                  : const Color(0xFFFF5E7D),
              onTap: _toggleMic,
            ),
            const SizedBox(width: 20),
            _btn(
              icon: _hangingUp
                  ? Icons.hourglass_empty_rounded
                  : Icons.call_end_rounded,
              color: const Color(0xFFFF5E7D),
              size: 68,
              onTap: _hangUp,
            ),
            const SizedBox(width: 20),
            _btn(
              icon: _camOn ? Icons.videocam_rounded : Icons.videocam_off_rounded,
              color: _camOn
                  ? Colors.white.withOpacity(0.15)
                  : const Color(0xFFFF5E7D),
              onTap: _toggleCam,
            ),
          ]),
        ),
      ]),
    );
  }

  Widget _btn({
    required IconData icon,
    required Color color,
    double size = 54,
    required VoidCallback onTap,
  }) =>
      GestureDetector(
        onTap: onTap,
        child: Container(
          width: size, height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: color,
            border: Border.all(
                color: Colors.white.withOpacity(0.1), width: 1.5),
          ),
          child: Icon(icon, color: Colors.white, size: size * 0.42),
        ),
      );
}

// ── Анимированный градиент ──────────────────────────────────────────────────
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
    [const Color(0xFF200A40), const Color(0xFF0D0B1F), const Color(0xFF1A0A3A)],
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
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final next = (_idx + 1) % _colors.length;
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, __) {
        final t = Curves.easeInOut.transform(_ctrl.value);
        return Container(
          width: double.infinity,
          height: double.infinity,
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

// ── Пульсирующее кольцо ──────────────────────────────────────────────────────
class _PulseRing extends StatefulWidget {
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
        vsync: this, duration: const Duration(milliseconds: 1200))
      ..repeat();
    _scale = Tween(begin: 0.8, end: 1.6).animate(
        CurvedAnimation(parent: _ctrl, curve: Curves.easeOut));
    _opacity = Tween(begin: 0.6, end: 0.0).animate(
        CurvedAnimation(parent: _ctrl, curve: Curves.easeOut));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _ctrl,
        builder: (_, __) => Transform.scale(
          scale: _scale.value,
          child: Opacity(
            opacity: _opacity.value,
            child: Container(
              width: 60, height: 60,
              decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                      color: const Color(0xFF7C6FFF), width: 2)),
            ),
          ),
        ),
      );
}
