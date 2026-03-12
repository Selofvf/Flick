import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:image_picker/image_picker.dart';
import 'package:emoji_picker_flutter/emoji_picker_flutter.dart';
import 'package:record/record.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:crypto/crypto.dart';
import 'package:intl/intl.dart';
import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:http/http.dart' as http;
import '../../../features/call/screens/call_screen.dart';
import '../../../core/wallpapers.dart';

class ChatScreen extends StatefulWidget {
  final String chatId;
  const ChatScreen({super.key, required this.chatId});
  @override State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _auth     = FirebaseAuth.instance;
  final _db       = FirebaseFirestore.instance;
  final _ctrl     = TextEditingController();
  final _scroll   = ScrollController();
  final _focus    = FocusNode();
  final _recorder = AudioRecorder();
  final _player   = AudioPlayer();

  static const _cloudName = 'dpy1me6tk';
  static const _apiKey    = '321197243977146';
  static const _apiSecret = 'ntdiE6OpKzaUzVwRhCiwwLrS1QM';

  static const _quickReactions = ['👍', '❤️', '😂', '😮', '😢', '🔥'];

  String  _chatName    = '';
  String  _chatType    = 'direct';
  String  _otherUserId = '';
  String  _ownerId     = '';
  String  _channelAvatar = '';
  int     _channelBanner = 0;
  String  _myUsername  = '';
  String  _wallpaperId = 'dark_1';
  bool    _showEmoji   = false;
  bool    _uploading   = false;
  bool    _isRecording = false;
  int     _recSeconds  = 0;
  Timer?  _recTimer;
  final List<double> _recWave = [];
  bool    _hasText     = false;
  bool    _isSubscribed = false;
  int     _subscriberCount = 0;
  String? _playingId;

  Map<String, dynamic>? _replyTo;
  String?               _replyToId;
  Map<String, dynamic>? _pinnedMessage;
  List<Map<String, dynamic>> _messages = [];

  // Редактирование
  String? _editingMsgId;
  String? _editingOrigText;

  // Поиск
  bool   _searchMode   = false;
  String _searchQuery  = '';
  int    _searchIndex  = 0;
  final  _searchCtrl   = TextEditingController();
  List<int> _searchHits = [];

  @override
  void initState() {
    super.initState();
    _loadChatName();
    _loadMyUsername();
    _ctrl.addListener(() {
      setState(() => _hasText = _ctrl.text.trim().isNotEmpty);
    });
    _focus.addListener(() {
      if (_focus.hasFocus && _showEmoji) setState(() => _showEmoji = false);
    });
  }

  Future<void> _loadMyUsername() async {
    final uid = _auth.currentUser?.uid ?? '';
    final doc = await _db.collection('users').doc(uid).get();
    setState(() {
      _myUsername  = doc.data()?['username']    ?? 'Я';
      _wallpaperId = doc.data()?['wallpaperId'] ?? 'dark_1';
    });
  }

  Future<void> _loadChatName() async {
    final doc  = await _db.collection('chats').doc(widget.chatId).get();
    final data = doc.data();
    if (data == null) return;
    final uid     = _auth.currentUser?.uid ?? '';
    final type    = data['type'] as String? ?? 'direct';
    final ownerId = data['ownerId'] as String? ?? '';
    final members = List<String>.from(data['members'] ?? []);
    final otherId = members.firstWhere((m) => m != uid, orElse: () => '');

    String name;
    if (type == 'direct') {
      final names = Map<String, dynamic>.from(data['names'] ?? {});
      name = names.entries
          .firstWhere((e) => e.key != uid, orElse: () => const MapEntry('?', '?'))
          .value.toString();
    } else {
      name = data['name'] ?? 'Чат';
    }

    setState(() {
      _chatName        = name;
      _chatType        = type;
      _ownerId         = ownerId;
      _isSubscribed    = members.contains(uid);
      _subscriberCount = members.length;
      _otherUserId     = otherId;
      _pinnedMessage   = data['pinnedMessage'] as Map<String, dynamic>?;
      _channelAvatar   = data['avatarUrl']  ?? '';
      _channelBanner   = (data['bannerIdx'] ?? 0) as int;
    });
  }

  // ── Подписка на канал ────────────────────────────────────────────────────
  Future<void> _toggleSubscribe() async {
    final uid = _auth.currentUser?.uid ?? '';
    if (_isSubscribed) {
      await _db.collection('chats').doc(widget.chatId).update({
        'members': FieldValue.arrayRemove([uid]),
      });
      setState(() { _isSubscribed = false; _subscriberCount--; });
    } else {
      await _db.collection('chats').doc(widget.chatId).update({
        'members': FieldValue.arrayUnion([uid]),
      });
      setState(() { _isSubscribed = true; _subscriberCount++; });
    }
  }

  // ── Cloudinary ───────────────────────────────────────────────────────────
  String _sign(String params) {
    final bytes = utf8.encode('$params$_apiSecret');
    return sha1.convert(bytes).toString();
  }

