import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
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

class UserProfileScreen extends StatefulWidget {
  final String userId;
  const UserProfileScreen({super.key, required this.userId});
  @override State<UserProfileScreen> createState() => _UserProfileScreenState();
}

class _UserProfileScreenState extends State<UserProfileScreen> {
  final _db   = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;

  String  _username    = '';
  String  _email       = '';
  String? _avatarUrl;
  int     _bannerIdx   = 0;
  bool    _loading     = true;
  bool    _hideEmail   = false;
  bool    _hideAvatar  = false;
  bool    _hideGifts   = false;
  bool    _hideStories = false;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    final doc  = await _db.collection('users').doc(widget.userId).get();
    final data = doc.data();
    final privacy = data?['privacy'] as Map<String, dynamic>? ?? {};
    setState(() {
      _username    = data?['username']   ?? data?['displayName'] ?? 'Пользователь';
      _email       = data?['email']      ?? '';
      _avatarUrl   = data?['avatarUrl'];
      _bannerIdx   = (data?['bannerIdx'] ?? 0) as int;
      _hideEmail   = privacy['hideEmail']   == true;
      _hideAvatar  = privacy['hideAvatar']  == true;
      _hideGifts   = privacy['hideGifts']   == true;
      _hideStories = privacy['hideStories'] == true;
      _loading     = false;
    });
  }

  Future<void> _openChat() async {
    final me = _auth.currentUser;
    if (me == null) return;

    // Ищем существующий direct чат
    final snap = await _db.collection('chats')
        .where('type', isEqualTo: 'direct')
        .where('members', arrayContains: me.uid)
        .get();

    String? chatId;
    for (final doc in snap.docs) {
      final members = List<String>.from(doc['members'] ?? []);
      if (members.contains(widget.userId)) {
        chatId = doc.id;
        break;
      }
    }

    // Создаём если не нашли
    if (chatId == null) {
      final meDoc  = await _db.collection('users').doc(me.uid).get();
      final myName = meDoc.data()?['displayName'] ?? meDoc.data()?['username'] ?? 'Я';
      final doc = await _db.collection('chats').add({
        'type'       : 'direct',
        'members'    : [me.uid, widget.userId],
        'names'      : {me.uid: myName, widget.userId: _username},
        'createdAt'  : FieldValue.serverTimestamp(),
        'updatedAt'  : FieldValue.serverTimestamp(),
        'lastMessage': '',
      });
      chatId = doc.id;
    }

    if (mounted) context.push('/chat/$chatId');
  }

  @override
  Widget build(BuildContext context) {
    final dark    = Theme.of(context).brightness == Brightness.dark;
    final bg      = dark ? const Color(0xFF0A0A0F) : const Color(0xFFF0F2F8);
    final surface = dark ? const Color(0xFF1C1C27) : Colors.white;
    final colors  = _bannerPresets[_bannerIdx.clamp(0, 7)];
    final isMe    = _auth.currentUser?.uid == widget.userId;

    return Scaffold(
      backgroundColor: bg,
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF7C6FFF)))
          : CustomScrollView(
              slivers: [
                // ── Баннер + аватарка ──────────────────────────────────────
                SliverAppBar(
                  expandedHeight: 260,
                  pinned: true,
                  backgroundColor: surface,
                  leading: IconButton(
                    icon: const Icon(Icons.arrow_back_rounded),
                    onPressed: () => Navigator.pop(context),
                  ),
                  flexibleSpace: FlexibleSpaceBar(
                    collapseMode: CollapseMode.pin,
                    background: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        // Баннер
                        Container(
                          height: 180,
                          width: double.infinity,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: colors,
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                          ),
                        ),
                        // Аватарка
                        Positioned(
                          top: 120,
                          left: 24,
                          child: Container(
                            width: 90, height: 90,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(
                                  color: dark ? const Color(0xFF0A0A0F) : Colors.white,
                                  width: 4),
                              gradient: LinearGradient(
                                colors: colors,
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                            ),
                            child: ClipOval(
                              child: (!isMe && _hideAvatar)
                                  ? _defaultAvatar()
                                  : _avatarUrl != null
                                      ? Image.network(_avatarUrl!,
                                          fit: BoxFit.cover,
                                          errorBuilder: (_, __, ___) => _defaultAvatar())
                                      : _defaultAvatar(),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                // ── Имя и email ────────────────────────────────────────────
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(_username,
                          style: TextStyle(
                            fontFamily: 'Syne', fontSize: 24,
                            fontWeight: FontWeight.w800,
                            color: dark ? Colors.white : const Color(0xFF0F0F1A))),
                        if (_email.isNotEmpty && (!_hideEmail || isMe)) ...[
                          const SizedBox(height: 4),
                          Text(_email,
                            style: const TextStyle(
                              fontFamily: 'DM Sans', fontSize: 14,
                              color: Color(0xFF8B8B9E))),
                        ],
                        const SizedBox(height: 24),

                        // ── Кнопки действий ───────────────────────────────
                        if (!isMe) ...[
                          _actionBtn(
                            icon: Icons.chat_bubble_rounded,
                            label: 'Написать сообщение',
                            colors: colors,
                            onTap: _openChat,
                          ),
                          const SizedBox(height: 12),
                        ],

                        // ── Информация ─────────────────────────────────────
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: surface,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: Colors.white.withOpacity(0.06)),
                          ),
                          child: Column(children: [
                            _infoRow(Icons.person_rounded, 'Имя пользователя',
                                '@$_username', dark),
                            if (_email.isNotEmpty && (!_hideEmail || isMe)) ...[
                              Divider(color: Colors.white.withOpacity(0.06), height: 24),
                              _infoRow(Icons.email_rounded, 'Email',
                                  _email, dark),
                            ],
                            if (!isMe && _hideEmail && _email.isNotEmpty) ...[
                              Divider(color: Colors.white.withOpacity(0.06), height: 24),
                              _infoRow(Icons.lock_rounded, 'Email', 'Скрыто', dark,
                                  muted: true),
                            ],
                          ]),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _defaultAvatar() => Center(
    child: Text(
      _username.isNotEmpty ? _username[0].toUpperCase() : '?',
      style: const TextStyle(fontFamily: 'Syne', fontSize: 36,
          fontWeight: FontWeight.w800, color: Colors.white),
    ),
  );

  Widget _actionBtn({
    required IconData icon,
    required String label,
    required List<Color> colors,
    required VoidCallback onTap,
  }) =>
    GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          gradient: LinearGradient(
            colors: colors,
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          boxShadow: [BoxShadow(
            color: colors[0].withOpacity(0.4),
            blurRadius: 16, offset: const Offset(0, 4))],
        ),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(icon, color: Colors.white, size: 20),
          const SizedBox(width: 10),
          Text(label, style: const TextStyle(fontFamily: 'DM Sans',
              fontSize: 15, fontWeight: FontWeight.w600, color: Colors.white)),
        ]),
      ),
    );

  Widget _infoRow(IconData icon, String label, String value, bool dark,
      {bool muted = false}) =>
    Row(children: [
      Container(
        width: 36, height: 36,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: (muted ? const Color(0xFF8B8B9E) : const Color(0xFF7C6FFF)).withOpacity(0.1),
        ),
        child: Icon(icon,
            color: muted ? const Color(0xFF8B8B9E) : const Color(0xFF7C6FFF),
            size: 18),
      ),
      const SizedBox(width: 12),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: const TextStyle(fontFamily: 'DM Sans',
            fontSize: 11, color: Color(0xFF8B8B9E))),
        Text(value, style: TextStyle(fontFamily: 'DM Sans', fontSize: 14,
            fontWeight: FontWeight.w500,
            fontStyle: muted ? FontStyle.italic : FontStyle.normal,
            color: muted
                ? const Color(0xFF8B8B9E)
                : (dark ? Colors.white : const Color(0xFF0F0F1A)))),
      ])),
    ]);
}
