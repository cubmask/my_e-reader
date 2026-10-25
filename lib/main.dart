import 'package:flutter/material.dart';

import 'app.dart';
import 'drive/drive_auth.dart';
import 'library/library_controller.dart';

void main() {
  runApp(
    ReaderApp(controller: LibraryController(auth: DriveAuth.forPlatform())),
  );
}