  Future<String?> _uploadToCloudinary(File file, String folder) async {
    final ts        = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final signature = _sign('folder=$folder&timestamp=$ts');
    final uri = Uri.parse('https://api.cloudinary.com/v1_1/$_cloudName/auto/upload');
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

  // ── Отправка ─────────────────────────────────────────────────────────────
  Future<void> _send({
    String? text,
    String? imageUrl,
    String? audioUrl,
    int?    audioDuration,
    String? fileUrl,
    String? fileName,
    int?    fileSize,
    String? fileExt,
  }) async {
    final t = text ?? _ctrl.text.trim();
    if (t.isEmpty && imageUrl == null && audioUrl == null && fileUrl == null) return;
    if (text == null && audioUrl == null && fileUrl == null) _ctrl.clear();

    final uid = _auth.currentUser?.uid ?? '';
    final now = FieldValue.serverTimestamp();

    final msg = <String, dynamic>{
      'senderId':   uid,
      'senderName': _myUsername,
      'createdAt':  now,
      'reactions':  <String, dynamic>{},
      'type': audioUrl != null ? 'audio' : (imageUrl != null ? 'image' : (fileUrl != null ? 'file' : 'text')),
    };

    if (_replyTo != null) {
      msg['replyTo'] = {
        'id':         _replyToId ?? '',
        'text':       _replyTo!['text'] ?? '',
        'senderName': _replyTo!['senderName'] ?? '',
        'type':       _replyTo!['type'] ?? 'text',
      };
    }

    if (audioUrl != null) {
      msg['audioUrl']      = audioUrl;
      msg['audioDuration'] = audioDuration ?? 0;
      msg['text']          = '🎤 Голосовое';
    } else if (imageUrl != null) {
      msg['imageUrl'] = imageUrl;
      msg['text']     = '📷 Фото';
    } else if (fileUrl != null) {
      msg['fileUrl']  = fileUrl;
      msg['fileName'] = fileName ?? 'Файл';
      msg['fileSize'] = fileSize ?? 0;
      msg['fileExt']  = fileExt ?? '';
      msg['text']     = '📎 ${fileName ?? 'Файл'}';
    } else {
      msg['text'] = t;
    }

    setState(() { _replyTo = null; _replyToId = null; });

    await _db.collection('chats').doc(widget.chatId).collection('messages').add(msg);
    await _db.collection('chats').doc(widget.chatId).update({
      'lastMessage': msg['text'],
      'updatedAt':   now,
    });

    Future.delayed(const Duration(milliseconds: 100), () {
      if (_scroll.hasClients) {
        _scroll.animateTo(_scroll.position.maxScrollExtent,
            duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
      }
    });
  }

  // ── Реакции ──────────────────────────────────────────────────────────────
  Future<void> _toggleReaction(String msgId, String emoji) async {
    final uid  = _auth.currentUser?.uid ?? '';
    final ref  = _db.collection('chats').doc(widget.chatId).collection('messages').doc(msgId);
    final doc  = await ref.get();
    final data = doc.data();
    if (data == null) return;
    final reactions = Map<String, dynamic>.from(data['reactions'] ?? {});
    final users     = List<String>.from(reactions[emoji] ?? []);
    if (users.contains(uid)) { users.remove(uid); } else { users.add(uid); }
    if (users.isEmpty) { reactions.remove(emoji); } else { reactions[emoji] = users; }
    await ref.update({'reactions': reactions});
  }

  void _showReactionPicker(String msgId, bool isMe) {
    HapticFeedback.mediumImpact();
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => _MessageMenu(
        msgId:    msgId,
        isMe:     isMe,
        isPinned: _pinnedMessage?['msgId'] == msgId,
        reactions: _quickReactions,
        onReact:   (emoji) { Navigator.pop(context); _toggleReaction(msgId, emoji); },
        onReply:   (data)  { Navigator.pop(context); _setReply(data, msgId); },
        onPin:     ()      { Navigator.pop(context); _pinMessage(msgId); },
        onUnpin:   ()      { Navigator.pop(context); _unpinMessage(); },
        onForward: ()      { Navigator.pop(context); _showForwardSheet(msgId); },
        onDelete:  (forAll) { Navigator.pop(context); _deleteMessage(msgId, forAll); },
        onEdit:    (text)   { Navigator.pop(context); _startEdit(msgId, text); },
        msgData:  _messages.firstWhere((m) => m['id'] == msgId, orElse: () => {}),
      ),
    );
  }

  Future<void> _showForwardSheet(String msgId) async {
    final msg = _messages.firstWhere((m) => m['id'] == msgId, orElse: () => {});
    if (msg.isEmpty) return;

    final uid = _auth.currentUser?.uid ?? '';

    // Загружаем список чатов
    final snap = await _db.collection('chats')
        .where('members', arrayContains: uid)
        .orderBy('updatedAt', descending: true)
        .get();

    final chats = snap.docs
        .map((d) => {...d.data(), 'id': d.id})
        .where((c) => c['type'] != 'notes' || c['id'] != widget.chatId)
        .toList();

    if (!mounted) return;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) {
        final dark    = Theme.of(context).brightness == Brightness.dark;
        final surface = dark ? const Color(0xFF13131A) : Colors.white;
        final bg      = dark ? const Color(0xFF0A0A0F) : const Color(0xFFF0F2F8);

        return DraggableScrollableSheet(
          initialChildSize: 0.6,
          maxChildSize: 0.9,
          minChildSize: 0.4,
          builder: (_, scrollCtrl) => Container(
            decoration: BoxDecoration(
              color: bg,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
              border: Border.all(color: Colors.white.withOpacity(0.06)),
            ),
            child: Column(children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 16, 24, 12),
                child: Column(children: [
                  Container(width: 40, height: 4,
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(99))),
                  const SizedBox(height: 16),
                  const Text('Переслать в...',
                    style: TextStyle(fontFamily: 'Syne', fontSize: 18,
                        fontWeight: FontWeight.w800, color: Colors.white)),
                ]),
              ),
              Expanded(
                child: ListView.builder(
                  controller: scrollCtrl,
                  itemCount: chats.length,
                  itemBuilder: (_, i) {
                    final chat    = chats[i];
                    final type    = chat['type'] as String? ?? 'direct';
                    final name    = type == 'direct'
                        ? (() {
                            final names = Map<String, String>.from(chat['names'] ?? {});
                            names.remove(uid);
                            return names.values.firstOrNull ?? 'Чат';
                          })()
                        : (chat['name'] as String? ?? 'Группа');
                    final avatarUrl = chat['avatarUrl'] as String? ?? '';

                    return InkWell(
                      onTap: () async {
                        Navigator.pop(context);
                        await _forwardMessage(msg, chat['id'] as String);
                        if (mounted) ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('Переслано в «$name»',
                              style: const TextStyle(fontFamily: 'DM Sans')),
                            backgroundColor: const Color(0xFF7C6FFF),
                            behavior: SnackBarBehavior.floating,
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12)),
                          ),
                        );
                      },
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                        child: Row(children: [
                          Container(
                            width: 46, height: 46,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: const LinearGradient(
                                colors: [Color(0xFF7C6FFF), Color(0xFF38BDF8)],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight),
                            ),
                            child: ClipOval(
                              child: avatarUrl.isNotEmpty
                                  ? Image.network(avatarUrl, fit: BoxFit.cover,
                                      errorBuilder: (_, __, ___) =>
                                          Icon(_chatIcon(type), color: Colors.white, size: 22))
                                  : Icon(_chatIcon(type), color: Colors.white, size: 22),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(child: Text(name,
                            style: TextStyle(fontFamily: 'DM Sans', fontSize: 15,
                                fontWeight: FontWeight.w500,
                                color: dark ? Colors.white : const Color(0xFF0F0F1A)),
                            overflow: TextOverflow.ellipsis)),
                          const Icon(Icons.chevron_right_rounded,
                              color: Color(0xFF8B8B9E), size: 18),
                        ]),
                      ),
                    );
                  },
                ),
              ),
            ]),
          ),
        );
      },
    );
  }

  IconData _chatIcon(String type) {
    if (type == 'group')   return Icons.group_rounded;
    if (type == 'channel') return Icons.campaign_rounded;
    if (type == 'notes')   return Icons.bookmark_rounded;
    return Icons.person_rounded;
  }

  Future<void> _forwardMessage(Map<String, dynamic> msg, String toChatId) async {
    final uid  = _auth.currentUser?.uid ?? '';
    final meDoc = await _db.collection('users').doc(uid).get();
    final myName = meDoc.data()?['displayName'] ?? meDoc.data()?['username'] ?? 'Я';

    final type = msg['type'] as String? ?? 'text';
    final newMsg = <String, dynamic>{
      'senderId'     : uid,
      'senderName'   : myName,
      'createdAt'    : FieldValue.serverTimestamp(),
      'reactions'    : {},
      'type'         : type,
      'forwardedFrom': msg['senderName'] ?? '',
      'text'         : msg['text'] ?? '',
    };

    if (type == 'image')  newMsg['imageUrl']  = msg['imageUrl'];
    if (type == 'audio') {
      newMsg['audioUrl']      = msg['audioUrl'];
      newMsg['audioDuration'] = msg['audioDuration'] ?? 0;
    }

    await _db.collection('chats').doc(toChatId)
        .collection('messages').add(newMsg);
    await _db.collection('chats').doc(toChatId).update({
      'lastMessage': type == 'image' ? '📷 Фото' : (msg['text'] ?? ''),
      'updatedAt'  : FieldValue.serverTimestamp(),
    });
  }

  void _openSearch() {
    setState(() { _searchMode = true; _searchQuery = ''; _searchHits = []; _searchIndex = 0; });
    Future.delayed(const Duration(milliseconds: 100), () => _searchCtrl.clear());
  }

  void _closeSearch() {
    setState(() { _searchMode = false; _searchQuery = ''; _searchHits = []; _searchIndex = 0; });
    _searchCtrl.clear();
  }

  void _onSearchChanged(String q, List<Map<String, dynamic>> messages) {
    final query = q.trim().toLowerCase();
    if (query.isEmpty) {
      setState(() { _searchQuery = ''; _searchHits = []; _searchIndex = 0; });
      return;
    }
    final hits = <int>[];
    for (int i = 0; i < messages.length; i++) {
      final text = (messages[i]['text'] as String? ?? '').toLowerCase();
      if (text.contains(query)) hits.add(i);
    }
    setState(() { _searchQuery = query; _searchHits = hits; _searchIndex = hits.isEmpty ? 0 : hits.length - 1; });
    if (hits.isNotEmpty) _scrollToSearchHit(hits.last);
  }

  void _scrollToSearchHit(int msgIndex) {
    if (!_scroll.hasClients) return;
    // Приблизительный скролл по индексу
    final maxExtent = _scroll.position.maxScrollExtent;
    final total     = _messages.length;
    if (total == 0) return;
    final offset = (msgIndex / total) * maxExtent;
    _scroll.animateTo(offset.clamp(0, maxExtent),
        duration: const Duration(milliseconds: 350), curve: Curves.easeOut);
  }

  void _searchNext() {
    if (_searchHits.isEmpty) return;
    final next = (_searchIndex + 1) % _searchHits.length;
    setState(() => _searchIndex = next);
    _scrollToSearchHit(_searchHits[next]);
  }

  void _searchPrev() {
    if (_searchHits.isEmpty) return;
    final prev = (_searchIndex - 1 + _searchHits.length) % _searchHits.length;
    setState(() => _searchIndex = prev);
    _scrollToSearchHit(_searchHits[prev]);
  }

  void _startEdit(String msgId, String currentText) {
    setState(() {
      _editingMsgId    = msgId;
      _editingOrigText = currentText;
    });
    _ctrl.text = currentText;
    _ctrl.selection = TextSelection.fromPosition(
        TextPosition(offset: currentText.length));
    _focus.requestFocus();
  }

  void _cancelEdit() {
    setState(() { _editingMsgId = null; _editingOrigText = null; });
    _ctrl.clear();
  }

  Future<void> _saveEdit() async {
    final newText = _ctrl.text.trim();
    if (newText.isEmpty || _editingMsgId == null) return;
    if (newText == _editingOrigText) { _cancelEdit(); return; }

    await _db.collection('chats').doc(widget.chatId)
        .collection('messages').doc(_editingMsgId).update({
      'text'    : newText,
      'edited'  : true,
      'editedAt': FieldValue.serverTimestamp(),
    });

    _cancelEdit();
  }

  Future<void> _deleteMessage(String msgId, bool forAll) async {
    final uid = _auth.currentUser?.uid ?? '';
    final msgRef = _db.collection('chats').doc(widget.chatId)
        .collection('messages').doc(msgId);

    if (forAll) {
      // Удаляем у всех — заменяем текст на заглушку
      await msgRef.update({
        'text'     : '',
        'type'     : 'deleted',
        'imageUrl' : FieldValue.delete(),
        'audioUrl' : FieldValue.delete(),
        'deletedBy': uid,
        'deletedAt': FieldValue.serverTimestamp(),
      });
    } else {
      // Удаляем только у себя — добавляем uid в hiddenFor
      await msgRef.update({
        'hiddenFor': FieldValue.arrayUnion([uid]),
      });
    }
  }

  Future<void> _pinMessage(String msgId) async {
    final msg = _messages.firstWhere((m) => m['id'] == msgId, orElse: () => {});
    if (msg.isEmpty) return;
    final pinned = {
      'msgId'     : msgId,
      'text'      : msg['text'] ?? '',
      'senderName': msg['senderName'] ?? '',
      'type'      : msg['type'] ?? 'text',
    };
    await _db.collection('chats').doc(widget.chatId)
        .update({'pinnedMessage': pinned});
    setState(() => _pinnedMessage = pinned);
  }

  Future<void> _unpinMessage() async {
    await _db.collection('chats').doc(widget.chatId)
        .update({'pinnedMessage': FieldValue.delete()});
    setState(() => _pinnedMessage = null);
  }

  void _setReply(Map<String, dynamic> data, String msgId) {
    HapticFeedback.lightImpact();
    setState(() { _replyTo = data; _replyToId = msgId; });
    _focus.requestFocus();
  }

  void _cancelReply() => setState(() { _replyTo = null; _replyToId = null; });

  // ── Медиа ────────────────────────────────────────────────────────────────
  static const _channel = MethodChannel('flick/file_picker');

  Future<void> _pickFile() async {
    String? filePath;
    String? fileName;

    try {
      // Нативный file picker через MethodChannel (MainActivity.kt)
      final result = await _channel.invokeMethod<Map>('pickFile');
      filePath = result?['path'] as String?;
      fileName = result?['name'] as String?;
    } catch (_) {
      // Fallback — image_picker если MethodChannel недоступен
      final picker = ImagePicker();
      final xfile  = await picker.pickImage(source: ImageSource.gallery, imageQuality: 85);
      if (xfile == null) return;
      filePath = xfile.path;
      fileName = p.basename(xfile.path);
    }

    if (filePath == null) return;

    final fileSize = File(filePath).lengthSync();
    if (fileSize > 200 * 1024 * 1024) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Файл слишком большой. Максимум 200 МБ')));
      return;
    }

    setState(() => _uploading = true);
    try {
      final ext     = p.extension(filePath).toLowerCase();
      final isImage = ['.jpg', '.jpeg', '.png', '.gif', '.webp'].contains(ext);
      final folder  = isImage ? 'flick/images' : 'flick/files';
      final url     = await _uploadToCloudinary(File(filePath), folder);
      if (url != null) {
        if (isImage) {
          await _send(imageUrl: url);
        } else {
          await _send(
            fileUrl:  url,
            fileName: fileName ?? 'Файл',
            fileSize: fileSize,
            fileExt:  ext,
          );
        }
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка загрузки: $e')));
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _startRecording() async {
    final hasPermission = await _recorder.hasPermission();
    if (!hasPermission) return;
    final path = '${Directory.systemTemp.path}/voice_${DateTime.now().millisecondsSinceEpoch}.m4a';
    await _recorder.start(const RecordConfig(encoder: AudioEncoder.aacLc), path: path);
    _recSeconds = 0;
    _recWave.clear();
    _recTimer = Timer.periodic(const Duration(milliseconds: 120), (_) {
      if (!mounted) return;
      final amp = 0.15 + Random().nextDouble() * 0.85;
      setState(() {
        _recWave.add(amp);
        if (_recWave.length > 40) _recWave.removeAt(0);
        if (_recWave.length % 8 == 0) _recSeconds++;
      });
    });
    setState(() => _isRecording = true);
  }

  Future<void> _stopRecording() async {
    _recTimer?.cancel();
    _recTimer = null;
    final duration = _recSeconds;
    final path = await _recorder.stop();
    setState(() { _isRecording = false; _recWave.clear(); _recSeconds = 0; });
    if (path == null) return;
    setState(() => _uploading = true);
    try {
      final url = await _uploadToCloudinary(File(path), 'flick/voice');
      if (url != null) await _send(audioUrl: url, audioDuration: duration);
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Ошибка отправки голосового')));
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _playAudio(String url, String msgId) async {
    if (_playingId == msgId) {
      await _player.stop();
      setState(() => _playingId = null);
    } else {
      await _player.stop();
      await _player.play(UrlSource(url));
      setState(() => _playingId = msgId);
      _player.onPlayerComplete.listen((_) {
        if (mounted) setState(() => _playingId = null);
      });
    }
  }

  void _startCall() {
    Navigator.push(context, MaterialPageRoute(
      builder: (_) => CallScreen(chatId: widget.chatId, remoteName: _chatName, isCaller: true),
    ));
  }

  void _toggleEmoji() {
    if (_showEmoji) { _focus.requestFocus(); } else { _focus.unfocus(); }
    setState(() => _showEmoji = !_showEmoji);
  }

  @override
  void dispose() {
    _ctrl.dispose(); _scroll.dispose(); _focus.dispose(); _searchCtrl.dispose();
    _recorder.dispose(); _player.dispose(); _recTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dark    = Theme.of(context).brightness == Brightness.dark;
    final surface = dark ? const Color(0xFF13131A) : Colors.white;
    final uid     = _auth.currentUser?.uid ?? '';
    final wall    = wallpaperById(_wallpaperId);

    return Scaffold(
      appBar: AppBar(
        backgroundColor: surface,
        leading: IconButton(
          icon: Icon(_searchMode ? Icons.close_rounded : Icons.arrow_back_rounded),
          onPressed: _searchMode ? _closeSearch : () => Navigator.pop(context),
        ),
        title: _searchMode ? TextField(
          controller: _searchCtrl,
          autofocus: true,
          style: TextStyle(fontFamily: 'DM Sans', fontSize: 15,
              color: dark ? Colors.white : const Color(0xFF0F0F1A)),
          decoration: InputDecoration(
            hintText: 'Поиск по сообщениям...',
            hintStyle: const TextStyle(fontFamily: 'DM Sans', color: Color(0xFF8B8B9E)),
            border: InputBorder.none,
          ),
          onChanged: (q) => _onSearchChanged(q, _messages),
        ) : Row(children: [
          GestureDetector(
            onTap: _chatType == 'channel' && _ownerId == (_auth.currentUser?.uid ?? '')
                ? () async {
                    final updated = await context.push('/channel-edit/${widget.chatId}');
                    if (updated == true) _loadChatName();
                  }
                : _chatType == 'direct' && _otherUserId.isNotEmpty
                    ? () => context.push('/profile/$_otherUserId')
                    : null,
            child: Container(
              width: 36, height: 36,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  colors: _chatType == 'channel'
                      ? [
                          const [Color(0xFF7C6FFF), Color(0xFF38BDF8)],
                          const [Color(0xFFFF5E7D), Color(0xFFFF9A3C)],
                          const [Color(0xFF34D399), Color(0xFF38BDF8)],
                          const [Color(0xFFFBBF24), Color(0xFFFF5E7D)],
                          const [Color(0xFFA78BFA), Color(0xFFF472B6)],
                          const [Color(0xFF0EA5E9), Color(0xFF6366F1)],
                          const [Color(0xFF10B981), Color(0xFFFBBF24)],
                          const [Color(0xFFEF4444), Color(0xFF7C3AED)],
                        ][_channelBanner.clamp(0, 7)]
                      : const [Color(0xFF7C6FFF), Color(0xFF38BDF8)],
                  begin: Alignment.topLeft, end: Alignment.bottomRight),
              ),
              child: ClipOval(
                child: _chatType == 'channel' && _channelAvatar.isNotEmpty
                    ? Image.network(_channelAvatar, fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => const Icon(
                            Icons.campaign_rounded, color: Colors.white, size: 20))
                    : Center(child: _chatType == 'channel'
                        ? const Icon(Icons.campaign_rounded, color: Colors.white, size: 20)
                        : _chatType == 'notes'
                            ? const Icon(Icons.bookmark_rounded, color: Colors.white, size: 20)
                            : Text(
                                _chatName.isNotEmpty ? _chatName[0].toUpperCase() : '?',
                                style: const TextStyle(fontFamily: 'Syne', fontSize: 16,
                                    fontWeight: FontWeight.w800, color: Colors.white))),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_chatName,
                style: TextStyle(fontFamily: 'Syne', fontSize: 15, fontWeight: FontWeight.w800,
                    color: dark ? Colors.white : const Color(0xFF0F0F1A)),
                overflow: TextOverflow.ellipsis),
              if (_chatType == 'channel')
                Text('$_subscriberCount подписчиков',
                  style: const TextStyle(fontFamily: 'DM Sans',
                      fontSize: 11, color: Color(0xFF8B8B9E)))
              else if (_chatType == 'notes')
                const Text('Только для тебя',
                  style: TextStyle(fontFamily: 'DM Sans',
                      fontSize: 11, color: Color(0xFF8B8B9E))),
            ],
          )),
        ]),
        actions: _searchMode ? [
          // Навигация по результатам
          if (_searchHits.isNotEmpty) ...[
            Text('${_searchHits.isEmpty ? 0 : _searchIndex + 1}/${_searchHits.length}',
              style: const TextStyle(fontFamily: 'DM Sans', fontSize: 13,
                  color: Color(0xFF8B8B9E))),
            IconButton(
              icon: const Icon(Icons.keyboard_arrow_up_rounded),
              onPressed: _searchPrev,
              tooltip: 'Предыдущее',
            ),
            IconButton(
              icon: const Icon(Icons.keyboard_arrow_down_rounded),
              onPressed: _searchNext,
              tooltip: 'Следующее',
            ),
          ],
          const SizedBox(width: 4),
        ] : [
          IconButton(
            icon: const Icon(Icons.search_rounded),
            onPressed: _openSearch,
            tooltip: 'Поиск',
          ),
          if (_chatType == 'channel' && _ownerId == (_auth.currentUser?.uid ?? ''))
            IconButton(
              onPressed: () async {
                final updated = await context.push('/channel-edit/${widget.chatId}');
                if (updated == true) _loadChatName();
              },
              icon: const Icon(Icons.edit_rounded, size: 20),
              tooltip: 'Редактировать канал',
            ),
          if (_chatType == 'channel')
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: GestureDetector(
                onTap: _toggleSubscribe,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(20),
                    gradient: _isSubscribed ? null : const LinearGradient(
                      colors: [Color(0xFF7C6FFF), Color(0xFF38BDF8)],
                      begin: Alignment.topLeft, end: Alignment.bottomRight),
                    color: _isSubscribed ? const Color(0xFF2A2A3A) : null,
                    border: _isSubscribed ? Border.all(color: const Color(0xFF7C6FFF).withOpacity(0.4)) : null,
                  ),
                  child: Text(
                    _isSubscribed ? 'Отписаться' : 'Подписаться',
                    style: TextStyle(
                      fontFamily: 'DM Sans', fontSize: 12, fontWeight: FontWeight.w600,
                      color: _isSubscribed ? const Color(0xFF8B8B9E) : Colors.white),
                  ),
                ),
              ),
            )
          else
            IconButton(
              onPressed: _startCall,
              icon: Container(
                width: 36, height: 36,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: const LinearGradient(
                    colors: [Color(0xFF7C6FFF), Color(0xFF38BDF8)],
                    begin: Alignment.topLeft, end: Alignment.bottomRight),
                  boxShadow: [BoxShadow(color: const Color(0xFF7C6FFF).withOpacity(0.4), blurRadius: 12)],
                ),
                child: const Icon(Icons.videocam_rounded, color: Colors.white, size: 18),
              ),
            ),
          const SizedBox(width: 4),
        ],
      ),

      // ── Фон чата ───────────────────────────────────────────────────────
      body: Container(
        decoration: wall != null
            ? BoxDecoration(
                gradient: LinearGradient(
                  colors: [wall.color1, wall.color2, wall.color1],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter),
              )
            : BoxDecoration(
                color: dark ? const Color(0xFF0A0A0F) : const Color(0xFFF0F2F8)),
        child: Column(children: [
          // ── Плашка закреплённого сообщения ──────────────────────────
          if (_pinnedMessage != null) _pinnedBar(dark, surface),
          if (_searchMode && _searchQuery.isNotEmpty) _searchResultBar(dark, surface),

          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: _db.collection('chats').doc(widget.chatId)
                  .collection('messages')
                  .orderBy('createdAt', descending: false)
                  .snapshots(),
              builder: (ctx, snap) {
                if (!snap.hasData) return const Center(
                    child: CircularProgressIndicator(color: Color(0xFF7C6FFF)));
                final docs = snap.data!.docs;
                if (docs.isEmpty) return Center(
                    child: Text('Напиши первое сообщение!',
                      style: TextStyle(fontFamily: 'DM Sans', fontSize: 14,
                          color: wall != null
                              ? Colors.white.withOpacity(0.5)
                              : (dark ? const Color(0xFF8B8B9E) : const Color(0xFF6B7280)))));
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (_scroll.hasClients) _scroll.jumpTo(_scroll.position.maxScrollExtent);
                });
                _messages = docs.map((d) => {
                  ...(d.data() as Map<String, dynamic>),
                  'id': d.id,
                }).toList();
                final visibleDocs = docs.where((d) {
                  final hidden = List<String>.from(
                      (d.data() as Map<String, dynamic>)['hiddenFor'] ?? []);
                  return !hidden.contains(uid);
                }).toList();
                // Обновляем _messages для поиска
                _messages = visibleDocs.map((d) => {
                  ...(d.data() as Map<String, dynamic>), 'id': d.id,
                }).toList();

                return ListView.builder(
                  controller: _scroll,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  itemCount: visibleDocs.length,
                  itemBuilder: (_, i) {
                    final data  = {...visibleDocs[i].data() as Map<String, dynamic>, 'id': visibleDocs[i].id};
                    final isMe  = data['senderId'] == uid;
                    // Подсветка текущего найденного
                    final isCurrentHit = _searchMode && _searchHits.isNotEmpty &&
                        _searchHits[_searchIndex] == i;
                    final isAnyHit = _searchMode && _searchQuery.isNotEmpty &&
                        _searchHits.contains(i);
                    return AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      decoration: isCurrentHit
                          ? BoxDecoration(
                              color: const Color(0xFFFFBF24).withOpacity(0.1),
                              borderRadius: BorderRadius.circular(12))
                          : isAnyHit
                              ? BoxDecoration(
                                  color: const Color(0xFFFFBF24).withOpacity(0.04),
                                  borderRadius: BorderRadius.circular(12))
                              : null,
                      child: _bubbleWithSwipe(data, isMe, dark, visibleDocs[i].id, uid,
                          wall != null, searchQuery: _searchMode ? _searchQuery : ''),
                    );
                  },
                );
              },
            ),
          ),
          if (_uploading)
            LinearProgressIndicator(
                color: const Color(0xFF7C6FFF),
                backgroundColor: const Color(0xFF7C6FFF).withOpacity(0.2)),
          if (_editingMsgId != null) _editBar(dark, surface),
          if (_replyTo != null) _replyBar(dark, surface),
          // Для каналов — поле ввода только у владельца
          if (_chatType != 'channel' || _ownerId == (_auth.currentUser?.uid ?? ''))
            _inputBar(surface, dark)
          else
            _channelReadonlyBar(surface, dark),
          if (_showEmoji) SizedBox(
            height: 280,
            child: EmojiPicker(
              onEmojiSelected: (_, emoji) {
                _ctrl.text += emoji.emoji;
                _ctrl.selection = TextSelection.fromPosition(
                    TextPosition(offset: _ctrl.text.length));
              },
              config: Config(
                height: 280,
                emojiTextStyle: const TextStyle(fontSize: 24),
                categoryViewConfig: CategoryViewConfig(
                  backgroundColor: dark ? const Color(0xFF13131A) : Colors.white,
                  iconColor: const Color(0xFF8B8B9E),
                  iconColorSelected: const Color(0xFF7C6FFF),
                  indicatorColor: const Color(0xFF7C6FFF),
                ),
                bottomActionBarConfig: BottomActionBarConfig(
                  backgroundColor: dark ? const Color(0xFF13131A) : Colors.white,
                  buttonColor: const Color(0xFF7C6FFF),
                ),
                searchViewConfig: SearchViewConfig(
                  backgroundColor: dark ? const Color(0xFF13131A) : Colors.white,
                ),
                emojiViewConfig: EmojiViewConfig(
                  backgroundColor: dark ? const Color(0xFF0A0A0F) : const Color(0xFFF0F2F8),
                ),
              ),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _highlightText(String text, String query, TextStyle baseStyle) {
    if (query.isEmpty) return Text(text, style: baseStyle);
    final lower   = text.toLowerCase();
    final qLower  = query.toLowerCase();
    final spans   = <TextSpan>[];
    int   start   = 0;
    int   idx;
    while ((idx = lower.indexOf(qLower, start)) != -1) {
      if (idx > start) {
        spans.add(TextSpan(text: text.substring(start, idx), style: baseStyle));
      }
      spans.add(TextSpan(
        text: text.substring(idx, idx + qLower.length),
        style: baseStyle.copyWith(
          backgroundColor: const Color(0xFFFFBF24).withOpacity(0.4),
          color: Colors.white,
          fontWeight: FontWeight.w700,
        ),
      ));
      start = idx + qLower.length;
    }
    if (start < text.length) {
      spans.add(TextSpan(text: text.substring(start), style: baseStyle));
    }
    return RichText(text: TextSpan(children: spans));
  }

  Widget _searchResultBar(bool dark, Color surface) {
    final count = _searchHits.length;
    final cur   = count == 0 ? 0 : _searchIndex + 1;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      decoration: BoxDecoration(
        color: surface,
        border: Border(bottom: BorderSide(color: Colors.white.withOpacity(0.06))),
      ),
      child: Row(children: [
        const Icon(Icons.search_rounded, size: 16, color: Color(0xFF8B8B9E)),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            count == 0 ? 'Ничего не найдено' : '$cur из $count совпадений',
            style: TextStyle(fontFamily: 'DM Sans', fontSize: 13,
                color: count == 0
                    ? const Color(0xFF8B8B9E)
                    : (dark ? Colors.white70 : const Color(0xFF4B4B6B))),
          ),
        ),
        if (count > 1) ...[
          GestureDetector(
            onTap: _searchPrev,
            child: Container(
              width: 32, height: 32,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFF7C6FFF).withOpacity(0.1)),
              child: const Icon(Icons.keyboard_arrow_up_rounded,
                  color: Color(0xFF7C6FFF), size: 20)),
          ),
          const SizedBox(width: 6),
          GestureDetector(
            onTap: _searchNext,
            child: Container(
              width: 32, height: 32,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFF7C6FFF).withOpacity(0.1)),
              child: const Icon(Icons.keyboard_arrow_down_rounded,
                  color: Color(0xFF7C6FFF), size: 20)),
          ),
        ],
      ]),
    );
  }

  Widget _pinnedBar(bool dark, Color surface) {
    final text   = _pinnedMessage!['text'] as String? ?? '';
    final sender = _pinnedMessage!['senderName'] as String? ?? '';
    final type   = _pinnedMessage!['type'] as String? ?? 'text';
    final preview = type == 'image' ? '📷 Фото'
        : type == 'audio' ? '🎤 Голосовое' : text;

    return GestureDetector(
      onTap: () {
        // Скролл к закреплённому сообщению
        final msgId = _pinnedMessage!['msgId'] as String?;
        if (msgId == null) return;
        final idx = _messages.indexWhere((m) => m['id'] == msgId);
        if (idx >= 0 && _scroll.hasClients) {
          _scroll.animateTo(
            idx * 72.0,
            duration: const Duration(milliseconds: 400),
            curve: Curves.easeOut,
          );
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: surface,
          border: Border(bottom: BorderSide(color: Colors.white.withOpacity(0.06))),
        ),
        child: Row(children: [
          Container(width: 3, height: 36,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(2),
              gradient: const LinearGradient(
                colors: [Color(0xFF7C6FFF), Color(0xFF38BDF8)],
                begin: Alignment.topCenter, end: Alignment.bottomCenter),
            )),
          const SizedBox(width: 10),
          Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('📌 Закреплённое',
                style: TextStyle(fontFamily: 'DM Sans', fontSize: 11,
                    fontWeight: FontWeight.w600, color: Color(0xFF7C6FFF))),
              const SizedBox(height: 2),
              Text(preview,
                style: TextStyle(fontFamily: 'DM Sans', fontSize: 13,
                    color: dark ? Colors.white70 : const Color(0xFF4B4B6B)),
                overflow: TextOverflow.ellipsis, maxLines: 1),
            ],
          )),
          GestureDetector(
            onTap: _unpinMessage,
            child: const Icon(Icons.close_rounded, color: Color(0xFF8B8B9E), size: 18),
          ),
        ]),
      ),
    );
  }

  Widget _editBar(bool dark, Color surface) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: surface,
        border: Border(top: BorderSide(color: Colors.white.withOpacity(0.06))),
      ),
      child: Row(children: [
        Container(width: 3, height: 36,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(2),
            gradient: const LinearGradient(
              colors: [Color(0xFFFFBF24), Color(0xFFFF9A3C)],
              begin: Alignment.topCenter, end: Alignment.bottomCenter),
          )),
        const SizedBox(width: 10),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('✏️ Редактирование',
            style: TextStyle(fontFamily: 'DM Sans', fontSize: 11,
                fontWeight: FontWeight.w600, color: Color(0xFFFFBF24))),
          const SizedBox(height: 2),
          Text(_editingOrigText ?? '',
            style: TextStyle(fontFamily: 'DM Sans', fontSize: 13,
                color: dark ? Colors.white60 : const Color(0xFF4B4B6B)),
            overflow: TextOverflow.ellipsis, maxLines: 1),
        ])),
        GestureDetector(
          onTap: _cancelEdit,
          child: const Icon(Icons.close_rounded, color: Color(0xFF8B8B9E), size: 18)),
      ]),
    );
  }

  Widget _replyBar(bool dark, Color surface) {
    final replyText   = _replyTo?['text'] ?? '';
    final replyType   = _replyTo?['type'] ?? 'text';
    final replySender = _replyTo?['senderName'] ?? '';
    final preview     = replyType == 'image' ? '📷 Фото'
        : replyType == 'audio' ? '🎤 Голосовое' : replyText;

    return Container(
      color: surface,
      padding: const EdgeInsets.fromLTRB(16, 8, 8, 0),
      child: Row(children: [
        Container(width: 3, height: 36,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(3),
            gradient: const LinearGradient(
              colors: [Color(0xFF7C6FFF), Color(0xFF38BDF8)],
              begin: Alignment.topCenter, end: Alignment.bottomCenter),
          )),
        const SizedBox(width: 10),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(replySender, style: const TextStyle(fontFamily: 'DM Sans', fontSize: 12,
              fontWeight: FontWeight.w600, color: Color(0xFF7C6FFF))),
          Text(preview, style: TextStyle(fontFamily: 'DM Sans', fontSize: 12,
              color: dark ? Colors.white60 : Colors.black54),
            maxLines: 1, overflow: TextOverflow.ellipsis),
        ])),
        IconButton(onPressed: _cancelReply,
          icon: const Icon(Icons.close_rounded, color: Color(0xFF8B8B9E), size: 20)),
      ]),
    );
  }

  Widget _bubbleWithSwipe(Map<String, dynamic> data, bool isMe,
      bool dark, String msgId, String myUid, bool hasWallpaper,
      {String searchQuery = ''}) {
    return Dismissible(
      key: ValueKey('swipe_$msgId'),
      direction: DismissDirection.startToEnd,
      confirmDismiss: (_) async { _setReply(data, msgId); return false; },
      background: Align(
        alignment: Alignment.centerLeft,
        child: Padding(
          padding: const EdgeInsets.only(left: 16),
          child: Container(
            width: 36, height: 36,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                colors: [Color(0xFF7C6FFF), Color(0xFF38BDF8)],
                begin: Alignment.topLeft, end: Alignment.bottomRight),
            ),
            child: const Icon(Icons.reply_rounded, color: Colors.white, size: 18),
          ),
        ),
      ),
      child: _bubble(data, isMe, dark, msgId, myUid, hasWallpaper, searchQuery: searchQuery),
    );
  }

  Widget _bubble(Map data, bool isMe, bool dark,
      String msgId, String myUid, bool hasWallpaper, {String searchQuery = ''}) {
    // Удалённое у всех
    if (data['type'] == 'deleted') {
      return Align(
        alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 3),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: (dark ? const Color(0xFF2A2A3D) : const Color(0xFFE8E8F0))
                .withOpacity(0.5),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.do_not_disturb_rounded,
                size: 14, color: const Color(0xFF8B8B9E).withOpacity(0.7)),
            const SizedBox(width: 6),
            Text('Сообщение удалено',
              style: TextStyle(fontFamily: 'DM Sans', fontSize: 13,
                  fontStyle: FontStyle.italic,
                  color: const Color(0xFF8B8B9E).withOpacity(0.7))),
          ]),
        ),
      );
    }

    final text      = data['text'] ?? '';
    final sender    = data['senderName'] ?? '';
    final imageUrl  = data['imageUrl'] as String?;
    final audioUrl  = data['audioUrl'] as String?;
    final ts        = data['createdAt'] as Timestamp?;
    final time      = ts != null ? DateFormat('HH:mm').format(ts.toDate().toLocal()) : '';
    final isEdited  = data['edited'] == true;
    final fileUrl   = data['fileUrl']  as String?;
    final fileName  = data['fileName'] as String? ?? 'Файл';
    final fileSize  = data['fileSize'] as int? ?? 0;
    final fileExt   = data['fileExt']  as String? ?? '';
    final isImage   = data['type'] == 'image' && imageUrl != null;
    final isAudio   = data['type'] == 'audio' && audioUrl != null;
    final isFile    = data['type'] == 'file'  && fileUrl  != null;
    final isPlaying = _playingId == msgId;
    final replyTo       = data['replyTo']       as Map<String, dynamic>?;
    final forwardedFrom = data['forwardedFrom'] as String?;
    final reactionsRaw = data['reactions'] as Map<String, dynamic>? ?? {};
    final reactions    = reactionsRaw.map((e, u) => MapEntry(e, List<String>.from(u)));

    // Цвета пузырей — адаптируем под обои
    final myBubbleColor = hasWallpaper
        ? Colors.black.withOpacity(0.35)
        : const Color(0xFF2D2A5E);
    final otherBubbleColor = hasWallpaper
        ? Colors.white.withOpacity(0.15)
        : (dark ? const Color(0xFF2A2A3D) : const Color(0xFFE8E8F0));

    return GestureDetector(
      onLongPress: () => _showReactionPicker(msgId, isMe),
      child: Align(
        alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
        child: Column(
          crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            Container(
              margin: const EdgeInsets.symmetric(vertical: 3),
              padding: EdgeInsets.all(isImage ? 6 : (isFile ? 8 : 12)),
              constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
              decoration: BoxDecoration(
                color: isMe ? myBubbleColor : otherBubbleColor,
                borderRadius: BorderRadius.only(
                  topLeft:     const Radius.circular(18),
                  topRight:    const Radius.circular(18),
                  bottomLeft:  Radius.circular(isMe ? 18 : 4),
                  bottomRight: Radius.circular(isMe ? 4 : 18),
                ),
                boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.15), blurRadius: 8)],
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                if (!isMe && sender.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4, left: 4),
                    child: Text(sender, style: const TextStyle(fontFamily: 'DM Sans',
                        fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF7C6FFF))),
                  ),

                if (forwardedFrom != null && forwardedFrom.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6, left: 4),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      const Icon(Icons.forward_rounded, size: 13, color: Color(0xFF38BDF8)),
                      const SizedBox(width: 4),
                      Text('Переслано от $forwardedFrom',
                        style: const TextStyle(fontFamily: 'DM Sans',
                            fontSize: 11, color: Color(0xFF38BDF8),
                            fontStyle: FontStyle.italic)),
                    ]),
                  ),

                if (replyTo != null)
                  Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(10),
                      color: Colors.black.withOpacity(0.15),
                      border: Border(left: BorderSide(
                          color: const Color(0xFF7C6FFF).withOpacity(0.8), width: 3)),
                    ),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(replyTo['senderName'] ?? '', style: const TextStyle(
                          fontFamily: 'DM Sans', fontSize: 11,
                          fontWeight: FontWeight.w600, color: Color(0xFF7C6FFF))),
                      const SizedBox(height: 2),
                      Text(
                        replyTo['type'] == 'image' ? '📷 Фото'
                            : replyTo['type'] == 'audio' ? '🎤 Голосовое'
                            : (replyTo['text'] ?? ''),
                        style: TextStyle(fontFamily: 'DM Sans', fontSize: 12,
                            color: Colors.white.withOpacity(0.6)),
                        maxLines: 2, overflow: TextOverflow.ellipsis),
                    ]),
                  ),

                if (isAudio)
                  _AudioBubble(
                    audioUrl: audioUrl!,
                    msgId: msgId,
                    isMe: isMe,
                    isPlaying: isPlaying,
                    duration: data['audioDuration'] as int? ?? 0,
                    onTap: () => _playAudio(audioUrl!, msgId),
                  )
                else if (isImage)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.network(imageUrl!, width: 220, fit: BoxFit.cover,
                      loadingBuilder: (_, child, progress) => progress == null ? child
                          : const SizedBox(width: 220, height: 160,
                              child: Center(child: CircularProgressIndicator(color: Color(0xFF7C6FFF))))),
                  )
                else if (isFile)
                  GestureDetector(
                    onTap: () async {
                      try {
                        await _channel.invokeMethod('openUrl', {'url': fileUrl});
                      } catch (_) {
                        if (mounted) ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Открой ссылку: $fileUrl')));
                      }
                    },
                    child: Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        color: Colors.white.withOpacity(0.08),
                      ),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Container(
                          width: 40, height: 40,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(10),
                            color: const Color(0xFF7C6FFF).withOpacity(0.2),
                          ),
                          child: Center(child: Text(
                            fileExt.replaceAll('.', '').toUpperCase(),
                            style: const TextStyle(fontFamily: 'Syne',
                                fontSize: 10, fontWeight: FontWeight.w800,
                                color: Color(0xFF7C6FFF)))),
                        ),
                        const SizedBox(width: 10),
                        Flexible(child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(fileName, style: const TextStyle(
                                fontFamily: 'DM Sans', fontSize: 13,
                                fontWeight: FontWeight.w500, color: Colors.white),
                              overflow: TextOverflow.ellipsis, maxLines: 2),
                            const SizedBox(height: 2),
                            Text(_formatSize(fileSize), style: TextStyle(
                                fontFamily: 'DM Sans', fontSize: 11,
                                color: Colors.white.withOpacity(0.5))),
                          ],
                        )),
                        const SizedBox(width: 8),
                        Icon(Icons.download_rounded,
                            color: Colors.white.withOpacity(0.5), size: 18),
                      ]),
                    ),
                  )
                else
                  _highlightText(
                    text,
                    _searchQuery,
                    TextStyle(fontFamily: 'DM Sans', fontSize: 15,
                        color: hasWallpaper ? Colors.white
                            : (isMe ? Colors.white
                                : (dark ? Colors.white : const Color(0xFF0F0F1A)))),
                  ),

                const SizedBox(height: 4),
                Align(
                  alignment: Alignment.centerRight,
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    if (isEdited) ...[
                      Text('изменено', style: TextStyle(fontFamily: 'DM Sans', fontSize: 10,
                          fontStyle: FontStyle.italic,
                          color: hasWallpaper
                              ? Colors.white.withOpacity(0.4)
                              : (isMe ? Colors.white.withOpacity(0.4) : const Color(0xFF8B8B9E)))),
                      const SizedBox(width: 4),
                    ],
                    Text(time, style: TextStyle(fontFamily: 'DM Sans', fontSize: 11,
                        color: hasWallpaper
                            ? Colors.white.withOpacity(0.5)
                            : (isMe ? Colors.white.withOpacity(0.5) : const Color(0xFF8B8B9E)))),
                  ]),
                ),
              ]),
            ),

            if (reactions.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 4, left: 4, right: 4),
                child: Wrap(
                  spacing: 4,
                  children: reactions.entries.map((entry) {
                    final emoji = entry.key;
                    final users = entry.value;
                    final count = users.length;
                    final iMine = users.contains(myUid);
                    return GestureDetector(
                      onTap: () => _toggleReaction(msgId, emoji),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          color: iMine
                              ? const Color(0xFF7C6FFF).withOpacity(0.25)
                              : Colors.white.withOpacity(0.08),
                          border: Border.all(
                            color: iMine ? const Color(0xFF7C6FFF).withOpacity(0.6) : Colors.transparent,
                            width: 1),
                        ),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          Text(emoji, style: const TextStyle(fontSize: 14)),
                          if (count > 1) ...[
                            const SizedBox(width: 4),
                            Text('$count', style: TextStyle(fontFamily: 'DM Sans', fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: iMine ? const Color(0xFF7C6FFF) : Colors.white70)),
                          ],
                        ]),
                      ),
                    );
                  }).toList(),
                ),
              ),
          ],
        ),
      ),
    );
  }

  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes Б';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} КБ';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} МБ';
  }

  Widget _channelReadonlyBar(Color surface, bool dark) => Container(
    color: surface,
    padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
    child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
      Icon(Icons.campaign_rounded, color: const Color(0xFF8B8B9E), size: 16),
      const SizedBox(width: 8),
      Text('Только владелец может писать в канал',
        style: const TextStyle(fontFamily: 'DM Sans', fontSize: 12,
            color: Color(0xFF8B8B9E))),
    ]),
  );

  Widget _inputBar(Color surface, bool dark) => Container(
    color: surface,
    padding: const EdgeInsets.fromLTRB(8, 8, 8, 16),
    child: Row(children: [
      if (!_isRecording) ...[
        IconButton(
          onPressed: _toggleEmoji,
          icon: Icon(
            _showEmoji ? Icons.keyboard_rounded : Icons.emoji_emotions_rounded,
            color: _showEmoji ? const Color(0xFF7C6FFF) : const Color(0xFF8B8B9E)),
        ),
        IconButton(
          onPressed: _pickFile,
          icon: const Icon(Icons.attach_file_rounded, color: Color(0xFF8B8B9E)),
        ),
      ] else
        const SizedBox(width: 16),
      Expanded(
        child: _isRecording
          ? _RecordingWave(wave: _recWave, seconds: _recSeconds)
          : TextField(
              controller: _ctrl, focusNode: _focus,
              style: TextStyle(fontFamily: 'DM Sans', fontSize: 15,
                color: dark ? const Color(0xFFF0F0F5) : const Color(0xFF0F0F1A)),
              decoration: InputDecoration(
                hintText: 'Сообщение...',
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              ),
              onSubmitted: (_) => _send(),
              textInputAction: TextInputAction.send,
            ),
      ),
      const SizedBox(width: 8),
      AnimatedSwitcher(
        duration: const Duration(milliseconds: 200),
        child: _hasText
            ? GestureDetector(
                key: const ValueKey('send'),
                onTap: () => _editingMsgId != null ? _saveEdit() : _send(),
                child: Container(
                  width: 46, height: 46,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      colors: [Color(0xFF7C6FFF), Color(0xFF38BDF8)],
                      begin: Alignment.topLeft, end: Alignment.bottomRight),
                  ),
                  child: Icon(
                    _editingMsgId != null ? Icons.check_rounded : Icons.send_rounded,
                    color: Colors.white, size: 20),
                ),
              )
            : GestureDetector(
                key: const ValueKey('mic'),
                onLongPressStart: (_) => _startRecording(),
                onLongPressEnd:   (_) => _stopRecording(),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: 46, height: 46,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      colors: _isRecording
                          ? [const Color(0xFFFF5E7D), const Color(0xFFFF9A3C)]
                          : [const Color(0xFF7C6FFF), const Color(0xFF38BDF8)],
                      begin: Alignment.topLeft, end: Alignment.bottomRight),
                    boxShadow: _isRecording ? [BoxShadow(
                        color: const Color(0xFFFF5E7D).withOpacity(0.5), blurRadius: 16)] : [],
                  ),
                  child: Icon(_isRecording ? Icons.stop_rounded : Icons.mic_rounded,
                      color: Colors.white, size: 22),
                ),
              ),
      ),
    ]),
  );
}

