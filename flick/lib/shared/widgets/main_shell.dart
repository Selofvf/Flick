import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class MainShell extends StatelessWidget {
  final Widget child;
  const MainShell({super.key, required this.child});

  static const _tabs = ['/bluetooth', '/home', '/settings'];

  void _showCreateMenu(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => _CreateMenu(
        onCreated: () {
          context.go('/home');
        },
        onChannelCreated: (chatId) {
          context.push('/chat/$chatId');
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final loc = GoRouterState.of(context).matchedLocation;
    final idx = _tabs.indexWhere((t) => loc.startsWith(t));
    final activeIdx = idx < 0 ? 1 : idx;
    final dark = Theme.of(context).brightness == Brightness.dark;

    final bgColor = dark ? const Color(0xFF1C1C1E) : const Color(0xFFF2F2F7);
    final activeColor = const Color(0xFF5B8EFF);
    final inactiveColor = dark ? Colors.white70 : Colors.black54;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: child,
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: Row(
            children: [
              Expanded(
                child: Container(
                  height: 68,
                  decoration: BoxDecoration(
                    color: bgColor,
                    borderRadius: BorderRadius.circular(34),
                  ),
                  child: Row(
                    children: [
                      _NavItem(
                        icon: Icons.bluetooth_rounded,
                        label: 'Bluetooth',
                        isActive: activeIdx == 0,
                        activeColor: activeColor,
                        inactiveColor: inactiveColor,
                        onTap: () => context.go(_tabs[0]),
                      ),
                      _NavItem(
                        icon: Icons.chat_bubble_rounded,
                        label: 'Чаты',
                        isActive: activeIdx == 1,
                        activeColor: activeColor,
                        inactiveColor: inactiveColor,
                        onTap: () => context.go(_tabs[1]),
                      ),
                      _NavItem(
                        icon: Icons.settings_rounded,
                        label: 'Настройки',
                        isActive: activeIdx == 2,
                        activeColor: activeColor,
                        inactiveColor: inactiveColor,
                        onTap: () => context.go(_tabs[2]),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 10),
              // Кнопка +
              GestureDetector(
                onTap: () => _showCreateMenu(context),
                child: Container(
                  width: 68,
                  height: 68,
                  decoration: BoxDecoration(
                    color: bgColor,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.add_rounded,
                    color: inactiveColor,
                    size: 28,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Навигационный элемент ─────────────────────────────────────────────────────

class _NavItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isActive;
  final Color activeColor;
  final Color inactiveColor;
  final VoidCallback onTap;

  const _NavItem({
    required this.icon,
    required this.label,
    required this.isActive,
    required this.activeColor,
    required this.inactiveColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          margin: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: isActive
                ? Colors.black.withOpacity(0.25)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(28),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon,
                  color: isActive ? activeColor : inactiveColor, size: 24),
              const SizedBox(height: 3),
              Text(
                label,
                style: TextStyle(
                  color: isActive ? activeColor : inactiveColor,
                  fontSize: 11,
                  fontWeight:
                      isActive ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Меню создания ─────────────────────────────────────────────────────────────

class _CreateMenu extends StatelessWidget {
  final VoidCallback onCreated;
  final void Function(String chatId)? onChannelCreated;
  const _CreateMenu({required this.onCreated, this.onChannelCreated});

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final surface = dark ? const Color(0xFF13131A) : Colors.white;

    return Container(
      decoration: BoxDecoration(
        color: surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        border: Border.all(color: Colors.white.withOpacity(0.06)),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(
          width: 36,
          height: 4,
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.2),
            borderRadius: BorderRadius.circular(99),
          ),
        ),
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
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                color: const Color(0xFF7C6FFF).withOpacity(0.15),
              ),
              child:
                  Center(child: Text(emoji, style: const TextStyle(fontSize: 20))),
            ),
            const SizedBox(width: 12),
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title,
                  style: const TextStyle(
                      fontFamily: 'DM Sans',
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: Color(0xFFF0F0F5))),
              Text(sub,
                  style: const TextStyle(
                      fontFamily: 'DM Sans',
                      fontSize: 12,
                      color: Color(0xFF8B8B9E))),
            ]),
          ]),
        ),
      );

  Future<void> _newChat(BuildContext context) async {
    final ctrl = TextEditingController();
    String? errorText;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          backgroundColor: const Color(0xFF13131A),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text('Новый чат',
              style: TextStyle(
                  fontFamily: 'Syne',
                  fontWeight: FontWeight.w800,
                  color: Colors.white)),
          content: TextField(
            controller: ctrl,
            style:
                const TextStyle(fontFamily: 'DM Sans', color: Colors.white),
            decoration: InputDecoration(
              hintText: 'Email пользователя',
              hintStyle: const TextStyle(color: Color(0xFF8B8B9E)),
              errorText: errorText,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Отмена',
                  style: TextStyle(color: Color(0xFF8B8B9E))),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF7C6FFF)),
              onPressed: () async {
                final email = ctrl.text.trim();
                if (email.isEmpty) return;

                // Ищем пользователя по email в Firestore
                final snap = await FirebaseFirestore.instance
                    .collection('users')
                    .where('email', isEqualTo: email)
                    .limit(1)
                    .get();

                if (snap.docs.isEmpty) {
                  setState(() => errorText = 'Пользователь не найден');
                  return;
                }

                final me = FirebaseAuth.instance.currentUser!;
                final other = snap.docs.first;
                final otherId = other.id;

                // Создаём или находим существующий чат
                final chatSnap = await FirebaseFirestore.instance
                    .collection('chats')
                    .where('members', arrayContains: me.uid)
                    .get();

                String? existingChatId;
                for (final doc in chatSnap.docs) {
                  final members =
                      List<String>.from(doc.data()['members'] ?? []);
                  if (members.contains(otherId) && members.length == 2) {
                    existingChatId = doc.id;
                    break;
                  }
                }

                if (existingChatId != null) {
                  Navigator.pop(ctx);
                  onCreated();
                  // Переходим в существующий чат
                  if (context.mounted) {
                    Navigator.of(context, rootNavigator: true)
                        .pushNamed('/chat/$existingChatId');
                  }
                  return;
                }

                // Получаем имена обоих участников
                final myDoc     = await FirebaseFirestore.instance.collection('users').doc(me.uid).get();
                final myName    = myDoc.data()?['displayName'] ?? myDoc.data()?['username'] ?? 'Неизвестный';
                final otherName = other.data()['displayName'] ?? other.data()['username'] ?? 'Неизвестный';

                // Создаём новый чат
                final newChat = await FirebaseFirestore.instance
                    .collection('chats')
                    .add({
                  'members'    : [me.uid, otherId],
                  'type'       : 'direct',
                  'createdAt'  : FieldValue.serverTimestamp(),
                  'updatedAt'  : FieldValue.serverTimestamp(),
                  'lastMessage': '',
                  'names'      : {me.uid: myName, otherId: otherName},
                });

                Navigator.pop(ctx);
                onCreated();
                if (context.mounted) {
                  Navigator.of(context, rootNavigator: true)
                      .pushNamed('/chat/${newChat.id}');
                }
              },
              child:
                  const Text('Найти', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _createGroup(BuildContext context) async {
    final nameCtrl  = TextEditingController();
    final emailCtrl = TextEditingController();
    final List<Map> addedUsers = [];
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
              TextField(
                controller: nameCtrl,
                style: const TextStyle(fontFamily: 'DM Sans', color: Colors.white),
                decoration: const InputDecoration(
                  hintText: 'Название группы',
                  hintStyle: TextStyle(color: Color(0xFF8B8B9E)),
                ),
              ),
              const SizedBox(height: 16),
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
                if (name.isEmpty) return;
                final me    = FirebaseAuth.instance.currentUser!;
                final meDoc = await FirebaseFirestore.instance
                    .collection('users').doc(me.uid).get();
                final myName = meDoc.data()?['displayName'] ??
                    meDoc.data()?['username'] ?? 'Я';

                final members = [me.uid, ...addedUsers.map((u) => u['id'] as String)];
                final names   = <String, String>{me.uid: myName};
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
