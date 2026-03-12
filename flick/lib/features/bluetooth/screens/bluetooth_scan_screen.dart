import 'package:flutter/material.dart';

class BluetoothScanScreen extends StatelessWidget {
  const BluetoothScanScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0F),
      appBar: AppBar(title: const Text('Bluetooth')),
      body: const Center(child: Text('Bluetooth — скоро',
        style: TextStyle(color: Color(0xFF8B8B9E)))),
    );
  }
}