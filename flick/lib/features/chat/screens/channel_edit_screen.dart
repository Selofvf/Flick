import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:image_picker/image_picker.dart';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

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

class ChannelEditScreen extends StatefulWidget {
  final String chatId;
  const ChannelEditScreen({super.key, required this.chatId});

  @override
  State<ChannelEditScreen> createState() => _ChannelEditScreenState();
}

class _ChannelEditScreenState extends State<ChannelEditScreen> {
  final _db   = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;

  static const _cloudName = 'dpy1me6tk';
  static const _apiKey    = '321197243977146';
  static const _apiSecret = 'ntdiE6OpKzaUzVwRhCiwwLrS1QM';

  late TextEditingController _nameCtrl;
  late TextEditingController _descCtrl;

  String  _name        = '';
  String  _description = '';
  String  _avatarUrl   = '';
  int     _bannerIdx   = 0;
  int     _memberCount = 0;
  bool    _loading     = true;
  bool    _uploading   = false;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController();
    _descCtrl = TextEditingController();
    _loadChannel();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadChannel() async {
    final doc  = await _db.collection('chats').doc(widget.chatId).get();
    final data = doc.data() ?? {};
    setState(() {
      _name        = data['name']        ?? '';
      _description = data['description'] ?? '';
      _avatarUrl   = data['avatarUrl']   ?? '';
      _bannerIdx   = (data['bannerIdx']  ?? 0) as int;
      _memberCount = (List.from(data['members'] ?? [])).length;
      _nameCtrl.text = _name;
      _descCtrl.text = _description;
      _loading = false;
    });
  }

  // ── Cloudinary ────────────────────────────────────────────────────────────
  String _sign(String params) {
    final bytes = utf8.encode('$params$_apiSecret');
    return sha1.convert(bytes).toString();
  }

