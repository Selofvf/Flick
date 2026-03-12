import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../core/widgets/grid_background.dart';
import '../../story/screens/story_screen.dart';
import '../../story/screens/add_story_screen.dart';

class ChatsListScreen extends ConsumerStatefulWidget {
  const ChatsListScreen({super.key});
  @override ConsumerState<ChatsListScreen> createState() => _ChatsListScreenState();
}

class _ChatsListScreenState extends ConsumerState<ChatsListScreen> {
  final _auth   = FirebaseAuth.instance;
  final _db     = FirebaseFirestore.instance;
  final _search = TextEditingController();
  final _scroll = ScrollController();

  List<Map<String, dynamic>> _chats      = [];
  List<Map<String, dynamic>> _stories    = [];
  List<Map<String, dynamic>> _broadcasts = [];
  bool _loading = true;
  String? _notesId; // id чата-заметок

  @override
  void initState() {
    super.initState();
    _loadChats();
    _loadStories();
    _ensureNotes();
    _listenBroadcasts();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _loadChats();
  }

  @override
  void dispose() {
    _scroll.dispose();
    _search.dispose();
    super.dispose();
  }

  // Создаёт или находит чат-заметки для текущего пользователя
  void _listenBroadcasts() {
    _db.collection('broadcasts')
        .orderBy('createdAt', descending: true)
        .limit(5)
        .snapshots()
        .listen((snap) {
      if (!mounted) return;
      setState(() {
        _broadcasts = snap.docs.map((d) => {...d.data(), 'id': d.id}).toList();
      });
    });
  }