class _MessageMenu extends StatelessWidget {
  final String            msgId;
  final bool              isMe;
  final bool              isPinned;
  final List<String>      reactions;
  final void Function(String)               onReact;
  final void Function(Map<String, dynamic>) onReply;
  final VoidCallback      onPin;
  final VoidCallback      onUnpin;
  final VoidCallback               onForward;
  final void Function(bool forAll)  onDelete;
  final void Function(String text)  onEdit;
  final Map<String, dynamic>        msgData;

  const _MessageMenu({
    required this.msgId, required this.isMe, required this.isPinned,
    required this.reactions, required this.onReact, required this.onReply,
    required this.onPin, required this.onUnpin, required this.onForward,
    required this.onDelete, required this.onEdit, required this.msgData,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      decoration: BoxDecoration(
        color: const Color(0xFF13131A),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.4), blurRadius: 24)],
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        // Реакции
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 12, 8, 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: reactions.map((emoji) =>
              GestureDetector(
                onTap: () => onReact(emoji),
                child: TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0.5, end: 1.0),
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.elasticOut,
                  builder: (_, scale, child) => Transform.scale(scale: scale, child: child),
                  child: Container(
                    width: 48, height: 48,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white.withOpacity(0.05),
                    ),
                    child: Center(child: Text(emoji, style: const TextStyle(fontSize: 26))),
                  ),
                ),
              ),
            ).toList(),
          ),
        ),

        Divider(color: Colors.white.withOpacity(0.06), height: 1),

        // Действия
        _action(Icons.reply_rounded, 'Ответить',
            () => onReply(msgData)),
        _action(Icons.forward_rounded, 'Переслать', onForward),
        if (isMe && (msgData['type'] == 'text' || msgData['type'] == null))
          _action(Icons.edit_rounded, 'Изменить',
              () => onEdit(msgData['text'] as String? ?? '')),
        _action(
          isPinned ? Icons.push_pin_outlined : Icons.push_pin_rounded,
          isPinned ? 'Открепить' : 'Закрепить',
          isPinned ? onUnpin : onPin,
          color: const Color(0xFF7C6FFF),
        ),
        if (isMe)
          _action(Icons.delete_sweep_rounded, 'Удалить у всех',
              () => onDelete(true), color: const Color(0xFFFF5E7D)),
        _action(Icons.delete_outline_rounded, 'Удалить у себя',
            () => onDelete(false), color: const Color(0xFFFF5E7D).withOpacity(0.7)),

        const SizedBox(height: 8),
      ]),
    );
  }

  Widget _action(IconData icon, String label, VoidCallback onTap, {Color? color}) =>
    InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        child: Row(children: [
          Icon(icon, color: color ?? Colors.white70, size: 20),
          const SizedBox(width: 14),
          Text(label, style: TextStyle(fontFamily: 'DM Sans', fontSize: 15,
              fontWeight: FontWeight.w500,
              color: color ?? Colors.white)),
        ]),
      ),
    );
}

