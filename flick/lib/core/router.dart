import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../features/auth/screens/splash_screen.dart';
import '../features/auth/screens/login_screen.dart';
import '../features/chat/screens/chats_list_screen.dart';
import '../features/chat/screens/chat_screen.dart';
import '../features/bluetooth/screens/bluetooth_scan_screen.dart';
import '../features/bluetooth/screens/bluetooth_chat_screen.dart';
import '../features/stories/screens/story_viewer_screen.dart';
import '../features/settings/screens/settings_screen.dart';
import '../features/call/screens/incoming_call_screen.dart';
import '../shared/widgets/main_shell.dart';
import '../features/search/screens/search_screen.dart';
import '../features/chat/screens/channel_edit_screen.dart';
import '../features/profile/screens/user_profile_screen.dart';

final routerProvider = Provider<GoRouter>((ref) {
  final router = GoRouter(
    initialLocation: '/',
    redirect: (ctx, state) {
      final isAuth   = FirebaseAuth.instance.currentUser != null;
      final loc      = state.matchedLocation;
      final isLogin  = loc == '/login';
      final isSplash = loc == '/';
      if (isSplash) return null;
      if (!isAuth && !isLogin) return '/login';
      if (isAuth  &&  isLogin) return '/home';
      return null;
    },
    routes: [
      GoRoute(path: '/',      builder: (_, __) => const SplashScreen()),
      GoRoute(path: '/login', builder: (_, __) => const LoginScreen()),
      ShellRoute(
        builder: (ctx, state, child) => MainShell(child: child),
        routes: [
          GoRoute(path: '/home',      builder: (_, __) => const ChatsListScreen()),
          GoRoute(path: '/bluetooth', builder: (_, __) => const BluetoothScanScreen()),
          GoRoute(path: '/settings',  builder: (_, __) => const SettingsScreen()),
        ],
      ),
      GoRoute(
        path: '/channel-edit/:id',
        builder: (_, state) => ChannelEditScreen(
            chatId: state.pathParameters['id']!),
      ),
      GoRoute(
        path: '/search',
        builder: (_, __) => const SearchScreen(),
      ),
      GoRoute(
        path: '/profile/:userId',
        builder: (_, state) => UserProfileScreen(
            userId: state.pathParameters['userId']!),
      ),
      GoRoute(
        path: '/chat/:id',
        builder: (_, state) => ChatScreen(chatId: state.pathParameters['id']!),
      ),
      GoRoute(
        path: '/bluetooth/chat/:deviceId',
        builder: (_, state) => BluetoothChatScreen(
          deviceId: state.pathParameters['deviceId']!),
      ),
      GoRoute(
        path: '/stories/:userId',
        builder: (_, state) => StoryViewerScreen(
          userId: state.pathParameters['userId']!),
      ),
      // ── Входящий звонок ─────────────────────────────────────────────────
      GoRoute(
        path: '/incoming-call',
        builder: (_, state) {
          final chatId     = state.uri.queryParameters['chatId'] ?? '';
          final callerName = state.uri.queryParameters['callerName'] ?? 'Неизвестный';
          return IncomingCallScreen(chatId: chatId, callerName: callerName);
        },
      ),
    ],
  );
  return router;
});
