import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:go_router/go_router.dart';

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

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen>
    with SingleTickerProviderStateMixin {
  final _ctrl = TextEditingController();
  final _db   = FirebaseFirestore.instance;
  final _me   = FirebaseAuth.instance.currentUser!;

  late final TabController _tabs;

  List<Map> _users    = [];
  List<Map> _groups   = [];
  List<Map> _channels = [];

  bool _loading = false;
  String _query = '';
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 4, vsync: this, initialIndex: 0);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _tabs.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _onChanged(String v) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      setState(() => _query = v.trim());
      if (_query.isNotEmpty) _search(_query);
      else setState(() { _users = []; _groups = []; _channels = []; });
    });
  }

  Future<void> _search(String q) async {
    setState(() => _loading = true);
    final lower = q.toLowerCase();

    // Загружаем всех пользователей и фильтруем локально
    // (Firestore не поддерживает поиск по подстроке)
    final userSnap = await _db.collection('users').limit(200).get();

    final users = userSnap.docs
        .map((d) => {...d.data(), 'id': d.id})
        .where((u) => u['id'] != _me.uid)
        .where((u) {
          final username = (u['username'] as String? ?? '').toLowerCase();
          final display  = (u['displayName'] as String? ?? '').toLowerCase();
          final email    = (u['email'] as String? ?? '').toLowerCase();
          return username.contains(lower) ||
                 display.contains(lower)  ||
                 email.contains(lower);
        })
        .toList();

    // Группы и каналы — тоже локальная фильтрация
    final chatSnap = await _db
        .collection('chats')
        .where('type', whereIn: ['group', 'channel'])
        .limit(200)
        .get();

    final groups   = <Map>[];
    final channels = <Map>[];
    for (final d in chatSnap.docs) {
      final data = {...d.data(), 'id': d.id};
      final name = (data['name'] as String? ?? '').toLowerCase();
      if (!name.contains(lower)) continue;
      if (data['type'] == 'group') groups.add(data);
      else channels.add(data);
    }

    setState(() {
      _users    = users.cast<Map>();
      _groups   = groups;
      _channels = channels;
      _loading  = false;
    });
  }

  // Открыть или создать чат с пользователем
  Future<void> _openUserChat(Map user) async {
    final otherId = user['id'] as String;

    final snap = await _db
        .collection('chats')
        .where('members', arrayContains: _me.uid)
        .where('type', isEqualTo: 'direct')
        .get();

    String? chatId;
    for (final d in snap.docs) {
      final m = List<String>.from(d.data()['members'] ?? []);
      if (m.contains(otherId) && m.length == 2) {
        chatId = d.id;
        break;
      }
    }

    // Получаем имя собеседника и своё имя для поля names
    final myDoc    = await _db.collection('users').doc(_me.uid).get();
    final myName   = myDoc.data()?['displayName'] ?? myDoc.data()?['username'] ?? 'Неизвестный';
    final otherDoc = await _db.collection('users').doc(otherId).get();
    final otherName= otherDoc.data()?['displayName'] ?? otherDoc.data()?['username'] ?? 'Неизвестный';

    chatId ??= (await _db.collection('chats').add({
      'members'     : [_me.uid, otherId],
      'type'        : 'direct',
      'createdAt'   : FieldValue.serverTimestamp(),
      'updatedAt'   : FieldValue.serverTimestamp(),
      'lastMessage' : '',
      'names'       : {_me.uid: myName, otherId: otherName},
    })).id;

    if (mounted) context.push('/chat/$chatId');
  }

  // Вступить / открыть группу или канал
  Future<void> _openChat(Map chat) async {
    final chatId  = chat['id'] as String;
    final members = List<String>.from(chat['members'] ?? []);

    if (!members.contains(_me.uid)) {
      await _db.collection('chats').doc(chatId).update({
        'members': FieldValue.arrayUnion([_me.uid]),
      });
    }
    if (mounted) context.push('/chat/$chatId');
  }

  @override
  Widget build(BuildContext context) {
    final dark    = Theme.of(context).brightness == Brightness.dark;
    final bg      = dark ? const Color(0xFF0A0A0F) : const Color(0xFFF5F5FA);
    final surface = dark ? const Color(0xFF13131A) : Colors.white;
    final muted   = dark ? const Color(0xFF8B8B9E) : const Color(0xFF9CA3AF);
    final accent  = const Color(0xFF7C6FFF);

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        backgroundColor: surface,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
          onPressed: () => context.pop(),
        ),
        title: TextField(
          controller: _ctrl,
          autofocus: true,
          onChanged: _onChanged,
          style: TextStyle(
            fontFamily: 'DM Sans',
            fontSize: 16,
            color: dark ? Colors.white : Colors.black87,
          ),
          decoration: InputDecoration(
            hintText: 'Поиск людей, групп, каналов...',
            hintStyle: TextStyle(fontFamily: 'DM Sans', color: muted, fontSize: 15),
            border: InputBorder.none,
            suffixIcon: _query.isNotEmpty
                ? IconButton(
                    icon: Icon(Icons.close_rounded, color: muted, size: 20),
                    onPressed: () {
                      _ctrl.clear();
                      setState(() {
                        _query = '';
                        _users = []; _groups = []; _channels = [];
                      });
                    },
                  )
                : null,
          ),
        ),
        bottom: TabBar(
          controller: _tabs,
          labelColor: accent,
          unselectedLabelColor: muted,
          indicatorColor: accent,
          indicatorSize: TabBarIndicatorSize.label,
          labelStyle: const TextStyle(fontFamily: 'DM Sans', fontWeight: FontWeight.w600, fontSize: 13),
          tabs: [
            Tab(text: 'Все (${_users.length + _groups.length + _channels.length})'),
            Tab(text: 'Люди (${_users.length})'),
            Tab(text: 'Группы (${_groups.length})'),
            Tab(text: 'Каналы (${_channels.length})'),
          ],
        ),
      ),
      body: _query.isEmpty
          ? _emptyState(muted)
          : _loading
              ? const Center(child: CircularProgressIndicator(color: Color(0xFF7C6FFF)))
              : TabBarView(
                  controller: _tabs,
                  children: [
                    // Все
                    _allResults(dark, surface, muted, accent),
                    // Люди
                    _userList(_users, dark, surface, muted, accent),
                    // Группы
                    _chatList(_groups, dark, surface, muted, accent),
                    // Каналы
                    _chatList(_channels, dark, surface, muted, accent),
                  ],
                ),
    );
  }

  Widget _emptyState(Color muted) => Center(
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      Icon(Icons.search_rounded, size: 64, color: muted.withOpacity(0.4)),
      const SizedBox(height: 16),
      Text('Начните вводить запрос',
          style: TextStyle(fontFamily: 'DM Sans', fontSize: 15, color: muted)),
    ]),
  );

  Widget _noResults(Color muted) => Center(
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      Icon(Icons.sentiment_dissatisfied_rounded, size: 56, color: muted.withOpacity(0.4)),
      const SizedBox(height: 12),
      Text('Ничего не найдено по «$_query»',
          style: TextStyle(fontFamily: 'DM Sans', fontSize: 15, color: muted)),
    ]),
  );

  Widget _allResults(bool dark, Color surface, Color muted, Color accent) {
    final all = _users.length + _groups.length + _channels.length;
    if (all == 0) return _noResults(muted);
    return ListView(children: [
      if (_users.isNotEmpty) ...[
        _sectionHeader('Люди', muted),
        ..._users.map((u) => _userTile(u, dark, surface, muted, accent)),
      ],
      if (_groups.isNotEmpty) ...[
        _sectionHeader('Группы', muted),
        ..._groups.map((g) => _chatTile(g, dark, surface, muted, accent)),
      ],
      if (_channels.isNotEmpty) ...[
        _sectionHeader('Каналы', muted),
        ..._channels.map((c) => _chatTile(c, dark, surface, muted, accent)),
      ],
      const SizedBox(height: 20),
    ]);
  }

  Widget _userList(List<Map> list, bool dark, Color surface, Color muted, Color accent) {
    if (list.isEmpty) return _noResults(muted);
    return ListView(children: [
      ...list.map((u) => _userTile(u, dark, surface, muted, accent)),
      const SizedBox(height: 20),
    ]);
  }

  Widget _chatList(List<Map> list, bool dark, Color surface, Color muted, Color accent) {
    if (list.isEmpty) return _noResults(muted);
    return ListView(children: [
      ...list.map((c) => _chatTile(c, dark, surface, muted, accent)),
      const SizedBox(height: 20),
    ]);
  }

  Widget _sectionHeader(String title, Color muted) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 20, 16, 6),
    child: Text(title.toUpperCase(),
        style: TextStyle(
            fontFamily: 'DM Sans', fontSize: 11,
            fontWeight: FontWeight.w600, color: muted,
            letterSpacing: 0.8)),
  );

  Widget _userTile(Map user, bool dark, Color surface, Color muted, Color accent) {
    final name     = user['username'] as String? ?? 'Без имени';
    final email    = user['email']    as String? ?? '';
    final avatarUrl= user['avatarUrl']as String? ?? '';

    return InkWell(
      onTap: () => _openUserChat(user),
      borderRadius: BorderRadius.circular(16),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: surface,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(children: [
          _avatar(name, avatarUrl, null, accent),
          const SizedBox(width: 12),
          Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start, children: [
              _highlighted(name, _query, dark),
              if (email.isNotEmpty)
                Text(email, style: TextStyle(fontFamily: 'DM Sans', fontSize: 12, color: muted),
                    overflow: TextOverflow.ellipsis),
            ],
          )),
          Icon(Icons.arrow_forward_ios_rounded, size: 14, color: muted),
        ]),
      ),
    );
  }

  Widget _chatTile(Map chat, bool dark, Color surface, Color muted, Color accent) {
    final name       = chat['name']       as String? ?? 'Без названия';
    final type       = chat['type']       as String? ?? 'group';
    final members    = List.from(chat['members'] ?? []);
    final avatarUrl  = chat['avatarUrl']  as String? ?? '';
    final bannerIdx  = (chat['bannerIdx'] ?? 0) as int;
    final isMember   = members.contains(_me.uid);
    final icon       = type == 'group' ? Icons.group_rounded : Icons.campaign_rounded;
    final colors     = _bannerPresets[bannerIdx.clamp(0, _bannerPresets.length - 1)];

    return InkWell(
      onTap: () => _openChat(chat),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: LinearGradient(
            colors: colors,
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(children: [
            // Аватарка
            Container(
              width: 48, height: 48,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withOpacity(0.2),
              ),
              child: ClipOval(
                child: avatarUrl.isNotEmpty
                    ? Image.network(avatarUrl, fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) =>
                            Icon(icon, color: Colors.white, size: 24))
                    : Icon(icon, color: Colors.white, size: 24),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(name,
                    style: const TextStyle(fontFamily: 'DM Sans', fontSize: 14,
                        fontWeight: FontWeight.w600, color: Colors.white),
                    overflow: TextOverflow.ellipsis),
                Text('${type == 'group' ? 'Группа' : 'Канал'} · ${members.length} участников',
                    style: TextStyle(fontFamily: 'DM Sans', fontSize: 12,
                        color: Colors.white.withOpacity(0.75))),
              ],
            )),
            if (isMember)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.25),
                  borderRadius: BorderRadius.circular(99),
                ),
                child: const Text('Вы в чате',
                    style: TextStyle(fontFamily: 'DM Sans', fontSize: 11,
                        color: Colors.white, fontWeight: FontWeight.w600)),
              )
            else
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.25),
                  borderRadius: BorderRadius.circular(99),
                ),
                child: const Text('Вступить',
                    style: TextStyle(fontFamily: 'DM Sans', fontSize: 11,
                        color: Colors.white, fontWeight: FontWeight.w600)),
              ),
          ]),
        ),
      ),
    );
  }

  // Аватарка для каналов/групп с градиентом
  Widget _chatAvatar(String name, String url, IconData icon, List<Color> colors) {
    return Container(
      width: 48, height: 48,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          colors: colors,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: ClipOval(
        child: url.isNotEmpty
            ? Image.network(url, fit: BoxFit.cover,
                errorBuilder: (_, __, ___) =>
                    Icon(icon, color: Colors.white, size: 22))
            : Icon(icon, color: Colors.white, size: 22),
      ),
    );
  }

  Widget _avatar(String name, String url, IconData? icon, Color accent) {
    if (url.isNotEmpty) {
      return CircleAvatar(radius: 24, backgroundImage: NetworkImage(url));
    }
    return CircleAvatar(
      radius: 24,
      backgroundColor: accent.withOpacity(0.2),
      child: icon != null
          ? Icon(icon, color: accent, size: 22)
          : Text(name.isNotEmpty ? name[0].toUpperCase() : '?',
              style: TextStyle(fontFamily: 'Syne',
                  fontWeight: FontWeight.w700, color: accent, fontSize: 18)),
    );
  }

  // Подсвечивает совпадение в тексте
  Widget _highlighted(String text, String query, bool dark) {
    if (query.isEmpty) {
      return Text(text, style: TextStyle(
          fontFamily: 'DM Sans', fontSize: 14,
          fontWeight: FontWeight.w500,
          color: dark ? Colors.white : Colors.black87));
    }
    final lower = text.toLowerCase();
    final idx   = lower.indexOf(query.toLowerCase());
    if (idx < 0) {
      return Text(text, style: TextStyle(
          fontFamily: 'DM Sans', fontSize: 14,
          fontWeight: FontWeight.w500,
          color: dark ? Colors.white : Colors.black87));
    }
    return RichText(text: TextSpan(children: [
      if (idx > 0)
        TextSpan(text: text.substring(0, idx),
            style: TextStyle(fontFamily: 'DM Sans', fontSize: 14,
                fontWeight: FontWeight.w500,
                color: dark ? Colors.white : Colors.black87)),
      TextSpan(
        text: text.substring(idx, idx + query.length),
        style: const TextStyle(fontFamily: 'DM Sans', fontSize: 14,
            fontWeight: FontWeight.w700, color: Color(0xFF7C6FFF)),
      ),
      if (idx + query.length < text.length)
        TextSpan(text: text.substring(idx + query.length),
            style: TextStyle(fontFamily: 'DM Sans', fontSize: 14,
                fontWeight: FontWeight.w500,
                color: dark ? Colors.white : Colors.black87)),
    ]));
  }
}
