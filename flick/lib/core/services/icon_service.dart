import 'package:flutter/services.dart';

class IconService {
  static const _channel = MethodChannel('com.example.flick/icon');

  /// key: 'default' | 'green' | 'pink' | 'orange' | 'blue'
  static Future<void> setIcon(String key) async {
    try {
      await _channel.invokeMethod('setIcon', {'icon': key});
    } catch (e) {
      // на iOS или в дебаге может не работать — игнорируем
    }
  }
}
