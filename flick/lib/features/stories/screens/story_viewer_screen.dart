import 'package:flutter/material.dart';

class StoryViewerScreen extends StatelessWidget {
  final String userId;
  const StoryViewerScreen({super.key, required this.userId});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0F),
      appBar: AppBar(title: const Text('Stories')),
      body: const Center(child: Text('Stories — скоро',
        style: TextStyle(color: Color(0xFF8B8B9E)))),
    );
  }
}