class _ReactionPicker extends StatelessWidget {
  final List<String> reactions;
  final void Function(String) onReact;
  const _ReactionPicker({required this.reactions, required this.onReact});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF13131A),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.4), blurRadius: 24)],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: reactions.map((emoji) =>
          GestureDetector(
            onTap: () => onReact(emoji),
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0.5, end: 1.0),
              duration: const Duration(milliseconds: 300),
              curve: Curves.elasticOut,
              builder: (_, scale, child) => Transform.scale(scale: scale, child: child),
              child: Container(
                width: 48, height: 48,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withOpacity(0.05),
                ),
                child: Center(child: Text(emoji, style: const TextStyle(fontSize: 26))),
              ),
            ),
          ),
        ).toList(),
      ),
    );
  }
}

// ── Виджет голосового сообщения с псевдо-волной ──────────────────────────────
class _AudioBubble extends StatefulWidget {
  final String   audioUrl;
  final String   msgId;
  final bool     isMe;
  final bool     isPlaying;
  final int      duration; // секунды
  final VoidCallback onTap;

  const _AudioBubble({
    required this.audioUrl, required this.msgId, required this.isMe,
    required this.isPlaying, required this.duration, required this.onTap,
  });

  @override State<_AudioBubble> createState() => _AudioBubbleState();
}

