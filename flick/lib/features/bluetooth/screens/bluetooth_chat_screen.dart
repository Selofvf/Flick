import 'package:flutter/material.dart';

class BluetoothChatScreen extends StatelessWidget {
  final String deviceId;
  const BluetoothChatScreen({super.key, required this.deviceId});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0F),
      appBar: AppBar(title: const Text('Bluetooth чат')),
      body: const Center(child: Text('Bluetooth чат — скоро',
        style: TextStyle(color: Color(0xFF8B8B9E)))),
    );
  }
}