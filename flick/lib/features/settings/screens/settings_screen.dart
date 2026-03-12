import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:image_picker/image_picker.dart';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'dart:io';
import 'dart:convert';
import '../../../app.dart';
import '../../../core/wallpapers.dart';

const _bannerPresets = [
  [Color(0xFF7C6FFF), Color(0xFF38BDF8)],
  [Color(0xFFFF5E7D), Color(0xFFFF9A3C)],
  [Color(0xFF34D399), Color(0xFF38BDF8)],
  [Color(0xFFFBBF24), Color(0xFFFF5E7D)],
  [Color(0xFFA78BFA), Color(0xFFF472B6)],
  [Color(0xFF0EA5E9), Color(0xFF6366F1)],
  [Color(0xFF10B981), Color(0xFFFBBF24)],
  [Color(0xFFEF4444), Color(0xFF7C3AED)],
];

const _appIcons = [
  {'key': 'default', 'asset': 'assets/icons/icon_default.png', 'label': 'Стандарт'},
  {'key': 'green',   'asset': 'assets/icons/icon_green.png',   'label': 'Зелёный'},
  {'key': 'pink',    'asset': 'assets/icons/icon_pink.png',    'label': 'Розовый'},
  {'key': 'orange',  'asset': 'assets/icons/icon_orange.png',  'label': 'Оранж'},
  {'key': 'blue',    'asset': 'assets/icons/icon_blue.png',    'label': 'Синий'},
];