class _AudioBubbleState extends State<_AudioBubble>
    with SingleTickerProviderStateMixin {
  late AnimationController _anim;

  // Псевдо-волна — фиксированные высоты баров (генерируем из url hashcode)
  late List<double> _bars;

  @override
  void initState() {
    super.initState();
    _anim = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 600))
      ..repeat(reverse: true);
    _generateBars();
  }

  void _generateBars() {
    final seed = widget.audioUrl.hashCode.abs();
    final rng  = List.generate(28, (i) {
      final v = ((seed * (i + 1) * 2654435761) & 0xFFFFFFFF) / 0xFFFFFFFF;
      // Форма волны — выше в середине
      final center = (i - 14).abs() / 14.0;
      return 0.2 + (1.0 - center * 0.6) * v * 0.8;
    });
    _bars = rng;
  }

  @override
  void didUpdateWidget(_AudioBubble old) {
    super.didUpdateWidget(old);
    if (widget.isPlaying && !_anim.isAnimating) {
      _anim.repeat(reverse: true);
    } else if (!widget.isPlaying && _anim.isAnimating) {
      _anim.stop();
      _anim.value = 0;
    }
  }

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  String _fmt(int secs) {
    final m = secs ~/ 60;
    final s = secs % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final activeColor  = widget.isMe
        ? Colors.white
        : const Color(0xFF7C6FFF);
    final inactiveColor = widget.isMe
        ? Colors.white.withOpacity(0.3)
        : const Color(0xFF7C6FFF).withOpacity(0.25);

    return GestureDetector(
      onTap: widget.onTap,
      child: SizedBox(
        width: 220,
        child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
          // Кнопка play/pause
          Container(
            width: 38, height: 38,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: widget.isMe
                  ? const LinearGradient(
                      colors: [Colors.white24, Colors.white10],
                      begin: Alignment.topLeft, end: Alignment.bottomRight)
                  : const LinearGradient(
                      colors: [Color(0xFF7C6FFF), Color(0xFF38BDF8)],
                      begin: Alignment.topLeft, end: Alignment.bottomRight),
            ),
            child: Icon(
              widget.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
              color: widget.isMe ? Colors.white : Colors.white,
              size: 20),
          ),
          const SizedBox(width: 10),

          // Волна + длительность
          Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Волна
              SizedBox(
                height: 28,
                child: AnimatedBuilder(
                  animation: _anim,
                  builder: (_, __) => Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: List.generate(_bars.length, (i) {
                      // Активные бары анимируются
                      final isActive = widget.isPlaying && i < _bars.length * 0.6;
                      final animFactor = isActive
                          ? 0.5 + 0.5 * _anim.value * (i % 3 == 0 ? 1.0 : i % 3 == 1 ? 0.7 : 0.4)
                          : 1.0;
                      final h = (_bars[i] * 24 * animFactor).clamp(3.0, 24.0);
                      return AnimatedContainer(
                        duration: const Duration(milliseconds: 100),
                        width: 3,
                        height: h,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(2),
                          color: widget.isPlaying && i < _bars.length * 0.6
                              ? activeColor
                              : inactiveColor,
                        ),
                      );
                    }),
                  ),
                ),
              ),
              const SizedBox(height: 3),
              // Длительность
              Text(
                widget.duration > 0 ? _fmt(widget.duration) : '0:00',
                style: TextStyle(
                  fontFamily: 'DM Sans', fontSize: 11,
                  color: widget.isMe
                      ? Colors.white.withOpacity(0.6)
                      : const Color(0xFF8B8B9E)),
              ),
            ],
          )),
        ]),
      ),
    );
  }
}