  Future<void> _ensureNotes() async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return;
    final snap = await _db.collection('chats')
        .where('type', isEqualTo: 'notes')
        .where('members', arrayContains: uid)
        .limit(1)
        .get();
    if (snap.docs.isNotEmpty) {
      setState(() => _notesId = snap.docs.first.id);
    } else {
      final doc = await _db.collection('chats').add({
        'type'       : 'notes',
        'members'    : [uid],
        'name'       : 'Мои заметки',
        'createdAt'  : FieldValue.serverTimestamp(),
        'updatedAt'  : FieldValue.serverTimestamp(),
        'lastMessage': '',
      });
      setState(() => _notesId = doc.id);
    }
  }

  Future<void> _loadChats() async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return;
    try {
      final snap = await _db
          .collection('chats')
          .where('members', arrayContains: uid)
          .orderBy('updatedAt', descending: true)
          .get();

      final chats = snap.docs.map((d) => {...d.data(), 'id': d.id}).toList();

      // Подгружаем avatarUrl
      for (final chat in chats) {
        final type = chat['type'] as String? ?? 'direct';
        if (type == 'direct') {
          // Для личных чатов — берём аватар собеседника
          final members = List<String>.from(chat['members'] ?? []);
          final otherId = members.firstWhere((m) => m != uid, orElse: () => '');
          if (otherId.isNotEmpty) {
            try {
              final userDoc = await _db.collection('users').doc(otherId).get();
              chat['_avatarUrl'] = userDoc.data()?['avatarUrl'];
            } catch (_) {}
          }
        } else {
          // Для групп и каналов — берём аватар прямо из документа чата
          chat['_avatarUrl'] = chat['avatarUrl'];
        }
      }

      setState(() {
        _chats   = chats;
        _loading = false;
      });
    } catch (_) {
      setState(() => _loading = false);
    }
  }

  Future<void> _loadStories() async {
    try {
      final now  = Timestamp.now();
      final snap = await _db
          .collection('stories')
          .where('expiresAt', isGreaterThan: now)
          .orderBy('expiresAt', descending: false)
          .orderBy('createdAt', descending: false)
          .get();
      final Map<String, List<Map<String, dynamic>>> byUser = {};
      for (final doc in snap.docs) {
        final data = {...doc.data(), 'id': doc.id};
        final uid  = data['uid'] as String? ?? '';
        byUser.putIfAbsent(uid, () => []).add(data);
      }
      // Подгружаем avatarUrl из коллекции users
      final result = <Map<String, dynamic>>[];
      for (final e in byUser.entries) {
        String avatarUrl = '';
        try {
          final userDoc = await _db.collection('users').doc(e.key).get();
          avatarUrl = userDoc.data()?['avatarUrl'] ?? '';
        } catch (_) {}
        result.add({
          'uid'      : e.key,
          'username' : e.value.first['username'] ?? '?',
          'avatarUrl': avatarUrl,
          'stories'  : e.value,
          'latest'   : e.value.last,
        });
      }
      setState(() => _stories = result);
    } catch (_) {}
  }

  String _name(Map chat) {
    final uid   = _auth.currentUser?.uid ?? '';
    final names = Map<String, dynamic>.from(chat['names'] ?? {});
    if (names.isNotEmpty) {
      final entry = names.entries.where((e) => e.key != uid).firstOrNull;
      if (entry != null && entry.value.toString().isNotEmpty) {
        return entry.value.toString();
      }
    }
    if (chat['name'] != null && chat['name'].toString().isNotEmpty) {
      return chat['name'].toString();
    }
    return 'Неизвестный';
  }

  // ── Выйти из чата (убираем себя из members) ──────────────────────────────
  Future<void> _leaveChat(Map chat) async {
    final uid    = _auth.currentUser?.uid ?? '';
    final chatId = chat['id'] as String;
    final members = List<String>.from(chat['members'] ?? []);

    final confirmed = await _confirmDialog(
      title: 'Выйти из чата',
      message: 'Вы покинете «${_name(chat)}». Вернуться можно только если вас добавят снова.',
      confirmText: 'Выйти',
      confirmColor: const Color(0xFFFF9A3C),
    );
    if (!confirmed) return;

    members.remove(uid);
    if (members.isEmpty) {
      // Если никого не осталось — удаляем чат
      await _db.collection('chats').doc(chatId).delete();
    } else {
      await _db.collection('chats').doc(chatId).update({'members': members});
    }
    await _loadChats();
  }

  // ── Удалить чат (только для создателя или direct) ────────────────────────
  Future<void> _deleteChat(Map chat) async {
    final chatId = chat['id'] as String;
    final type   = chat['type'] as String? ?? 'direct';

    final confirmed = await _confirmDialog(
      title: type == 'direct' ? 'Удалить чат' : 'Удалить ${type == 'group' ? 'группу' : 'канал'}',
      message: 'Это действие нельзя отменить. Все сообщения будут удалены.',
      confirmText: 'Удалить',
      confirmColor: const Color(0xFFFF5E7D),
    );
    if (!confirmed) return;

    // Удаляем сообщения
    final msgs = await _db.collection('chats').doc(chatId).collection('messages').get();
    for (final doc in msgs.docs) { await doc.reference.delete(); }
    // Удаляем чат
    await _db.collection('chats').doc(chatId).delete();
    await _loadChats();
  }

  Future<bool> _confirmDialog({
    required String title,
    required String message,
    required String confirmText,
    required Color confirmColor,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (dialogCtx) => AlertDialog(
        backgroundColor: const Color(0xFF13131A),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(title, style: const TextStyle(
            fontFamily: 'Syne', fontWeight: FontWeight.w800, color: Colors.white)),
        content: Text(message, style: const TextStyle(
            fontFamily: 'DM Sans', fontSize: 14, color: Color(0xFF8B8B9E))),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(false),
            child: const Text('Отмена',
                style: TextStyle(color: Color(0xFF8B8B9E)))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: confirmColor),
            onPressed: () => Navigator.of(dialogCtx).pop(true),
            child: Text(confirmText)),
        ],
      ),
    );
    return result ?? false;
  }

  void _showChatActions(Map chat) {
    final dark    = Theme.of(context).brightness == Brightness.dark;
    final uid     = _auth.currentUser?.uid ?? '';
    final type    = chat['type'] as String? ?? 'direct';
    final creator = chat['creatorId'] as String? ?? '';
    final isOwner = creator == uid;
    final isDirect = type == 'direct';

    HapticFeedback.mediumImpact();

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        decoration: BoxDecoration(
          color: dark ? const Color(0xFF13131A) : Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          border: Border.all(color: Colors.white.withOpacity(0.06)),
        ),
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 40),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 40, height: 4,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.2),
              borderRadius: BorderRadius.circular(99))),
          const SizedBox(height: 16),

          // Название чата
          Row(children: [
            Container(
              width: 42, height: 42,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  colors: [Color(0xFF7C6FFF), Color(0xFF38BDF8)],
                  begin: Alignment.topLeft, end: Alignment.bottomRight),
              ),
              child: Center(child: Text(
                _name(chat).isNotEmpty ? _name(chat)[0].toUpperCase() : '?',
                style: const TextStyle(fontFamily: 'Syne', fontSize: 16,
                    fontWeight: FontWeight.w800, color: Colors.white))),
            ),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(_name(chat), style: const TextStyle(fontFamily: 'Syne',
                  fontSize: 16, fontWeight: FontWeight.w800, color: Colors.white)),
              Text(isDirect ? 'Личный чат'
                  : type == 'group' ? 'Группа' : 'Канал',
                style: const TextStyle(fontFamily: 'DM Sans',
                    fontSize: 12, color: Color(0xFF8B8B9E))),
            ])),
          ]),

          const SizedBox(height: 20),
          const Divider(color: Colors.white10),
          const SizedBox(height: 12),

          // Выйти (для групп и каналов)
          if (!isDirect) ...[
            _actionBtn(
              icon: Icons.exit_to_app_rounded,
              label: 'Выйти из ${type == 'group' ? 'группы' : 'канала'}',
              color: const Color(0xFFFF9A3C),
              onTap: () { Navigator.pop(context); _leaveChat(chat); },
            ),
            const SizedBox(height: 10),
          ],

          // Удалить (для direct всегда, для групп/каналов только владелец)
          if (isDirect || isOwner)
            _actionBtn(
              icon: Icons.delete_rounded,
              label: isDirect ? 'Удалить чат'
                  : 'Удалить ${type == 'group' ? 'группу' : 'канал'}',
              color: const Color(0xFFFF5E7D),
              onTap: () { Navigator.pop(context); _deleteChat(chat); },
            ),
        ]),
      ),
    );
  }

  Widget _actionBtn({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) =>
    GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withOpacity(0.3)),
        ),
        child: Row(children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 12),
          Text(label, style: TextStyle(fontFamily: 'DM Sans', fontSize: 15,
              fontWeight: FontWeight.w500, color: color)),
        ]),
      ),
    );

  @override
  Widget build(BuildContext context) {
    final dark    = Theme.of(context).brightness == Brightness.dark;
    final bg      = dark ? const Color(0xFF0A0A0F) : const Color(0xFFF0F2F8);
    final surface = dark ? const Color(0xFF13131A) : Colors.white;
    final muted   = dark ? const Color(0xFF8B8B9E) : const Color(0xFF6B7280);
    final textCol = dark ? const Color(0xFFF0F0F5) : const Color(0xFF0F0F1A);

    // Заметки показываем отдельно — убираем из основного списка
    final chatsOnly = _chats.where((c) => c['type'] != 'notes').toList();
    final filtered = _search.text.isEmpty
        ? chatsOnly
        : chatsOnly.where((c) =>
            _name(c).toLowerCase().contains(_search.text.toLowerCase())).toList();

    return Scaffold(
      backgroundColor: bg,
      body: GridBackground(
        child: CustomScrollView(
          controller: _scroll,
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverAppBar(
              backgroundColor: surface,
              floating: true,
              snap: true,
              pinned: false,
              automaticallyImplyLeading: false,
              titleSpacing: 16,
              expandedHeight: 210,
              collapsedHeight: kToolbarHeight,
              title: Row(children: [
                Image.asset(
                  'assets/icons/flick_logo.png',
                  width: 32,
                  height: 32,
                ),
                const SizedBox(width: 10),
                ShaderMask(
                  shaderCallback: (b) => const LinearGradient(
                    colors: [Colors.white, Color(0xFFB49FFF)]).createShader(b),
                  child: const Text('Flick',
                    style: TextStyle(fontFamily: 'Syne', fontSize: 18,
                      fontWeight: FontWeight.w800, color: Colors.white)),
                ),
              ]),
              actions: [
                IconButton(
                  onPressed: () => context.push('/search'),
                  icon: const Icon(Icons.search_rounded, size: 24),
                  tooltip: 'Поиск',
                ),
              ],
              flexibleSpace: FlexibleSpaceBar(
                collapseMode: CollapseMode.pin,
                background: Column(children: [
                  SizedBox(height: kToolbarHeight + MediaQuery.of(context).padding.top),
                  Container(
                    color: surface,
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                    child: TextField(
                      controller: _search,
                      onChanged: (_) => setState(() {}),
                      style: TextStyle(fontFamily: 'DM Sans', fontSize: 14, color: textCol),
                      decoration: InputDecoration(
                        hintText: 'Поиск...',
                        prefixIcon: Icon(Icons.search_rounded, color: muted, size: 20),
                        contentPadding: const EdgeInsets.symmetric(vertical: 10, horizontal: 14),
                      ),
                    ),
                  ),
                  Container(
                    color: surface,
                    padding: const EdgeInsets.only(bottom: 8),
                    child: SizedBox(
                      height: 80,
                      child: ListView(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        children: [
                          _addStoryBtn(dark),
                          ..._stories.map((u) => _storyAvatar(u, dark)),
                        ],
                      ),
                    ),
                  ),
                ]),
              ),
            ),

            if (_loading)
              const SliverFillRemaining(
                child: Center(child: CircularProgressIndicator(color: Color(0xFF7C6FFF))))
            else ...[
              // Плашка заметок всегда сверху
              // Рассылки от администрации
              if (_broadcasts.isNotEmpty)
                SliverToBoxAdapter(child: _broadcastBanner(dark, _broadcasts.first)),

              if (_notesId != null)
                SliverToBoxAdapter(child: _notesTile(dark, surface, muted)),

              if (filtered.isEmpty)
                SliverFillRemaining(child: _empty(dark))
              else
                SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (_, i) => _tile(filtered[i], dark, surface, muted, textCol),
                    childCount: filtered.length,
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _broadcastBanner(bool dark, Map<String, dynamic> broadcast) {
    final text = broadcast['text'] as String? ?? '';
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 10, 16, 4),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: dark ? const Color(0xFF1C1C27) : Colors.white,
        border: Border.all(color: const Color(0xFFFF5E7D).withOpacity(0.3)),
      ),
      child: Row(children: [
        Container(
          width: 36, height: 36,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: const Color(0xFFFF5E7D).withOpacity(0.15),
          ),
          child: const Icon(Icons.campaign_rounded,
              color: Color(0xFFFF5E7D), size: 20),
        ),
        const SizedBox(width: 12),
        Expanded(child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('📢 Сообщение от администрации',
              style: TextStyle(fontFamily: 'DM Sans', fontSize: 11,
                  fontWeight: FontWeight.w600, color: Color(0xFFFF5E7D))),
            const SizedBox(height: 2),
            Text(text,
              style: TextStyle(fontFamily: 'DM Sans', fontSize: 13,
                  color: dark ? Colors.white70 : const Color(0xFF4B4B6B))),
          ],
        )),
      ]),
    );
  }

  Widget _notesTile(bool dark, Color surface, Color muted) {
    final textCol = dark ? const Color(0xFFF0F0F5) : const Color(0xFF0F0F1A);
    return InkWell(
      onTap: () => context.push('/chat/$_notesId'),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: surface,
          border: Border(bottom: BorderSide(color: Colors.white.withOpacity(0.06))),
        ),
        child: Row(children: [
          // Аватарка — градиентный круг с закладкой
          Container(
            width: 48, height: 48,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                colors: [Color(0xFF7C6FFF), Color(0xFF38BDF8)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: const Icon(Icons.bookmark_rounded, color: Colors.white, size: 24),
          ),
          const SizedBox(width: 12),
          Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Мои заметки',
                style: TextStyle(fontFamily: 'DM Sans', fontSize: 14,
                    fontWeight: FontWeight.w500, color: textCol)),
              Text('Сохраняй всё важное',
                style: TextStyle(fontFamily: 'DM Sans', fontSize: 13, color: muted)),
            ],
          )),
        ]),
      ),
    );
  }

  Widget _addStoryBtn(bool dark) {
    final myUid   = _auth.currentUser?.uid ?? '';
    final myStory = _stories.where((s) => s['uid'] == myUid).firstOrNull;

    return GestureDetector(
      onTap: () async {
        final added = await Navigator.push<bool>(context,
            MaterialPageRoute(builder: (_) => const AddStoryScreen()));
        if (added == true) _loadStories();
      },
      child: Container(
        width: 58,
        margin: const EdgeInsets.only(right: 10),
        child: Column(children: [
          Stack(children: [
            Container(
              width: 54, height: 54,
              padding: const EdgeInsets.all(2.5),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                gradient: myStory != null
                    ? const LinearGradient(
                        colors: [Color(0xFF7C6FFF), Color(0xFF38BDF8)],
                        begin: Alignment.topLeft, end: Alignment.bottomRight)
                    : null,
                color: myStory == null ? Colors.white.withOpacity(0.1) : null,
              ),
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  gradient: const LinearGradient(
                    colors: [Color(0xFF7C6FFF), Color(0xFF38BDF8)],
                    begin: Alignment.topLeft, end: Alignment.bottomRight),
                ),
                child: const Center(child: Icon(Icons.person_rounded,
                    color: Colors.white, size: 24)),
              ),
            ),
            Positioned(bottom: 0, right: 0,
              child: Container(
                width: 16, height: 16,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: const LinearGradient(
                    colors: [Color(0xFF7C6FFF), Color(0xFF38BDF8)],
                    begin: Alignment.topLeft, end: Alignment.bottomRight),
                  border: Border.all(color: const Color(0xFF13131A), width: 2),
                ),
                child: const Icon(Icons.add_rounded, color: Colors.white, size: 10)),
            ),
          ]),
          const SizedBox(height: 4),
          const Text('Мой', style: TextStyle(fontFamily: 'DM Sans',
              fontSize: 10, color: Colors.white),
            overflow: TextOverflow.ellipsis),
        ]),
      ),
    );
  }

  Widget _storyAvatar(Map userStories, bool dark) {
    final name      = userStories['username'] as String? ?? '?';
    final avatarUrl = userStories['avatarUrl'] as String? ?? '';
    final stories   = (userStories['stories'] as List).cast<Map<String, dynamic>>();

    return GestureDetector(
      onTap: () => Navigator.push(context, MaterialPageRoute(
          builder: (_) => StoryScreen(stories: stories, ownerName: name))),
      child: Container(
        width: 58,
        margin: const EdgeInsets.only(right: 10),
        child: Column(children: [
          Container(
            width: 54, height: 54,
            padding: const EdgeInsets.all(2.5),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              gradient: const LinearGradient(
                colors: [Color(0xFF7C6FFF), Color(0xFF38BDF8)],
                begin: Alignment.topLeft, end: Alignment.bottomRight),
            ),
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                color: const Color(0xFF2D2A5E)),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: avatarUrl.isNotEmpty
                    ? Image.network(avatarUrl, width: 50, height: 50,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Center(
                          child: Text(name[0].toUpperCase(),
                            style: const TextStyle(fontFamily: 'Syne',
                              fontSize: 20, fontWeight: FontWeight.w800,
                              color: Colors.white))))
                    : Center(child: Text(name[0].toUpperCase(),
                        style: const TextStyle(fontFamily: 'Syne',
                          fontSize: 20, fontWeight: FontWeight.w800,
                          color: Colors.white))),
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(name, style: const TextStyle(fontFamily: 'DM Sans',
              fontSize: 10, color: Colors.white),
            overflow: TextOverflow.ellipsis, maxLines: 1),
        ]),
      ),
    );
  }

  Widget _tile(Map chat, bool dark, Color surface, Color muted, Color textCol) {
    final name     = _name(chat);
    final preview  = chat['lastMessage'] ?? '';
    final isDirect = chat['type'] == 'direct';

    return Dismissible(
      key: ValueKey('chat_${chat['id']}'),
      direction: DismissDirection.endToStart,
      confirmDismiss: (_) async {
        _showChatActions(chat);
        return false;
      },
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        color: const Color(0xFFFF5E7D).withOpacity(0.15),
        child: Container(
          width: 44, height: 44,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: const Color(0xFFFF5E7D).withOpacity(0.2),
          ),
          child: const Icon(Icons.more_horiz_rounded,
              color: Color(0xFFFF5E7D), size: 22),
        ),
      ),
      child: InkWell(
        onTap: () => context.push('/chat/${chat['id']}'),
        onLongPress: () => _showChatActions(chat),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: surface,
            border: Border(bottom: BorderSide(color: Colors.white.withOpacity(0.06))),
          ),
          child: Row(children: [
            _chatAvatar(chat, name),
            const SizedBox(width: 12),
            Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  if (!isDirect) ...[
                    Icon(chat['type'] == 'group'
                        ? Icons.group_rounded : Icons.campaign_rounded,
                        size: 14, color: const Color(0xFF7C6FFF)),
                    const SizedBox(width: 4),
                  ],
                  Expanded(child: Text(name,
                    style: TextStyle(fontFamily: 'DM Sans', fontSize: 14,
                      fontWeight: FontWeight.w500, color: textCol),
                    overflow: TextOverflow.ellipsis)),
                ]),
                if (preview.isNotEmpty)
                  Text(preview,
                    style: TextStyle(fontFamily: 'DM Sans', fontSize: 13, color: muted),
                    overflow: TextOverflow.ellipsis),
              ])),
          ]),
        ),
      ),
    );
  }

  Widget _chatAvatar(Map chat, String name) {
    final avatarUrl = chat['_avatarUrl'] as String?;
    if (avatarUrl != null && avatarUrl.isNotEmpty) {
      return Container(
        width: 48, height: 48,
        decoration: const BoxDecoration(shape: BoxShape.circle),
        child: ClipOval(
          child: Image.network(avatarUrl, width: 48, height: 48, fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => _defaultAvatar(name)),
        ),
      );
    }
    return _defaultAvatar(name);
  }

  Widget _defaultAvatar(String name) => Container(
    width: 48, height: 48,
    decoration: const BoxDecoration(
      shape: BoxShape.circle,
      gradient: LinearGradient(
        colors: [Color(0xFF7C6FFF), Color(0xFF38BDF8)],
        begin: Alignment.topLeft, end: Alignment.bottomRight),
    ),
    child: Center(child: Text(
      name.isNotEmpty ? name[0].toUpperCase() : '?',
      style: const TextStyle(fontFamily: 'Syne', fontSize: 18,
        fontWeight: FontWeight.w800, color: Colors.white))),
  );

  Widget _empty(bool dark) => Center(
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      Container(
        width: 64, height: 64,
        decoration: BoxDecoration(
          color: dark ? const Color(0xFF13131A) : Colors.white,
          borderRadius: BorderRadius.circular(20)),
        child: const Center(child: Text('💬', style: TextStyle(fontSize: 28))),
      ),
      const SizedBox(height: 16),
      Text('Нет диалогов',
        style: TextStyle(fontFamily: 'DM Sans', fontSize: 15,
          color: dark ? const Color(0xFF8B8B9E) : const Color(0xFF6B7280))),
      const SizedBox(height: 8),
      Text('Начни новый чат!',
        style: TextStyle(fontFamily: 'DM Sans', fontSize: 13,
          color: (dark ? const Color(0xFF8B8B9E) : const Color(0xFF6B7280)).withOpacity(0.6))),
    ]),
  );

  void _showCreateMenu() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => _CreateMenu(
        onCreated: _loadChats,
        onChannelCreated: (chatId) {
          _loadChats();
          context.push('/chat/$chatId');
        },
      ),
    );
  }
}

