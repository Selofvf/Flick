import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:go_router/go_router.dart';
import 'app.dart';
import 'core/router.dart';

// Глобальный GoRouter для навигации из FCM
GoRouter? _router;
void setRouter(GoRouter router) => _router = router;

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
}

void _handleCallMessage(RemoteMessage message) {
  final data = message.data;
  if (data['type'] == 'call' && _router != null) {
    final chatId     = data['chatId']     ?? '';
    final callerName = data['callerName'] ?? 'Неизвестный';
    _router!.go('/incoming-call?chatId=$chatId&callerName=$callerName');
  }
}

Future<void> _initFcm() async {
  try {
    final messaging = FirebaseMessaging.instance;
    await messaging.requestPermission(
      alert: true, badge: true, sound: true,
    ).timeout(const Duration(seconds: 5));

    final token = await messaging.getToken()
        .timeout(const Duration(seconds: 10));
    final user = FirebaseAuth.instance.currentUser;
    if (token != null && user != null) {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .update({'fcmToken': token});
    }

    messaging.onTokenRefresh.listen((newToken) {
      final u = FirebaseAuth.instance.currentUser;
      if (u != null) {
        FirebaseFirestore.instance
            .collection('users')
            .doc(u.uid)
            .update({'fcmToken': newToken});
      }
    });
  } catch (_) {
    // FCM недоступен — продолжаем без него
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    systemNavigationBarColor: Colors.transparent,
    systemNavigationBarDividerColor: Colors.transparent,
  ));

  await Hive.initFlutter();
  await Hive.openBox('settings');
  await Hive.openBox('bt_messages');
  await Firebase.initializeApp();

  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

  // FCM инициализируем в фоне — не блокируем запуск
  _initFcm();

  // Приложение открыто — входящий звонок
  FirebaseMessaging.onMessage.listen(_handleCallMessage);

  // Приложение в фоне — пользователь нажал уведомление
  FirebaseMessaging.onMessageOpenedApp.listen(_handleCallMessage);

  runApp(const ProviderScope(child: FlickApp()));
}
