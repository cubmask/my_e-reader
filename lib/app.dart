import 'package:flutter/material.dart';

import 'library/library_controller.dart';
import 'ui/home_shell.dart';
import 'ui/theme.dart';

class ReaderApp extends StatelessWidget {
  const ReaderApp({super.key, required this.controller});

  final LibraryController controller;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'My E-Reader',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(Brightness.light),
      darkTheme: buildAppTheme(Brightness.dark),
      home: HomeShell(controller: controller),
    );
  }
}
