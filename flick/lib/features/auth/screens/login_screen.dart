import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});
  @override ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabs;
  final _loginEmail = TextEditingController();
  final _loginPass  = TextEditingController();
  final _regName    = TextEditingController();
  final _regEmail   = TextEditingController();
  final _regPass    = TextEditingController();

  bool _loading = false, _hideLP = true, _hideRP = true;
  String? _error, _success;
  double _strength = 0;
  Color  _strengthColor = Colors.transparent;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
    _regPass.addListener(_calcStrength);
    _tabs.addListener(() => setState(() { _error = null; _success = null; }));
  }

  void _calcStrength() {
    final v = _regPass.text; int s = 0;
    if (v.length >= 6) s++;
    if (v.length >= 10) s++;
    if (RegExp(r'[A-Z]').hasMatch(v)) s++;
    if (RegExp(r'[0-9]').hasMatch(v)) s++;
    if (RegExp(r'[^a-zA-Z0-9]').hasMatch(v)) s++;
    final w = [0.0, 0.25, 0.50, 0.75, 0.90, 1.0];
    final c = [
      Colors.transparent,
      const Color(0xFFFF5E7D),
      const Color(0xFFFBBF24),
      const Color(0xFF60A5FA),
      const Color(0xFF34D399),
      const Color(0xFF34D399),
    ];
    setState(() { _strength = w[s]; _strengthColor = c[s]; });
  }

  @override
  void dispose() {
    _tabs.dispose();
    _loginEmail.dispose(); _loginPass.dispose();
    _regName.dispose(); _regEmail.dispose(); _regPass.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    setState(() { _loading = true; _error = null; _success = null; });
    try {
      final res = await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: _loginEmail.text.trim(),
        password: _loginPass.text,
      );
      // Создаём документ если его ещё нет (для старых пользователей)
      final user = res.user!;
      final doc  = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
      if (!doc.exists) {
        final name = user.displayName ?? _loginEmail.text.split('@').first;
        await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
          'username'   : name.toLowerCase(),
          'displayName': name,
          'email'      : user.email ?? '',
          'avatarUrl'  : '',
          'createdAt'  : FieldValue.serverTimestamp(),
        });
      }
      // Проверяем бан
      final userDoc = await FirebaseFirestore.instance
          .collection('users').doc(user.uid).get();
      if (userDoc.data()?['banned'] == true) {
        await FirebaseAuth.instance.signOut();
        setState(() => _error = 'Ваш аккаунт заблокирован');
        return;
      }
      if (mounted) context.go('/home');
    } on FirebaseAuthException catch (e) {
      setState(() => _error = _err(e.code));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _register() async {
    if (_regName.text.trim().isEmpty) {
      setState(() => _error = 'Введи имя');
      return;
    }
    setState(() { _loading = true; _error = null; _success = null; });
    try {
      final res = await FirebaseAuth.instance.createUserWithEmailAndPassword(
        email: _regEmail.text.trim(),
        password: _regPass.text,
      );
      await res.user?.updateDisplayName(_regName.text.trim());
      setState(() => _success = 'Аккаунт создан! Войди 🎉');
      _tabs.animateTo(0);
    } on FirebaseAuthException catch (e) {
      setState(() => _error = _err(e.code));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _err(String c) => {
    'user-not-found':       'Пользователь не найден',
    'wrong-password':       'Неверный пароль',
    'email-already-in-use': 'Email уже используется',
    'weak-password':        'Пароль минимум 6 символов',
    'invalid-email':        'Некорректный email',
    'invalid-credential':   'Неверный email или пароль',
  }[c] ?? 'Ошибка: $c';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0F),
      body: Stack(children: [
        Positioned.fill(child: CustomPaint(painter: _GridPainter())),
        Positioned(top: -120, left: -150,
          child: _glow(500, const Color(0xFF7C6FFF), 0.15)),
        Positioned(bottom: -100, right: -100,
          child: _glow(400, const Color(0xFF38BDF8), 0.10)),
        SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
              child: Column(children: [
                _brand(),
                const SizedBox(height: 32),
                _card(),
              ]),
            ),
          ),
        ),
      ]),
    );
  }

  Widget _brand() => Column(children: [
    Container(
      width: 60, height: 60,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: const LinearGradient(
          colors: [Color(0xFF7C6FFF), Color(0xFF38BDF8)],
          begin: Alignment.topLeft, end: Alignment.bottomRight),
        boxShadow: [BoxShadow(
          color: const Color(0xFF7C6FFF).withOpacity(0.5), blurRadius: 28)],
      ),
      child: const Center(child: Text('F',
        style: TextStyle(fontFamily: 'Syne', fontSize: 32,
          fontWeight: FontWeight.w800, color: Colors.white))),
    ),
    const SizedBox(height: 16),
    ShaderMask(
      shaderCallback: (b) => const LinearGradient(
        colors: [Colors.white, Color(0xFFB49FFF), Color(0xFF38BDF8)],
        stops: [0.0, 0.55, 1.0]).createShader(b),
      child: const Text('Flick',
        style: TextStyle(fontFamily: 'Syne', fontSize: 36,
          fontWeight: FontWeight.w800, color: Colors.white, letterSpacing: -1.5)),
    ),
  ]);

  Widget _card() => Container(
    decoration: BoxDecoration(
      color: const Color(0xFF13131A),
      borderRadius: BorderRadius.circular(22),
      border: Border.all(color: Colors.white.withOpacity(0.06)),
      boxShadow: [BoxShadow(
        color: Colors.black.withOpacity(0.6), blurRadius: 64)],
    ),
    padding: const EdgeInsets.all(24),
    child: Column(children: [
      _tabBar(),
      const SizedBox(height: 24),
      AnimatedBuilder(
        animation: _tabs,
        builder: (_, __) => AnimatedSwitcher(
          duration: const Duration(milliseconds: 250),
          child: _tabs.index == 0 ? _loginForm() : _registerForm(),
        ),
      ),
      if (_error   != null) ...[const SizedBox(height: 12), _msg(_error!,   true)],
      if (_success != null) ...[const SizedBox(height: 12), _msg(_success!, false)],
    ]),
  );

  Widget _tabBar() => AnimatedBuilder(
    animation: _tabs,
    builder: (_, __) => Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1C1C27),
        borderRadius: BorderRadius.circular(10)),
      padding: const EdgeInsets.all(4),
      child: Row(children: [
        _tabBtn('Войти', 0),
        _tabBtn('Регистрация', 1),
      ]),
    ),
  );

  Widget _tabBtn(String label, int i) {
    final active = _tabs.index == i;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() { _tabs.animateTo(i); }),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          padding: const EdgeInsets.symmetric(vertical: 9),
          decoration: BoxDecoration(
            color: active ? const Color(0xFF13131A) : Colors.transparent,
            borderRadius: BorderRadius.circular(7),
            border: active
                ? Border.all(color: Colors.white.withOpacity(0.06))
                : null,
            boxShadow: active
                ? [BoxShadow(color: Colors.black.withOpacity(0.3), blurRadius: 8)]
                : null,
          ),
          child: Text(label, textAlign: TextAlign.center,
            style: TextStyle(fontFamily: 'DM Sans', fontSize: 14,
              fontWeight: FontWeight.w500,
              color: active ? Colors.white : const Color(0xFF8B8B9E))),
        ),
      ),
    );
  }

  Widget _loginForm() => Column(
    key: const ValueKey('login'),
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _label('EMAIL'), const SizedBox(height: 6),
      _field(_loginEmail, 'твой@email.com', TextInputType.emailAddress),
      const SizedBox(height: 16),
      _label('ПАРОЛЬ'), const SizedBox(height: 6),
      _field(_loginPass, '••••••••', TextInputType.visiblePassword,
        hide: _hideLP, onToggle: () => setState(() => _hideLP = !_hideLP)),
      const SizedBox(height: 24),
      _gradBtn('Войти', _login),
    ]);

  Widget _registerForm() => Column(
    key: const ValueKey('reg'),
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _label('ИМЯ'), const SizedBox(height: 6),
      _field(_regName, 'Как тебя зовут?', TextInputType.name),
      const SizedBox(height: 16),
      _label('EMAIL'), const SizedBox(height: 6),
      _field(_regEmail, 'твой@email.com', TextInputType.emailAddress),
      const SizedBox(height: 16),
      _label('ПАРОЛЬ'), const SizedBox(height: 6),
      _field(_regPass, '••••••••', TextInputType.visiblePassword,
        hide: _hideRP, onToggle: () => setState(() => _hideRP = !_hideRP)),
      const SizedBox(height: 8),
      ClipRRect(
        borderRadius: BorderRadius.circular(99),
        child: LinearProgressIndicator(
          value: _strength, minHeight: 3,
          backgroundColor: const Color(0xFF1C1C27),
          valueColor: AlwaysStoppedAnimation(_strengthColor))),
      const SizedBox(height: 24),
      _gradBtn('Создать аккаунт', _register),
    ]);

  Widget _label(String t) => Text(t,
    style: const TextStyle(fontFamily: 'DM Sans', fontSize: 11,
      fontWeight: FontWeight.w500, color: Color(0xFF8B8B9E), letterSpacing: 0.8));

  Widget _field(TextEditingController c, String hint, TextInputType type,
      {bool? hide, VoidCallback? onToggle}) =>
    TextField(
      controller: c, keyboardType: type, obscureText: hide ?? false,
      style: const TextStyle(fontFamily: 'DM Sans', fontSize: 15,
        color: Color(0xFFF0F0F5)),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: Color(0xFF8B8B9E)),
        suffixIcon: onToggle != null ? IconButton(
          onPressed: onToggle,
          icon: Icon(hide! ? Icons.visibility_off_rounded : Icons.visibility_rounded,
            color: const Color(0xFF8B8B9E), size: 20)) : null,
      ),
    );

  Widget _gradBtn(String label, VoidCallback fn) => GestureDetector(
    onTap: _loading ? null : fn,
    child: Container(
      width: double.infinity, height: 50,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        gradient: const LinearGradient(
          colors: [Color(0xFF7C6FFF), Color(0xFFA78BFA), Color(0xFF38BDF8)],
          stops: [0.0, 0.5, 1.0]),
        boxShadow: [BoxShadow(
          color: const Color(0xFF7C6FFF).withOpacity(0.4),
          blurRadius: 24, offset: const Offset(0, 8))],
      ),
      child: Center(child: _loading
        ? const SizedBox(width: 20, height: 20,
            child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
        : Text(label, style: const TextStyle(fontFamily: 'Syne', fontSize: 15,
            fontWeight: FontWeight.w700, color: Colors.white))),
    ),
  );

  Widget _msg(String t, bool err) => Container(
    width: double.infinity,
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
    decoration: BoxDecoration(
      color: (err ? const Color(0xFFFF5E7D) : const Color(0xFF34D399)).withOpacity(0.1),
      borderRadius: BorderRadius.circular(10),
      border: Border.all(
        color: (err ? const Color(0xFFFF5E7D) : const Color(0xFF34D399)).withOpacity(0.2)),
    ),
    child: Text(t, textAlign: TextAlign.center,
      style: TextStyle(fontFamily: 'DM Sans', fontSize: 13,
        color: err ? const Color(0xFFFF5E7D) : const Color(0xFF34D399))),
  );

  Widget _glow(double s, Color c, double o) => Container(
    width: s, height: s,
    decoration: BoxDecoration(shape: BoxShape.circle, color: c.withOpacity(o)));
}

class _GridPainter extends CustomPainter {
  @override
  void paint(Canvas c, Size s) {
    final h = Paint()..color = const Color(0xFF7C6FFF).withOpacity(0.05)..strokeWidth = 1;
    final v = Paint()..color = const Color(0xFF38BDF8).withOpacity(0.04)..strokeWidth = 1;
    for (double y = 0; y < s.height; y += 40)
      c.drawLine(Offset(0, y), Offset(s.width, y), h);
    for (double x = 0; x < s.width; x += 40)
      c.drawLine(Offset(x, 0), Offset(x, s.height), v);
  }
  @override bool shouldRepaint(_) => false;
}