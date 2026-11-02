import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'app.dart';
import 'drive/drive_auth.dart';
import 'library/library_controller.dart';
import 'reader/car/car_player.dart';
import 'reader/tts/background_audio.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  final controller = LibraryController(auth: DriveAuth.forPlatform());
  // Android Auto connects to the media service, sometimes before any screen
  // is shown, so it starts with the app and can browse the library.
  if (!kIsWeb && Platform.isAndroid) {
    unawaited(BackgroundAudio.instance.start(car: CarPlayer(controller)));
  }
  runApp(ReaderApp(controller: controller));
}