  Future<String?> _uploadImage(File file) async {
    final ts        = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final folder    = 'flick/channels';
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

  Future<void> _changeAvatar() async {
    // Просто открываем галерею — image_picker сам справляется с разрешениями


    final picker = ImagePicker();
    final xfile  = await picker.pickImage(source: ImageSource.gallery, imageQuality: 80);
    if (xfile == null) return;
    setState(() => _uploading = true);
    try {
      final url = await _uploadImage(File(xfile.path));
      if (url != null) {
        await _db.collection('chats').doc(widget.chatId).update({'avatarUrl': url});
        setState(() => _avatarUrl = url);
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Аватарка обновлена ✓')));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ошибка загрузки: $e')));
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _saveBanner(int idx) async {
    await _db.collection('chats').doc(widget.chatId).update({'bannerIdx': idx});
    setState(() => _bannerIdx = idx);
  }

  Future<void> _saveInfo() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) return;
    await _db.collection('chats').doc(widget.chatId).update({
      'name'       : name,
      'description': _descCtrl.text.trim(),
    });
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Канал обновлён ✓')));
      Navigator.pop(context, true); // возвращаем true = нужно перезагрузить
    }
  }

  @override
  Widget build(BuildContext context) {
    final dark    = Theme.of(context).brightness == Brightness.dark;
    final bg      = dark ? const Color(0xFF0A0A0F) : const Color(0xFFF5F5FA);
    final surface = dark ? const Color(0xFF13131A) : Colors.white;
    final muted   = dark ? const Color(0xFF8B8B9E) : const Color(0xFF9CA3AF);
    final bannerColors = _bannerPresets[_bannerIdx];

    if (_loading) {
      return Scaffold(
        backgroundColor: bg,
        body: const Center(child: CircularProgressIndicator(color: Color(0xFF7C6FFF))),
      );
    }

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        backgroundColor: surface,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('Редактировать канал',
            style: TextStyle(fontFamily: 'Syne', fontWeight: FontWeight.w800, fontSize: 16)),
        actions: [
          TextButton(
            onPressed: _saveInfo,
            child: const Text('Сохранить',
                style: TextStyle(fontFamily: 'DM Sans',
                    color: Color(0xFF7C6FFF), fontWeight: FontWeight.w600)),
          ),
        ],
      ),
      body: SingleChildScrollView(
        child: Column(children: [

          // ── Баннер ───────────────────────────────────────────────────────
          Container(
            height: 140,
            width: double.infinity,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: bannerColors,
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
          ),

          const SizedBox(height: 16),

          // ── Аватарка + кнопка смены ───────────────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(children: [
              // Аватарка
              Container(
                width: 80, height: 80,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: bg, width: 3),
                  gradient: LinearGradient(
                    colors: bannerColors,
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                child: ClipOval(
                  child: _uploading
                      ? const Center(child: CircularProgressIndicator(
                          color: Colors.white, strokeWidth: 2))
                      : _avatarUrl.isNotEmpty
                          ? Image.network(_avatarUrl, fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => _defaultIcon())
                          : _defaultIcon(),
                ),
              ),
              const SizedBox(width: 16),
              // Кнопка смены аватара
              Expanded(
                child: Material(
                  color: surface,
                  borderRadius: BorderRadius.circular(14),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(14),
                    onTap: _changeAvatar,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
                      child: Row(children: [
                        const Icon(Icons.camera_alt_rounded,
                            color: Color(0xFF7C6FFF), size: 20),
                        const SizedBox(width: 10),
                        Text('Сменить аватарку',
                          style: TextStyle(fontFamily: 'DM Sans',
                            fontSize: 14, fontWeight: FontWeight.w500,
                            color: dark ? Colors.white : Colors.black87)),
                      ]),
                    ),
                  ),
                ),
              ),
            ]),
          ),

          const SizedBox(height: 24),

          // ── Выбор градиента баннера ──────────────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Цвет баннера',
                  style: TextStyle(fontFamily: 'DM Sans', fontSize: 12,
                      fontWeight: FontWeight.w600, color: muted, letterSpacing: 0.8)),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.start,
                children: [
                  for (int i = 0; i < _bannerPresets.length; i++)
                    GestureDetector(
                      onTap: () => _saveBanner(i),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        margin: const EdgeInsets.only(right: 10),
                        width:  i == _bannerIdx ? 36 : 28,
                        height: i == _bannerIdx ? 36 : 28,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: LinearGradient(
                            colors: _bannerPresets[i],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          border: i == _bannerIdx
                              ? Border.all(color: Colors.white, width: 2.5)
                              : null,
                          boxShadow: i == _bannerIdx
                              ? [BoxShadow(
                                  color: _bannerPresets[i][0].withOpacity(0.5),
                                  blurRadius: 10)]
                              : null,
                        ),
                      ),
                    ),
                ],
              ),
            ]),
          ),

          const SizedBox(height: 28),

          // ── Поля ────────────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('НАЗВАНИЕ',
                  style: TextStyle(fontFamily: 'DM Sans', fontSize: 11,
                      fontWeight: FontWeight.w600, color: muted, letterSpacing: 0.8)),
              const SizedBox(height: 8),
              Container(
                decoration: BoxDecoration(
                  color: surface,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: TextField(
                  controller: _nameCtrl,
                  style: TextStyle(fontFamily: 'DM Sans', fontSize: 15,
                      color: dark ? Colors.white : Colors.black87),
                  decoration: InputDecoration(
                    hintText: 'Название канала',
                    hintStyle: TextStyle(color: muted),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 14),
                    border: InputBorder.none,
                  ),
                ),
              ),

              const SizedBox(height: 20),

              Text('ОПИСАНИЕ',
                  style: TextStyle(fontFamily: 'DM Sans', fontSize: 11,
                      fontWeight: FontWeight.w600, color: muted, letterSpacing: 0.8)),
              const SizedBox(height: 8),
              Container(
                decoration: BoxDecoration(
                  color: surface,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: TextField(
                  controller: _descCtrl,
                  maxLines: 4,
                  style: TextStyle(fontFamily: 'DM Sans', fontSize: 15,
                      color: dark ? Colors.white : Colors.black87),
                  decoration: InputDecoration(
                    hintText: 'Расскажите о вашем канале...',
                    hintStyle: TextStyle(color: muted),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 14),
                    border: InputBorder.none,
                  ),
                ),
              ),

              const SizedBox(height: 24),

              // Статистика
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: surface,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(children: [
                  const Icon(Icons.people_rounded,
                      color: Color(0xFF7C6FFF), size: 22),
                  const SizedBox(width: 12),
                  Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('$_memberCount',
                        style: const TextStyle(fontFamily: 'Syne',
                            fontSize: 18, fontWeight: FontWeight.w800,
                            color: Color(0xFF7C6FFF))),
                    Text('подписчиков',
                        style: TextStyle(fontFamily: 'DM Sans',
                            fontSize: 12, color: muted)),
                  ]),
                ]),
              ),

              const SizedBox(height: 40),
            ]),
          ),
        ]),
      ),
    );
  }

  Widget _defaultIcon() => Center(
    child: Icon(Icons.campaign_rounded,
        color: Colors.white.withOpacity(0.9), size: 36),
  );
}