const _iconChannel = MethodChannel('com.selov.flick/icon');
Future<void> _setAppIcon(String key) async {
  try { await _iconChannel.invokeMethod('setIcon', {'icon': key}); } catch (_) {}
}

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});
  @override ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  final _auth = FirebaseAuth.instance;
  final _db   = FirebaseFirestore.instance;

  static const _cloudName = 'dpy1me6tk';
  static const _apiKey    = '321197243977146';
  static const _apiSecret = 'ntdiE6OpKzaUzVwRhCiwwLrS1QM';

  String  _username    = '';
  String  _email       = '';
  String? _avatarUrl;
  int     _bannerIdx   = 0;
  int     _iconIdx     = 0;
  String  _wallpaperId = 'dark_1';
  bool    _uploading   = false;

  // Приватность
  bool _hideEmail   = false;
  bool _hideAvatar  = false;
  bool _hideGifts   = false;
  bool _hideStories = false;

  // Секретное меню
  Timer?  _holdTimer;
  bool    _holdActive    = false;
  double  _holdProgress  = 0;
  bool    _showSecretField = false;
  final   _secretCtrl    = TextEditingController();
  String  _secretError   = '';

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  @override
  void dispose() {
    _holdTimer?.cancel();
    _secretCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadProfile() async {
    final uid  = _auth.currentUser?.uid ?? '';
    final doc  = await _db.collection('users').doc(uid).get();
    final data = doc.data();
    final privacy = data?['privacy'] as Map<String, dynamic>? ?? {};
    setState(() {
      _username    = data?['username']    ?? '';
      _email       = _auth.currentUser?.email ?? '';
      _avatarUrl   = data?['avatarUrl'];
      _bannerIdx   = (data?['bannerIdx']  ?? 0) as int;
      _iconIdx     = (data?['iconIdx']    ?? 0) as int;
      _wallpaperId = data?['wallpaperId'] ?? 'dark_1';
      _hideEmail   = privacy['hideEmail']   == true;
      _hideAvatar  = privacy['hideAvatar']  == true;
      _hideGifts   = privacy['hideGifts']   == true;
      _hideStories = privacy['hideStories'] == true;
    });
  }

  String _sign(String params) {
    final bytes = utf8.encode('$params$_apiSecret');
    return sha1.convert(bytes).toString();
  }

  Future<String?> _uploadAvatar(File file) async {
    final ts        = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final folder    = 'flick/avatars';
    final signature = _sign('folder=$folder&timestamp=$ts');
    final uri = Uri.parse('https://api.cloudinary.com/v1_1/$_cloudName/image/upload');
    final req = http.MultipartRequest('POST', uri)
      ..fields['api_key']   = _apiKey
      ..fields['timestamp'] = ts.toString()
      ..fields['folder']    = folder
      ..fields['signature'] = signature
      ..files.add(await http.MultipartFile.fromPath('file', file.path));
    final res  = await req.send();
    final body = await res.stream.bytesToString();
    return jsonDecode(body)['secure_url'] as String?;
  }

  // ── Секретное меню ───────────────────────────────────────────────────────
  void _startHold() {
    _holdProgress = 0;
    _holdActive   = true;
    setState(() {});
    _holdTimer = Timer.periodic(const Duration(milliseconds: 100), (t) {
      if (!mounted) { t.cancel(); return; }
      setState(() => _holdProgress += 100 / 20000 * 100); // 20 сек = 100%
      if (_holdProgress >= 100) {
        t.cancel();
        _holdActive = false;
        _holdProgress = 0;
        HapticFeedback.heavyImpact();
        setState(() { _showSecretField = true; _secretError = ''; });
      }
    });
  }

  void _cancelHold() {
    _holdTimer?.cancel();
    if (mounted) setState(() { _holdActive = false; _holdProgress = 0; });
  }

  Future<void> _checkPassword() async {
    final input = _secretCtrl.text.trim();
    _secretCtrl.clear();

    // Читаем пароли из Firestore
    final doc = await _db.collection('config').doc('admin').get();
    final data = doc.data();
    if (data == null) {
      setState(() => _secretError = 'Конфигурация не найдена');
      return;
    }

    final ownerPass = data['ownerPassword'] as String? ?? '';
    final adminPass = data['adminPassword'] as String? ?? '';

    if (input == ownerPass) {
      setState(() { _showSecretField = false; _secretError = ''; });
      _openAdminPanel(role: 'owner');
    } else if (input == adminPass) {
      setState(() { _showSecretField = false; _secretError = ''; });
      _openAdminPanel(role: 'admin');
    } else {
      HapticFeedback.vibrate();
      setState(() => _secretError = 'Неверный пароль');
    }
  }

  void _openAdminPanel({required String role}) {
    Navigator.push(context, MaterialPageRoute(
        builder: (_) => _AdminPanelScreen(role: role)));
  }

  Future<void> _savePrivacy({
    bool? hideEmail,
    bool? hideAvatar,
    bool? hideGifts,
    bool? hideStories,
  }) async {
    final uid = _auth.currentUser?.uid ?? '';
    final updated = {
      'hideEmail'  : hideEmail   ?? _hideEmail,
      'hideAvatar' : hideAvatar  ?? _hideAvatar,
      'hideGifts'  : hideGifts   ?? _hideGifts,
      'hideStories': hideStories ?? _hideStories,
    };
    await _db.collection('users').doc(uid).update({'privacy': updated});
    setState(() {
      if (hideEmail   != null) _hideEmail   = hideEmail;
      if (hideAvatar  != null) _hideAvatar  = hideAvatar;
      if (hideGifts   != null) _hideGifts   = hideGifts;
      if (hideStories != null) _hideStories = hideStories;
    });
  }

  Future<void> _saveBanner(int idx) async {
    final uid = _auth.currentUser?.uid ?? '';
    await _db.collection('users').doc(uid).update({'bannerIdx': idx});
    setState(() => _bannerIdx = idx);
  }

  Future<void> _saveIcon(int idx) async {
    final uid = _auth.currentUser?.uid ?? '';
    await _db.collection('users').doc(uid).update({'iconIdx': idx});
    setState(() => _iconIdx = idx);
    await _setAppIcon(_appIcons[idx]['key']!);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Иконка «${_appIcons[idx]['label']}» выбрана!',
          style: const TextStyle(fontFamily: 'DM Sans')),
        backgroundColor: const Color(0xFF7C6FFF),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ));
    }
  }

  Future<void> _saveWallpaper(String id) async {
    final uid = _auth.currentUser?.uid ?? '';
    await _db.collection('users').doc(uid).update({'wallpaperId': id});
    setState(() => _wallpaperId = id);
  }

  Future<void> _changeAvatar() async {
    final picker = ImagePicker();
    final xfile  = await picker.pickImage(source: ImageSource.gallery, imageQuality: 80);
    if (xfile == null) return;
    setState(() => _uploading = true);
    try {
      final url = await _uploadAvatar(File(xfile.path));
      if (url != null) {
        final uid = _auth.currentUser?.uid ?? '';
        await _db.collection('users').doc(uid).update({'avatarUrl': url});
        setState(() => _avatarUrl = url);
      }
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Ошибка загрузки аватара')));
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _editUsername() async {
    final ctrl = TextEditingController(text: _username);
    await showDialog(context: context, builder: (dialogCtx) => AlertDialog(
      backgroundColor: const Color(0xFF13131A),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: const Text('Изменить имя', style: TextStyle(
          fontFamily: 'Syne', fontWeight: FontWeight.w800, color: Colors.white)),
      content: TextField(
        controller: ctrl, autofocus: true,
        style: const TextStyle(fontFamily: 'DM Sans', color: Colors.white),
        decoration: const InputDecoration(hintText: 'Новое имя')),
      actionsAlignment: MainAxisAlignment.spaceBetween,
      actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogCtx).pop(),
          child: const Text('Отмена', style: TextStyle(color: Color(0xFF8B8B9E)))),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF7C6FFF),
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12)),
          onPressed: () async {
            final newName = ctrl.text.trim();
            if (newName.isEmpty) return;
            final uid = _auth.currentUser?.uid ?? '';
            await _db.collection('users').doc(uid).update({'username': newName});
            setState(() => _username = newName);
            if (mounted) Navigator.of(dialogCtx).pop();
          },
          child: const Text('Сохранить',
            style: TextStyle(fontFamily: 'DM Sans', fontWeight: FontWeight.w600,
                color: Colors.white))),
      ],
    ));
  }

  // ── Обои ──────────────────────────────────────────────────────────────────
  void _showWallpaperSheet() {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final categories = ['Тёмные', 'Светлые', 'Природа', 'Градиенты'];

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setSheet) => DraggableScrollableSheet(
          initialChildSize: 0.85,
          maxChildSize: 0.95,
          minChildSize: 0.5,
          builder: (_, scrollCtrl) => Container(
            decoration: BoxDecoration(
              color: dark ? const Color(0xFF13131A) : Colors.white,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
              border: Border.all(color: Colors.white.withOpacity(0.06)),
            ),
            child: Column(children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
                child: Column(children: [
                  Container(width: 40, height: 4,
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(99))),
                  const SizedBox(height: 16),
                  const Text('Обои чата', style: TextStyle(
                      fontFamily: 'Syne', fontSize: 18,
                      fontWeight: FontWeight.w800, color: Colors.white)),
                  const SizedBox(height: 4),
                  Text('Выбери фон для всех чатов',
                    style: TextStyle(fontFamily: 'DM Sans', fontSize: 13,
                        color: Colors.white.withOpacity(0.5))),
                  const SizedBox(height: 16),
                ]),
              ),
              Expanded(
                child: ListView(
                  controller: scrollCtrl,
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
                  children: [
                    // Без обоев
                    Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: GestureDetector(
                        onTap: () async {
                          await _saveWallpaper('none');
                          setSheet(() {});
                          if (mounted) Navigator.pop(context);
                        },
                        child: Container(
                          height: 60,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: _wallpaperId == 'none'
                                  ? const Color(0xFF7C6FFF)
                                  : Colors.white.withOpacity(0.1),
                              width: _wallpaperId == 'none' ? 2 : 1),
                            color: dark
                                ? const Color(0xFF1C1C27)
                                : const Color(0xFFF0F2F8),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.hide_image_rounded,
                                color: _wallpaperId == 'none'
                                    ? const Color(0xFF7C6FFF)
                                    : const Color(0xFF8B8B9E)),
                              const SizedBox(width: 8),
                              Text('Без обоев',
                                style: TextStyle(fontFamily: 'DM Sans',
                                  fontSize: 14, fontWeight: FontWeight.w500,
                                  color: _wallpaperId == 'none'
                                      ? const Color(0xFF7C6FFF)
                                      : const Color(0xFF8B8B9E))),
                            ],
                          ),
                        ),
                      ),
                    ),

                    for (final cat in categories) ...[
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10, top: 4),
                        child: Text(cat.toUpperCase(),
                          style: const TextStyle(fontFamily: 'DM Sans',
                              fontSize: 11, fontWeight: FontWeight.w500,
                              color: Color(0xFF8B8B9E), letterSpacing: 0.8)),
                      ),
                      GridView.count(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        crossAxisCount: 4,
                        crossAxisSpacing: 10,
                        mainAxisSpacing: 10,
                        childAspectRatio: 0.6,
                        children: wallpapers
                            .where((w) => w.category == cat)
                            .map((w) {
                          final selected = _wallpaperId == w.id;
                          return GestureDetector(
                            onTap: () async {
                              await _saveWallpaper(w.id);
                              setSheet(() {});
                              if (mounted) Navigator.pop(context);
                            },
                            child: Column(children: [
                              Expanded(
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 200),
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(12),
                                    gradient: LinearGradient(
                                      colors: [w.color1, w.color2],
                                      begin: Alignment.topCenter,
                                      end: Alignment.bottomCenter),
                                    border: Border.all(
                                      color: selected
                                          ? const Color(0xFF7C6FFF)
                                          : Colors.white.withOpacity(0.1),
                                      width: selected ? 2.5 : 1),
                                    boxShadow: selected ? [BoxShadow(
                                      color: const Color(0xFF7C6FFF).withOpacity(0.4),
                                      blurRadius: 12)] : [],
                                  ),
                                  child: selected
                                      ? const Center(child: Icon(
                                          Icons.check_rounded,
                                          color: Colors.white, size: 22))
                                      : null,
                                ),
                              ),
                              const SizedBox(height: 5),
                              Text(w.label,
                                style: TextStyle(fontFamily: 'DM Sans',
                                  fontSize: 11,
                                  fontWeight: selected
                                      ? FontWeight.w600 : FontWeight.w400,
                                  color: selected
                                      ? const Color(0xFF7C6FFF)
                                      : const Color(0xFF8B8B9E))),
                            ]),
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 16),
                    ],
                  ],
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }

  void _showProfileSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setSheet) {
          final dark   = Theme.of(context).brightness == Brightness.dark;
          final colors = _bannerPresets[_bannerIdx];
          return Container(
            decoration: BoxDecoration(
              color: dark ? const Color(0xFF0A0A0F) : const Color(0xFFF0F2F8),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
            ),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
                  gradient: LinearGradient(colors: colors,
                      begin: Alignment.topLeft, end: Alignment.bottomRight),
                ),
                padding: const EdgeInsets.fromLTRB(24, 20, 24, 28),
                child: Column(children: [
                  Container(width: 40, height: 4,
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.3),
                      borderRadius: BorderRadius.circular(99))),
                  const SizedBox(height: 20),
                  Stack(children: [
                    GestureDetector(
                      onTap: () async { await _changeAvatar(); setSheet(() {}); },
                      child: Container(
                        width: 86, height: 86,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.white.withOpacity(0.2),
                          border: Border.all(color: Colors.white.withOpacity(0.5), width: 3),
                          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.3), blurRadius: 20)],
                        ),
                        child: _uploading
                            ? const Center(child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                            : _avatarUrl != null
                                ? ClipOval(child: Image.network(_avatarUrl!, width: 86, height: 86, fit: BoxFit.cover))
                                : Center(child: Text(
                                    _username.isNotEmpty ? _username[0].toUpperCase() : '?',
                                    style: const TextStyle(fontFamily: 'Syne', fontSize: 36,
                                        fontWeight: FontWeight.w800, color: Colors.white))),
                      ),
                    ),
                    Positioned(bottom: 0, right: 0,
                      child: GestureDetector(
                        onTap: () async { await _changeAvatar(); setSheet(() {}); },
                        child: Container(
                          width: 26, height: 26,
                          decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.white,
                            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.2), blurRadius: 8)]),
                          child: const Icon(Icons.camera_alt_rounded, color: Color(0xFF7C6FFF), size: 14)),
                      )),
                  ]),
                  const SizedBox(height: 12),
                  Text(_username, style: const TextStyle(fontFamily: 'Syne', fontSize: 22,
                      fontWeight: FontWeight.w800, color: Colors.white)),
                  const SizedBox(height: 2),
                  Text(_email, style: TextStyle(fontFamily: 'DM Sans', fontSize: 13,
                      color: Colors.white.withOpacity(0.7))),
                  const SizedBox(height: 20),
                  Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    for (int i = 0; i < _bannerPresets.length; i++)
                      GestureDetector(
                        onTap: () async { await _saveBanner(i); setSheet(() {}); },
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          margin: const EdgeInsets.symmetric(horizontal: 5),
                          width:  i == _bannerIdx ? 32 : 24,
                          height: i == _bannerIdx ? 32 : 24,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: LinearGradient(colors: _bannerPresets[i],
                                begin: Alignment.topLeft, end: Alignment.bottomRight),
                            border: i == _bannerIdx ? Border.all(color: Colors.white, width: 2.5) : null,
                            boxShadow: i == _bannerIdx
                                ? [BoxShadow(color: Colors.black.withOpacity(0.3), blurRadius: 8)] : null,
                          ),
                        ),
                      ),
                  ]),
                ]),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 20, 24, 40),
                child: Column(children: [
                  _sheetBtn(icon: Icons.edit_rounded, label: 'Изменить имя', dark: dark,
                    onTap: () async { Navigator.pop(context); await _editUsername(); }),
                  const SizedBox(height: 10),
                  _sheetBtn(icon: Icons.image_rounded, label: 'Сменить аватар', dark: dark,
                    onTap: () async { await _changeAvatar(); setSheet(() {}); }),
                  const SizedBox(height: 10),
                  _sheetBtn(icon: Icons.logout_rounded, label: 'Выйти', dark: dark,
                    color: const Color(0xFFFF5E7D),
                    onTap: () async {
                      Navigator.pop(context);
                      await _auth.signOut();
                      if (mounted) context.go('/login');
                    }),
                  const SizedBox(height: 20),
                  // Подарки
                  Row(children: [
                    const Text('🎁', style: TextStyle(fontSize: 16)),
                    const SizedBox(width: 8),
                    const Text('ПОДАРКИ', style: TextStyle(fontFamily: 'DM Sans',
                        fontSize: 11, fontWeight: FontWeight.w600,
                        color: Color(0xFF8B8B9E), letterSpacing: 0.8)),
                  ]),
                  const SizedBox(height: 12),
                  GridView.count(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    crossAxisCount: 4,
                    crossAxisSpacing: 10,
                    mainAxisSpacing: 10,
                    childAspectRatio: 0.85,
                    children: _gifts.map((g) {
                      final c1 = Color(g['color1'] as int);
                      final c2 = Color(g['color2'] as int);
                      return Column(children: [
                        Container(
                          width: 58, height: 58,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(16),
                            gradient: LinearGradient(
                              colors: [c1.withOpacity(0.2), c2.withOpacity(0.2)],
                              begin: Alignment.topLeft, end: Alignment.bottomRight),
                            border: Border.all(color: c1.withOpacity(0.4), width: 1.5),
                            boxShadow: [BoxShadow(color: c1.withOpacity(0.15), blurRadius: 10)],
                          ),
                          child: Center(child: Text(g['emoji'] as String,
                              style: const TextStyle(fontSize: 26))),
                        ),
                        const SizedBox(height: 5),
                        Text(g['label'] as String,
                          style: const TextStyle(fontFamily: 'DM Sans', fontSize: 10,
                              fontWeight: FontWeight.w500, color: Color(0xFF8B8B9E)),
                          textAlign: TextAlign.center, maxLines: 1,
                          overflow: TextOverflow.ellipsis),
                      ]);
                    }).toList(),
                  ),
                ]),
              ),
            ]),
          );
        },
      ),
    );
  }

  void _showIconSheet() {
    final dark = Theme.of(context).brightness == Brightness.dark;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setSheet) => Container(
          decoration: BoxDecoration(
            color: dark ? const Color(0xFF13131A) : Colors.white,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
            border: Border.all(color: Colors.white.withOpacity(0.06)),
          ),
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 40),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(width: 40, height: 4,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.2),
                borderRadius: BorderRadius.circular(99))),
            const SizedBox(height: 20),
            const Text('Иконка приложения', style: TextStyle(fontFamily: 'Syne',
                fontSize: 18, fontWeight: FontWeight.w800, color: Colors.white)),
            const SizedBox(height: 6),
            Text('Выбери свой стиль', style: TextStyle(fontFamily: 'DM Sans',
                fontSize: 13, color: Colors.white.withOpacity(0.5))),
            const SizedBox(height: 24),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3, crossAxisSpacing: 16,
                mainAxisSpacing: 16, childAspectRatio: 0.8),
              itemCount: _appIcons.length,
              itemBuilder: (_, i) {
                final ic       = _appIcons[i];
                final selected = i == _iconIdx;
                return GestureDetector(
                  onTap: () async {
                    await _saveIcon(i); setSheet(() {});
                    if (mounted) Navigator.pop(context);
                  },
                  child: Column(children: [
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      width: 72, height: 72,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(18),
                        boxShadow: selected ? [BoxShadow(
                          color: const Color(0xFF7C6FFF).withOpacity(0.6),
                          blurRadius: 20, spreadRadius: 2)] : [],
                        border: selected
                            ? Border.all(color: const Color(0xFF7C6FFF), width: 3)
                            : Border.all(color: Colors.white.withOpacity(0.1), width: 1.5),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: Image.asset(ic['asset']!, width: 72, height: 72, fit: BoxFit.contain),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(ic['label']!, style: TextStyle(fontFamily: 'DM Sans', fontSize: 12,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
                      color: selected ? const Color(0xFF7C6FFF) : const Color(0xFF8B8B9E))),
                    if (selected) Container(margin: const EdgeInsets.only(top: 4),
                      width: 6, height: 6,
                      decoration: const BoxDecoration(shape: BoxShape.circle, color: Color(0xFF7C6FFF))),
                  ]),
                );
              },
            ),
            const SizedBox(height: 16),
          ]),
        ),
      ),
    );
  }

  Widget _sheetBtn({required IconData icon, required String label,
      required bool dark, Color? color, required VoidCallback onTap}) =>
    GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: dark ? const Color(0xFF1C1C27) : const Color(0xFFF0F2F8),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white.withOpacity(0.06)),
        ),
        child: Row(children: [
          Icon(icon, color: color ?? const Color(0xFF7C6FFF), size: 20),
          const SizedBox(width: 12),
          Text(label, style: TextStyle(fontFamily: 'DM Sans', fontSize: 15,
            fontWeight: FontWeight.w500,
            color: color ?? (dark ? Colors.white : const Color(0xFF0F0F1A)))),
        ]),
      ),
    );

  @override
  Widget build(BuildContext context) {
    final dark       = Theme.of(context).brightness == Brightness.dark;
    final bg         = dark ? const Color(0xFF0A0A0F) : const Color(0xFFF0F2F8);
    final surface    = dark ? const Color(0xFF13131A) : Colors.white;
    final isDark     = ref.watch(themeModeProvider) == ThemeMode.dark;
    final colors     = _bannerPresets[_bannerIdx];
    final curIcon    = _appIcons[_iconIdx];
    final curWall    = wallpaperById(_wallpaperId);

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        backgroundColor: surface,
        title: const Text('Настройки', style: TextStyle(
            fontFamily: 'Syne', fontWeight: FontWeight.w800)),
      ),
      body: ListView(children: [
        const SizedBox(height: 16),

        // Профиль
        GestureDetector(
          onTap: _showProfileSheet,
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              gradient: LinearGradient(colors: colors,
                  begin: Alignment.topLeft, end: Alignment.bottomRight),
              boxShadow: [BoxShadow(color: colors[0].withOpacity(0.4), blurRadius: 24)],
            ),
            padding: const EdgeInsets.all(20),
            child: Row(children: [
              Container(
                width: 56, height: 56,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withOpacity(0.2),
                  border: Border.all(color: Colors.white.withOpacity(0.5), width: 2),
                ),
                child: _avatarUrl != null
                    ? ClipOval(child: Image.network(_avatarUrl!, width: 56, height: 56, fit: BoxFit.cover))
                    : Center(child: Text(
                        _username.isNotEmpty ? _username[0].toUpperCase() : '?',
                        style: const TextStyle(fontFamily: 'Syne', fontSize: 24,
                            fontWeight: FontWeight.w800, color: Colors.white))),
              ),
              const SizedBox(width: 14),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(_username, style: const TextStyle(fontFamily: 'Syne', fontSize: 17,
                    fontWeight: FontWeight.w800, color: Colors.white)),
                Text(_email, style: TextStyle(fontFamily: 'DM Sans', fontSize: 13,
                    color: Colors.white.withOpacity(0.7))),
              ])),
              const Icon(Icons.chevron_right_rounded, color: Colors.white),
            ]),
          ),
        ),

        const SizedBox(height: 20),

        // Оформление
        _section('ОФОРМЛЕНИЕ', [
          _tile(icon: Icons.dark_mode_rounded, title: 'Тёмная тема',
            surface: surface, dark: dark,
            trailing: Switch(
              value: isDark,
              onChanged: (_) => ref.read(themeModeProvider.notifier).toggle(),
              activeColor: const Color(0xFF7C6FFF),
            )),
        ], dark),

        const SizedBox(height: 12),

        // Обои
        _section('ОБОИ ЧАТА', [
          GestureDetector(
            onTap: _showWallpaperSheet,
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 3),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white.withOpacity(0.06)),
              ),
              child: Row(children: [
                Container(
                  width: 40, height: 40,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    gradient: curWall != null
                        ? LinearGradient(colors: [curWall.color1, curWall.color2],
                            begin: Alignment.topLeft, end: Alignment.bottomRight)
                        : null,
                    color: curWall == null
                        ? (dark ? const Color(0xFF2A2A3D) : const Color(0xFFE8E8F0))
                        : null,
                    border: Border.all(color: Colors.white.withOpacity(0.1)),
                  ),
                  child: curWall == null
                      ? const Icon(Icons.hide_image_rounded,
                          color: Color(0xFF8B8B9E), size: 18)
                      : null,
                ),
                const SizedBox(width: 14),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(curWall?.label ?? 'Без обоев',
                    style: TextStyle(fontFamily: 'DM Sans', fontSize: 15,
                      fontWeight: FontWeight.w500,
                      color: dark ? Colors.white : const Color(0xFF0F0F1A))),
                  Text(curWall?.category ?? 'По умолчанию',
                    style: const TextStyle(fontFamily: 'DM Sans', fontSize: 12,
                        color: Color(0xFF8B8B9E))),
                ])),
                const Icon(Icons.chevron_right_rounded, color: Color(0xFF8B8B9E)),
              ]),
            ),
          ),
        ], dark),

        const SizedBox(height: 12),

        // Иконка
        _section('ИКОНКА ПРИЛОЖЕНИЯ', [
          GestureDetector(
            onTap: _showIconSheet,
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 3),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white.withOpacity(0.06)),
              ),
              child: Row(children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Image.asset(curIcon['asset']!, width: 40, height: 40, fit: BoxFit.contain),
                ),
                const SizedBox(width: 14),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(curIcon['label']!, style: TextStyle(fontFamily: 'DM Sans', fontSize: 15,
                    fontWeight: FontWeight.w500,
                    color: dark ? Colors.white : const Color(0xFF0F0F1A))),
                  const Text('Нажми чтобы изменить',
                    style: TextStyle(fontFamily: 'DM Sans', fontSize: 12, color: Color(0xFF8B8B9E))),
                ])),
                const Icon(Icons.chevron_right_rounded, color: Color(0xFF8B8B9E)),
              ]),
            ),
          ),
        ], dark),

        const SizedBox(height: 12),

        // Приватность
        _section('ПРИВАТНОСТЬ', [
          _tile(
            icon: Icons.email_rounded,
            title: 'Скрыть почту',
            surface: surface, dark: dark,
            trailing: Switch(
              value: _hideEmail,
              onChanged: (v) => _savePrivacy(hideEmail: v),
              activeColor: const Color(0xFF7C6FFF),
            ),
          ),
          _tile(
            icon: Icons.face_rounded,
            title: 'Скрыть аватарку',
            surface: surface, dark: dark,
            trailing: Switch(
              value: _hideAvatar,
              onChanged: (v) => _savePrivacy(hideAvatar: v),
              activeColor: const Color(0xFF7C6FFF),
            ),
          ),
          _tile(
            icon: Icons.card_giftcard_rounded,
            title: 'Скрыть подарки',
            surface: surface, dark: dark,
            trailing: Switch(
              value: _hideGifts,
              onChanged: (v) => _savePrivacy(hideGifts: v),
              activeColor: const Color(0xFF7C6FFF),
            ),
          ),
          _tile(
            icon: Icons.auto_stories_rounded,
            title: 'Скрыть истории',
            surface: surface, dark: dark,
            trailing: Switch(
              value: _hideStories,
              onChanged: (v) => _savePrivacy(hideStories: v),
              activeColor: const Color(0xFF7C6FFF),
            ),
          ),
        ], dark),

        const SizedBox(height: 24),

        // Версия приложения
        Center(
          child: GestureDetector(
            onLongPressStart: (_) => _startHold(),
            onLongPressEnd:   (_) => _cancelHold(),
            child: Stack(alignment: Alignment.center, children: [
              if (_holdActive)
                SizedBox(
                  width: 80, height: 80,
                  child: CircularProgressIndicator(
                    value: _holdProgress / 100,
                    strokeWidth: 2,
                    color: const Color(0xFF7C6FFF).withOpacity(0.5),
                    backgroundColor: Colors.transparent,
                  ),
                ),
              Column(mainAxisSize: MainAxisSize.min, children: [
                Text('Flick', style: TextStyle(fontFamily: 'Syne',
                    fontSize: 13, fontWeight: FontWeight.w700,
                    color: const Color(0xFF8B8B9E).withOpacity(0.6))),
                Text('v1.0.2', style: TextStyle(fontFamily: 'DM Sans',
                    fontSize: 12,
                    color: const Color(0xFF8B8B9E).withOpacity(0.4))),
              ]),
            ]),
          ),
        ),

        // Поле ввода пароля
        if (_showSecretField) ...[
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                decoration: BoxDecoration(
                  color: dark ? const Color(0xFF1C1C27) : Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: _secretError.isNotEmpty
                        ? const Color(0xFFFF5E7D)
                        : const Color(0xFF7C6FFF).withOpacity(0.4)),
                ),
                child: Row(children: [
                  const Icon(Icons.lock_rounded, color: Color(0xFF7C6FFF), size: 18),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: _secretCtrl,
                      autofocus: true,
                      obscureText: true,
                      style: const TextStyle(fontFamily: 'DM Sans',
                          fontSize: 14, color: Colors.white),
                      decoration: const InputDecoration(
                        hintText: 'Введи пароль...',
                        hintStyle: TextStyle(color: Color(0xFF8B8B9E)),
                        border: InputBorder.none,
                        isDense: true,
                      ),
                      onSubmitted: (_) => _checkPassword(),
                    ),
                  ),
                  GestureDetector(
                    onTap: _checkPassword,
                    child: const Icon(Icons.arrow_forward_rounded,
                        color: Color(0xFF7C6FFF), size: 20)),
                ]),
              ),
              if (_secretError.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(_secretError, style: const TextStyle(
                    fontFamily: 'DM Sans', fontSize: 12,
                    color: Color(0xFFFF5E7D))),
              ],
            ]),
          ),
        ],

        const SizedBox(height: 32),
      ]),
    );
  }

  static const _gifts = [
    {'emoji': '⭐', 'label': 'Звезда',    'color1': 0xFFFFD700, 'color2': 0xFFFF9A3C},
    {'emoji': '❤️', 'label': 'Сердце',    'color1': 0xFFFF5E7D, 'color2': 0xFFFF2D55},
    {'emoji': '🔥', 'label': 'Огонь',     'color1': 0xFFFF6B00, 'color2': 0xFFFF9A3C},
    {'emoji': '👑', 'label': 'Корона',    'color1': 0xFFFFD700, 'color2': 0xFFFFA500},
    {'emoji': '💎', 'label': 'Бриллиант', 'color1': 0xFF38BDF8, 'color2': 0xFF7C6FFF},
    {'emoji': '🚀', 'label': 'Ракета',    'color1': 0xFF7C6FFF, 'color2': 0xFF38BDF8},
    {'emoji': '🏆', 'label': 'Кубок',     'color1': 0xFFFFD700, 'color2': 0xFF34D399},
    {'emoji': '✨', 'label': 'Магия',     'color1': 0xFFA78BFA, 'color2': 0xFFF472B6},
  ];

  void _showGiftsSheet() {
    final dark = Theme.of(context).brightness == Brightness.dark;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => Container(
        decoration: BoxDecoration(
          color: dark ? const Color(0xFF13131A) : Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          border: Border.all(color: Colors.white.withOpacity(0.06)),
        ),
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 40),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 40, height: 4,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.2),
              borderRadius: BorderRadius.circular(99))),
          const SizedBox(height: 20),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            const Text('🎁', style: TextStyle(fontSize: 22)),
            const SizedBox(width: 8),
            const Text('ПОДАРКИ', style: TextStyle(fontFamily: 'Syne',
                fontSize: 18, fontWeight: FontWeight.w800, color: Colors.white)),
          ]),
          const SizedBox(height: 6),
          Text('Твоя коллекция', style: TextStyle(fontFamily: 'DM Sans',
              fontSize: 13, color: Colors.white.withOpacity(0.5))),
          const SizedBox(height: 24),
          GridView.count(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisCount: 4,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            childAspectRatio: 0.85,
            children: _gifts.map((g) {
              final c1 = Color(g['color1'] as int);
              final c2 = Color(g['color2'] as int);
              return Column(children: [
                Container(
                  width: 64, height: 64,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(18),
                    gradient: LinearGradient(
                      colors: [c1.withOpacity(0.2), c2.withOpacity(0.2)],
                      begin: Alignment.topLeft, end: Alignment.bottomRight),
                    border: Border.all(color: c1.withOpacity(0.4), width: 1.5),
                    boxShadow: [BoxShadow(color: c1.withOpacity(0.2), blurRadius: 12)],
                  ),
                  child: Center(child: Text(g['emoji'] as String,
                      style: const TextStyle(fontSize: 28))),
                ),
                const SizedBox(height: 6),
                Text(g['label'] as String,
                  style: const TextStyle(fontFamily: 'DM Sans', fontSize: 11,
                      fontWeight: FontWeight.w500, color: Color(0xFF8B8B9E)),
                  textAlign: TextAlign.center),
              ]);
            }).toList(),
          ),
        ]),
      ),
    );
  }

  Widget _section(String title, List<Widget> items, bool dark) =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
          child: Text(title, style: const TextStyle(fontFamily: 'DM Sans',
              fontSize: 11, fontWeight: FontWeight.w500,
              color: Color(0xFF8B8B9E), letterSpacing: 0.8)),
        ),
        ...items,
      ]);

  Widget _tile({required IconData icon, required String title,
      required Color surface, required bool dark,
      Color? color, Widget? trailing, VoidCallback? onTap}) =>
    Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 3),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withOpacity(0.06)),
      ),
      child: ListTile(
        leading: Icon(icon, color: color ?? const Color(0xFF7C6FFF)),
        title: Text(title, style: TextStyle(fontFamily: 'DM Sans', fontSize: 15,
          color: color ?? (dark ? const Color(0xFFF0F0F5) : const Color(0xFF0F0F1A)))),
        trailing: trailing ?? (onTap != null
            ? const Icon(Icons.chevron_right_rounded, color: Color(0xFF8B8B9E)) : null),
        onTap: onTap,
      ),
    );
}

