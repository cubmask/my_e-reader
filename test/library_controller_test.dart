import 'package:ebook_reader/library/library_controller.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parses Drive folder links and bare ids', () {
    expect(
      parseFolderId(
        'https://drive.google.com/drive/folders/1AbC_def-GHIjklMNop?usp=sharing',
      ),
      '1AbC_def-GHIjklMNop',
    );
    expect(parseFolderId(' 1AbC_def-GHIjklMNop '), '1AbC_def-GHIjklMNop');
    expect(parseFolderId('not a folder'), isNull);
  });
}
