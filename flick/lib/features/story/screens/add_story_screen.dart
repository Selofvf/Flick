import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:image_picker/image_picker.dart';
import 'package:crypto/crypto.dart';
import 'dart:io';
import 'dart:convert';
import 'package:http/http.dart' as http;

class AddStoryScreen extends StatefulWidget {
  const AddStoryScreen({super.key});
  @override State<AddStoryScreen> createState() => _AddStoryScreenState();
}

class _AddStoryScreenState extends State<AddStoryScreen> {
  final _auth = FirebaseAuth.instance;
  final _db   = FirebaseFirestore.instance;
  final _ctrl = TextEditingController();

  static const _cloudName = 'dpy1me6tk';
  static const _apiKey    = '321197243977146';
  static const _apiSecret = 'ntdiE6OpKzaUzVwRhCiwwLrS1QM';

  String _type      = 'text'; // 'text' | 'image'
  File?  _imageFile;
  bool   _uploading = false;

  // Градиентные фоны для текстовых историй
  final _bgs = [
    [const Color(0xFF1A0A3A), const Color(0xFF0A1830)],
    [const Color(0xFF7C6FFF), const Color(0xFF38BDF8)],
    [const Color(0xFF200A40), const Color(0xFF0D0B1F)],
    [const Color(0xFFFF5E7D), const Color(0xFF7C6FFF)],
    [const Color(0xFF0A3A1A), const Color(0xFF0A1830)],
    [const Color(0xFF3A1A0A), const Color(0xFF1A0A3A)],
  ];
  int _bgIdx = 0;

  String _sign(String params) {
    final bytes = utf8.encode('$params$_apiSecret');
    return sha1.convert(bytes).toString();
  }