class _CreateMenu extends StatelessWidget {
  final VoidCallback onCreated;
  final void Function(String chatId)? onChannelCreated;
  const _CreateMenu({required this.onCreated, this.onChannelCreated});

  @override
  Widget build(BuildContext context) {
    final dark    = Theme.of(context).brightness == Brightness.dark;
    final surface = dark ? const Color(0xFF13131A) : Colors.white;

    return Container(
      decoration: BoxDecoration(
        color: surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        border: Border.all(color: Colors.white.withOpacity(0.06)),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 36, height: 4,
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.2),
            borderRadius: BorderRadius.circular(99))),
        const SizedBox(height: 20),
        _item(context, '💬', 'Новый чат', 'Личное сообщение',
          () { Navigator.pop(context); _newChat(context); }),
        _item(context, '👥', 'Создать группу', 'Чат для нескольких',
          () { Navigator.pop(context); _createGroup(context); }),
        _item(context, '📢', 'Создать канал', 'Вещание для подписчиков',
          () { Navigator.pop(context); _createChannel(context); }),
        const SizedBox(height: 8),
      ]),
    );
  }

  Widget _item(BuildContext ctx, String emoji, String title,
      String sub, VoidCallback fn) =>
      InkWell(
        onTap: fn,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
          child: Row(children: [
            Container(
              width: 42, height: 42,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                color: const Color(0xFF7C6FFF).withOpacity(0.15)),
              child: Center(child: Text(emoji, style: const TextStyle(fontSize: 20))),
            ),
            const SizedBox(width: 12),
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: const TextStyle(fontFamily: 'DM Sans',
                fontSize: 14, fontWeight: FontWeight.w500, color: Color(0xFFF0F0F5))),
              Text(sub, style: const TextStyle(fontFamily: 'DM Sans',
                fontSize: 12, color: Color(0xFF8B8B9E))),
            ]),
          ]),
        ),
      );

  Future<void> _newChat(BuildContext context) async {
    final ctrl = TextEditingController();
    await showDialog(context: context, builder: (_) => AlertDialog(
      backgroundColor: const Color(0xFF13131A),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: const Text('Новый чат', style: TextStyle(
        fontFamily: 'Syne', fontWeight: FontWeight.w800, color: Colors.white)),
      content: TextField(controller: ctrl,
        style: const TextStyle(fontFamily: 'DM Sans', color: Colors.white),
        decoration: const InputDecoration(hintText: 'Email пользователя')),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context),
          child: const Text('Отмена', style: TextStyle(color: Color(0xFF8B8B9E)))),
        ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF7C6FFF)),
          onPressed: () { Navigator.pop(context); onCreated(); },
          child: const Text('Найти')),
      ],
    ));
  }

  Future<void> _createGroup(BuildContext context) async {
    final nameCtrl   = TextEditingController();
    final emailCtrl  = TextEditingController();
    final List<Map>  addedUsers = [];
    String? errorText;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          backgroundColor: const Color(0xFF13131A),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text('Создать группу',
              style: TextStyle(fontFamily: 'Syne',
                  fontWeight: FontWeight.w800, color: Colors.white)),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              // Название
              TextField(
                controller: nameCtrl,
                style: const TextStyle(fontFamily: 'DM Sans', color: Colors.white),
                decoration: const InputDecoration(
                  hintText: 'Название группы',
                  hintStyle: TextStyle(color: Color(0xFF8B8B9E)),
                ),
              ),
              const SizedBox(height: 16),
              // Добавить участника по email
              Row(children: [
                Expanded(
                  child: TextField(
                    controller: emailCtrl,
                    style: const TextStyle(fontFamily: 'DM Sans', color: Colors.white),
                    decoration: InputDecoration(
                      hintText: 'Email участника',
                      hintStyle: const TextStyle(color: Color(0xFF8B8B9E)),
                      errorText: errorText,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.add_rounded, color: Color(0xFF7C6FFF)),
                  onPressed: () async {
                    final email = emailCtrl.text.trim();
                    if (email.isEmpty) return;
                    final snap = await FirebaseFirestore.instance
                        .collection('users')
                        .where('email', isEqualTo: email)
                        .limit(1)
                        .get();
                    if (snap.docs.isEmpty) {
                      setD(() => errorText = 'Пользователь не найден');
                      return;
                    }
                    final user = {...snap.docs.first.data(), 'id': snap.docs.first.id};
                    final uid  = FirebaseAuth.instance.currentUser!.uid;
                    if (user['id'] == uid) {
                      setD(() => errorText = 'Нельзя добавить себя');
                      return;
                    }
                    if (addedUsers.any((u) => u['id'] == user['id'])) {
                      setD(() => errorText = 'Уже добавлен');
                      return;
                    }
                    setD(() {
                      addedUsers.add(user);
                      errorText = null;
                      emailCtrl.clear();
                    });
                  },
                ),
              ]),
              // Список добавленных
              if (addedUsers.isNotEmpty) ...[
                const SizedBox(height: 12),
                ...addedUsers.map((u) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(children: [
                    CircleAvatar(
                      radius: 16,
                      backgroundColor: const Color(0xFF7C6FFF).withOpacity(0.2),
                      child: Text(
                        (u['username'] as String? ?? '?')[0].toUpperCase(),
                        style: const TextStyle(color: Color(0xFF7C6FFF),
                            fontFamily: 'Syne', fontSize: 13)),
                    ),
                    const SizedBox(width: 8),
                    Expanded(child: Text(
                      u['username'] as String? ?? u['email'] as String? ?? '',
                      style: const TextStyle(fontFamily: 'DM Sans',
                          color: Colors.white, fontSize: 13))),
                    IconButton(
                      icon: const Icon(Icons.close_rounded,
                          color: Color(0xFF8B8B9E), size: 18),
                      onPressed: () => setD(() => addedUsers.remove(u)),
                    ),
                  ]),
                )),
              ],
            ]),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Отмена',
                  style: TextStyle(color: Color(0xFF8B8B9E)))),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF7C6FFF)),
              onPressed: () async {
                final name = nameCtrl.text.trim();
                if (name.isEmpty) {
                  setD(() => errorText = 'Введи название');
                  return;
                }
                final me    = FirebaseAuth.instance.currentUser!;
                final meDoc = await FirebaseFirestore.instance
                    .collection('users').doc(me.uid).get();
                final myName = meDoc.data()?['displayName'] ??
                    meDoc.data()?['username'] ?? 'Я';

                final members  = [me.uid, ...addedUsers.map((u) => u['id'] as String)];
                final names    = <String, String>{me.uid: myName};
                for (final u in addedUsers) {
                  names[u['id'] as String] =
                      u['displayName'] as String? ?? u['username'] as String? ?? '?';
                }

                final doc = await FirebaseFirestore.instance
                    .collection('chats')
                    .add({
                  'name'       : name,
                  'type'       : 'group',
                  'ownerId'    : me.uid,
                  'members'    : members,
                  'names'      : names,
                  'createdAt'  : FieldValue.serverTimestamp(),
                  'updatedAt'  : FieldValue.serverTimestamp(),
                  'lastMessage': '',
                });

                Navigator.pop(ctx);
                onCreated();
                if (context.mounted && onChannelCreated != null) {
                  onChannelCreated!(doc.id);
                }
              },
              child: const Text('Создать',
                  style: TextStyle(color: Colors.white))),
          ],
        ),
      ),
    );
  }

  Future<void> _createChannel(BuildContext context) async {
    final nameCtrl = TextEditingController();
    final descCtrl = TextEditingController();

    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF13131A),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Новый канал',
            style: TextStyle(fontFamily: 'Syne',
                fontWeight: FontWeight.w800, color: Colors.white)),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(
            controller: nameCtrl,
            style: const TextStyle(fontFamily: 'DM Sans', color: Colors.white),
            decoration: const InputDecoration(
              hintText: 'Название канала',
              hintStyle: TextStyle(color: Color(0xFF8B8B9E)),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: descCtrl,
            style: const TextStyle(fontFamily: 'DM Sans', color: Colors.white),
            decoration: const InputDecoration(
              hintText: 'Описание (необязательно)',
              hintStyle: TextStyle(color: Color(0xFF8B8B9E)),
            ),
          ),
        ]),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Отмена',
                style: TextStyle(color: Color(0xFF8B8B9E)))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF7C6FFF)),
            onPressed: () async {
              final name = nameCtrl.text.trim();
              if (name.isEmpty) return;
              final uid = FirebaseAuth.instance.currentUser!.uid;
              final doc = await FirebaseFirestore.instance
                  .collection('chats')
                  .add({
                'name'       : name,
                'description': descCtrl.text.trim(),
                'type'       : 'channel',
                'ownerId'    : uid,
                'members'    : [uid],
                'createdAt'  : FieldValue.serverTimestamp(),
                'updatedAt'  : FieldValue.serverTimestamp(),
                'lastMessage': '',
              });
              Navigator.pop(ctx);
              onCreated();
              if (context.mounted && onChannelCreated != null) {
                onChannelCreated!(doc.id);
              }
            },
            child: const Text('Создать',
                style: TextStyle(color: Colors.white))),
        ],
      ),
    );
  }
}