// ── Панель администратора ─────────────────────────────────────────────────────
class _AdminPanelScreen extends StatefulWidget {
  final String role; // 'owner' | 'admin'
  const _AdminPanelScreen({required this.role});
  @override State<_AdminPanelScreen> createState() => _AdminPanelScreenState();
}

class _AdminPanelScreenState extends State<_AdminPanelScreen> {
  final _db   = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;

  List<Map<String, dynamic>> _users   = [];
  bool _loading = true;
  int  _totalChats = 0;
  int  _totalUsers = 0;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final usersSnap = await _db.collection('users').get();
    final chatsSnap = await _db.collection('chats').get();
    setState(() {
      _users = usersSnap.docs.map((d) => {...d.data(), 'uid': d.id}).toList();
      _totalUsers = usersSnap.docs.length;
      _totalChats = chatsSnap.docs.length;
      _loading = false;
    });
  }

  Future<void> _banUser(String uid, String name) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        backgroundColor: const Color(0xFF13131A),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('Заблокировать $name?',
            style: const TextStyle(fontFamily: 'Syne',
                fontWeight: FontWeight.w800, color: Colors.white)),
        content: const Text('Пользователь не сможет войти в приложение.',
            style: TextStyle(fontFamily: 'DM Sans', color: Color(0xFF8B8B9E))),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogCtx, false),
              child: const Text('Отмена', style: TextStyle(color: Color(0xFF8B8B9E)))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFFF5E7D)),
            onPressed: () => Navigator.pop(dialogCtx, true),
            child: const Text('Заблокировать',
                style: TextStyle(fontFamily: 'DM Sans', fontWeight: FontWeight.w600,
                    color: Colors.white)),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      await _db.collection('users').doc(uid).update({'banned': true});
      // Обновляем локальный список сразу
      setState(() {
        final idx = _users.indexWhere((u) => u['uid'] == uid);
        if (idx >= 0) _users[idx] = {..._users[idx], 'banned': true};
      });
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$name заблокирован'),
            backgroundColor: const Color(0xFFFF5E7D),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ошибка: $e'),
            backgroundColor: const Color(0xFFFF5E7D),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))));
    }
  }

  Future<void> _unbanUser(String uid, String name) async {
    try {
      await _db.collection('users').doc(uid).update({'banned': false});
      setState(() {
        final idx = _users.indexWhere((u) => u['uid'] == uid);
        if (idx >= 0) _users[idx] = {..._users[idx], 'banned': false};
      });
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$name разблокирован'),
            backgroundColor: const Color(0xFF34D399),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ошибка: $e'),
            backgroundColor: const Color(0xFFFF5E7D),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))));
    }
  }

  Future<void> _broadcastMessage() async {
    final ctrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF13131A),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Рассылка всем',
            style: TextStyle(fontFamily: 'Syne',
                fontWeight: FontWeight.w800, color: Colors.white)),
        content: TextField(
          controller: ctrl, autofocus: true, maxLines: 3,
          style: const TextStyle(fontFamily: 'DM Sans', color: Colors.white),
          decoration: const InputDecoration(hintText: 'Текст уведомления...',
              hintStyle: TextStyle(color: Color(0xFF8B8B9E)))),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false),
              child: const Text('Отмена', style: TextStyle(color: Color(0xFF8B8B9E)))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF7C6FFF)),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Отправить',
                style: TextStyle(fontFamily: 'DM Sans',
                    fontWeight: FontWeight.w600, color: Colors.white)),
          ),
        ],
      ),
    );
    if (ok != true || ctrl.text.trim().isEmpty) return;
    await _db.collection('broadcasts').add({
      'text'     : ctrl.text.trim(),
      'createdAt': FieldValue.serverTimestamp(),
      'by'       : _auth.currentUser?.uid ?? '',
    });
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: const Text('Рассылка отправлена'),
          backgroundColor: const Color(0xFF7C6FFF),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))));
  }

  @override
  Widget build(BuildContext context) {
    final isOwner = widget.role == 'owner';
    const bg      = Color(0xFF0A0A0F);
    const surface = Color(0xFF13131A);
    const accent  = Color(0xFF7C6FFF);

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        backgroundColor: surface,
        title: Row(children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              gradient: const LinearGradient(
                colors: [Color(0xFFFF5E7D), Color(0xFFFF9A3C)],
                begin: Alignment.topLeft, end: Alignment.bottomRight),
            ),
            child: Text(isOwner ? '👑 OWNER' : '🛡 ADMIN',
                style: const TextStyle(fontFamily: 'Syne', fontSize: 11,
                    fontWeight: FontWeight.w800, color: Colors.white)),
          ),
          const SizedBox(width: 10),
          const Text('Панель', style: TextStyle(
              fontFamily: 'Syne', fontWeight: FontWeight.w800)),
        ]),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: accent))
          : ListView(padding: const EdgeInsets.all(16), children: [
              // Статистика
              Row(children: [
                _statCard('👥', 'Пользователей', _totalUsers.toString()),
                const SizedBox(width: 12),
                _statCard('💬', 'Чатов', _totalChats.toString()),
              ]),
              const SizedBox(height: 16),

              // Рассылка
              GestureDetector(
                onTap: _broadcastMessage,
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: surface,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.white.withOpacity(0.06)),
                  ),
                  child: Row(children: [
                    Container(width: 40, height: 40,
                      decoration: BoxDecoration(shape: BoxShape.circle,
                          color: accent.withOpacity(0.1)),
                      child: const Icon(Icons.campaign_rounded, color: accent, size: 20)),
                    const SizedBox(width: 12),
                    const Expanded(child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('Рассылка', style: TextStyle(fontFamily: 'DM Sans',
                          fontSize: 15, fontWeight: FontWeight.w500, color: Colors.white)),
                      Text('Отправить всем пользователям',
                          style: TextStyle(fontFamily: 'DM Sans',
                              fontSize: 12, color: Color(0xFF8B8B9E))),
                    ])),
                    const Icon(Icons.chevron_right_rounded, color: Color(0xFF8B8B9E)),
                  ]),
                ),
              ),
              const SizedBox(height: 20),

              // Пользователи
              const Padding(
                padding: EdgeInsets.only(left: 4, bottom: 10),
                child: Text('ПОЛЬЗОВАТЕЛИ', style: TextStyle(fontFamily: 'DM Sans',
                    fontSize: 11, fontWeight: FontWeight.w500,
                    color: Color(0xFF8B8B9E), letterSpacing: 0.8)),
              ),
              ...(_users.map((u) {
                final uid    = u['uid'] as String;
                final name   = u['username'] as String? ?? 'Unknown';
                final email  = u['email']    as String? ?? '';
                final avatar = u['avatarUrl'] as String?;
                final banned = u['banned']   == true;
                final isSelf = uid == _auth.currentUser?.uid;

                return Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: surface,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: banned
                        ? const Color(0xFFFF5E7D).withOpacity(0.3)
                        : Colors.white.withOpacity(0.06)),
                  ),
                  child: Row(children: [
                    Container(
                      width: 40, height: 40,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: const LinearGradient(
                          colors: [Color(0xFF7C6FFF), Color(0xFF38BDF8)],
                          begin: Alignment.topLeft, end: Alignment.bottomRight),
                      ),
                      child: ClipOval(child: avatar != null && avatar.isNotEmpty
                          ? Image.network(avatar, fit: BoxFit.cover)
                          : Center(child: Text(
                              name.isNotEmpty ? name[0].toUpperCase() : '?',
                              style: const TextStyle(fontFamily: 'Syne',
                                  fontSize: 16, fontWeight: FontWeight.w800,
                                  color: Colors.white)))),
                    ),
                    const SizedBox(width: 12),
                    Expanded(child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        Text(name, style: const TextStyle(fontFamily: 'DM Sans',
                            fontSize: 14, fontWeight: FontWeight.w500,
                            color: Colors.white)),
                        if (isSelf) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(6),
                              color: accent.withOpacity(0.2)),
                            child: const Text('вы', style: TextStyle(
                                fontFamily: 'DM Sans', fontSize: 10,
                                color: accent, fontWeight: FontWeight.w600)),
                          ),
                        ],
                        if (banned) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(6),
                              color: const Color(0xFFFF5E7D).withOpacity(0.2)),
                            child: const Text('бан', style: TextStyle(
                                fontFamily: 'DM Sans', fontSize: 10,
                                color: Color(0xFFFF5E7D),
                                fontWeight: FontWeight.w600)),
                          ),
                        ],
                      ]),
                      Text(email, style: const TextStyle(fontFamily: 'DM Sans',
                          fontSize: 12, color: Color(0xFF8B8B9E)),
                          overflow: TextOverflow.ellipsis),
                    ])),
                    if (!isSelf)
                      GestureDetector(
                        onTap: () => banned
                            ? _unbanUser(uid, name)
                            : _banUser(uid, name),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(10),
                            color: banned
                                ? const Color(0xFF34D399).withOpacity(0.15)
                                : const Color(0xFFFF5E7D).withOpacity(0.15),
                          ),
                          child: Text(banned ? 'Разбан' : 'Бан',
                            style: TextStyle(fontFamily: 'DM Sans', fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: banned
                                    ? const Color(0xFF34D399)
                                    : const Color(0xFFFF5E7D))),
                        ),
                      ),
                  ]),
                );
              })),
            ]),
    );
  }

  Widget _statCard(String emoji, String label, String value) => Expanded(
    child: Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF13131A),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.06)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(emoji, style: const TextStyle(fontSize: 24)),
        const SizedBox(height: 8),
        Text(value, style: const TextStyle(fontFamily: 'Syne', fontSize: 22,
            fontWeight: FontWeight.w800, color: Colors.white)),
        Text(label, style: const TextStyle(fontFamily: 'DM Sans',
            fontSize: 12, color: Color(0xFF8B8B9E))),
      ]),
    ),
  );
}