  Future<String?> _uploadToCloudinary(File file) async {
    final ts        = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final signature = _sign('folder=flick/stories&timestamp=$ts');
    final uri = Uri.parse(
        'https://api.cloudinary.com/v1_1/$_cloudName/auto/upload');
    final req = http.MultipartRequest('POST', uri)
      ..fields['api_key']   = _apiKey
      ..fields['timestamp'] = ts.toString()
      ..fields['folder']    = 'flick/stories'
      ..fields['signature'] = signature
      ..files.add(await http.MultipartFile.fromPath('file', file.path));
    final res  = await req.send();
    final body = await res.stream.bytesToString();
    final json = jsonDecode(body);
    return json['secure_url'] as String?;
  }

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final xfile  = await picker.pickImage(
        source: ImageSource.gallery, imageQuality: 80);
    if (xfile == null) return;
    setState(() {
      _imageFile = File(xfile.path);
      _type = 'image';
    });
  }

  Future<void> _publish() async {
    if (_type == 'text' && _ctrl.text.trim().isEmpty) return;
    setState(() => _uploading = true);
    try {
      final uid = _auth.currentUser?.uid ?? '';
      final doc = await _db.collection('users').doc(uid).get();
      final username = doc.data()?['username'] ?? 'Я';
      final now = FieldValue.serverTimestamp();
      final expires = Timestamp.fromDate(
          DateTime.now().add(const Duration(hours: 24)));

      final data = <String, dynamic>{
        'uid':       uid,
        'username':  username,
        'type':      _type,
        'createdAt': now,
        'expiresAt': expires,
      };

      if (_type == 'image' && _imageFile != null) {
        final url = await _uploadToCloudinary(_imageFile!);
        if (url == null) throw Exception('Upload failed');
        data['imageUrl'] = url;
        data['text']     = _ctrl.text.trim();
      } else {
        data['text']     = _ctrl.text.trim();
        data['bgColor']  = '0x${_bgs[_bgIdx][0].value.toRadixString(16).padLeft(8, '0').toUpperCase()}';
        data['bgColor2'] = '0x${_bgs[_bgIdx][1].value.toRadixString(16).padLeft(8, '0').toUpperCase()}';
      }

      await _db.collection('stories').add(data);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка: $e')));
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bg = _type == 'text'
        ? _bgs[_bgIdx]
        : [const Color(0xFF0A0A0F), const Color(0xFF13131A)];

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: bg,
            begin: Alignment.topLeft,
            end: Alignment.bottomRight)),
        child: SafeArea(
          child: Column(children: [

            // Шапка
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(children: [
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close_rounded,
                      color: Colors.white, size: 26)),
                const Spacer(),
                const Text('Новый статус',
                  style: TextStyle(fontFamily: 'Syne', fontSize: 18,
                    fontWeight: FontWeight.w800, color: Colors.white)),
                const Spacer(),
                _uploading
                    ? const SizedBox(width: 46, height: 46,
                        child: Center(child: CircularProgressIndicator(
                            color: Colors.white, strokeWidth: 2)))
                    : GestureDetector(
                        onTap: _publish,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 18, vertical: 10),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(99),
                            color: Colors.white.withOpacity(0.2),
                            border: Border.all(
                                color: Colors.white.withOpacity(0.4))),
                          child: const Text('Опубл.',
                            style: TextStyle(fontFamily: 'Syne',
                                fontSize: 14, fontWeight: FontWeight.w700,
                                color: Colors.white)),
                        ),
                      ),
              ]),
            ),

            // Превью контента
            Expanded(
              child: _type == 'image' && _imageFile != null
                  ? Stack(children: [
                      Positioned.fill(
                        child: Image.file(_imageFile!, fit: BoxFit.cover)),
                      if (_ctrl.text.isNotEmpty)
                        Center(child: Container(
                          margin: const EdgeInsets.all(32),
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.black.withOpacity(0.4),
                            borderRadius: BorderRadius.circular(12)),
                          child: Text(_ctrl.text,
                            textAlign: TextAlign.center,
                            style: const TextStyle(fontFamily: 'Syne',
                                fontSize: 22, fontWeight: FontWeight.w700,
                                color: Colors.white)),
                        )),
                    ])
                  : Center(child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Text(
                        _ctrl.text.isEmpty
                            ? 'Напиши что-нибудь...'
                            : _ctrl.text,
                        textAlign: TextAlign.center,
                        style: TextStyle(fontFamily: 'Syne', fontSize: 26,
                          fontWeight: FontWeight.w700,
                          color: _ctrl.text.isEmpty
                              ? Colors.white.withOpacity(0.3)
                              : Colors.white),
                      ),
                    )),
            ),

            // Панель инструментов
            Container(
              color: Colors.black.withOpacity(0.3),
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              child: Column(children: [

                // Выбор фона (только для текста)
                if (_type == 'text')
                  SizedBox(
                    height: 40,
                    child: ListView.builder(
                      scrollDirection: Axis.horizontal,
                      itemCount: _bgs.length,
                      itemBuilder: (_, i) => GestureDetector(
                        onTap: () => setState(() => _bgIdx = i),
                        child: Container(
                          width: 36, height: 36,
                          margin: const EdgeInsets.only(right: 8),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: LinearGradient(
                              colors: _bgs[i],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight),
                            border: _bgIdx == i
                                ? Border.all(color: Colors.white, width: 2.5)
                                : null,
                          ),
                        ),
                      ),
                    ),
                  ),

                const SizedBox(height: 12),

                // Поле ввода текста
                Row(children: [
                  Expanded(
                    child: TextField(
                      controller: _ctrl,
                      onChanged: (_) => setState(() {}),
                      maxLines: 3,
                      minLines: 1,
                      style: const TextStyle(fontFamily: 'DM Sans',
                          fontSize: 15, color: Colors.white),
                      decoration: InputDecoration(
                        hintText: 'Добавь текст...',
                        hintStyle: TextStyle(
                            color: Colors.white.withOpacity(0.4)),
                        filled: true,
                        fillColor: Colors.white.withOpacity(0.1),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: BorderSide.none),
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 12),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  // Кнопка фото
                  GestureDetector(
                    onTap: _pickImage,
                    child: Container(
                      width: 46, height: 46,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.white.withOpacity(0.15),
                        border: Border.all(
                            color: Colors.white.withOpacity(0.3))),
                      child: Icon(
                        _type == 'image'
                            ? Icons.image_rounded
                            : Icons.add_photo_alternate_rounded,
                        color: Colors.white, size: 22),
                    ),
                  ),
                ]),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}
