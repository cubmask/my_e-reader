import 'package:flutter/material.dart';

import 'library/library_controller.dart';
import 'ui/home_shell.dart';

class ReaderApp extends StatelessWidget {
  const ReaderApp({super.key, required this.controller});

  final LibraryController controller;

  @override
  Widget build(BuildContext context) {
    const seed = Color(0xFF6B4E31);
    return MaterialApp(
      title: 'Ebook Reader',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(colorSchemeSeed: seed),
      darkTheme: ThemeData(colorSchemeSeed: seed, brightness: Brightness.dark),
      home: HomeShell(controller: controller),
    );
  }
}