// ── Виджет волны при записи ───────────────────────────────────────────────────
class _RecordingWave extends StatelessWidget {
  final List<double> wave;
  final int seconds;

  const _RecordingWave({required this.wave, required this.seconds});

  String get _time {
    final m = seconds ~/ 60;
    final s = seconds % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        color: const Color(0xFFFF5E7D).withOpacity(0.08),
        border: Border.all(color: const Color(0xFFFF5E7D).withOpacity(0.2)),
      ),
      child: Row(children: [
        // Мигающий индикатор записи
        _PulsingDot(),
        const SizedBox(width: 8),

        // Таймер
        Text(_time,
          style: const TextStyle(fontFamily: 'DM Sans', fontSize: 13,
              fontWeight: FontWeight.w600, color: Color(0xFFFF5E7D))),
        const SizedBox(width: 10),

        // Волна
        Expanded(
          child: wave.isEmpty
            ? const Center(child: Text('🎤',
                style: TextStyle(fontSize: 14)))
            : CustomPaint(
                painter: _WavePainter(wave),
                size: const Size(double.infinity, 28),
              ),
        ),
      ]),
    );
  }
}

class _PulsingDot extends StatefulWidget {
  @override State<_PulsingDot> createState() => _PulsingDotState();
}

class _PulsingDotState extends State<_PulsingDot>
    with SingleTickerProviderStateMixin {
  late AnimationController _anim;
  late Animation<double>   _scale;

  @override
  void initState() {
    super.initState();
    _anim = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 700))
      ..repeat(reverse: true);
    _scale = Tween(begin: 0.7, end: 1.0).animate(
        CurvedAnimation(parent: _anim, curve: Curves.easeInOut));
  }

  @override
  void dispose() { _anim.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) => ScaleTransition(
    scale: _scale,
    child: Container(
      width: 8, height: 8,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        color: Color(0xFFFF5E7D),
      ),
    ),
  );
}

class _WavePainter extends CustomPainter {
  final List<double> wave;
  _WavePainter(this.wave);

  @override
  void paint(Canvas canvas, Size size) {
    if (wave.isEmpty) return;

    final paint = Paint()
      ..color = const Color(0xFFFF5E7D)
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 2.5
      ..style = PaintingStyle.fill;

    final barW   = (size.width / wave.length).clamp(2.0, 6.0);
    final gap    = (size.width - barW * wave.length) / (wave.length - 1);
    final centerY = size.height / 2;

    for (int i = 0; i < wave.length; i++) {
      final x    = i * (barW + gap);
      final h    = wave[i] * size.height * 0.9;
      final top  = centerY - h / 2;

      // Цвет градиентом — свежие бары ярче
      final alpha = 0.3 + 0.7 * (i / wave.length);
      paint.color = Color.fromRGBO(255, 94, 125, alpha);

      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x, top, barW, h),
          const Radius.circular(2)),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_WavePainter old) => old.wave != wave;
}
