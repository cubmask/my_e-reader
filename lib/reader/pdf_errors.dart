import 'dart:io';

import 'package:pdfrx/pdfrx.dart';

// PDFium's FPDF_ERR_* load error codes.
const _errFile = 2;
const _errFormat = 3;
const _errSecurity = 5;

/// Whether [file] starts like a PDF. PDFium accepts the `%PDF-` header
/// anywhere in the first kilobyte.
Future<bool> looksLikePdf(File file) async {
  try {
    final head = await file
        .openRead(0, 1024)
        .fold<List<int>>([], (all, chunk) => all..addAll(chunk));
    return String.fromCharCodes(head).contains('%PDF-');
  } catch (_) {
    return false;
  }
}

/// A message for the reader when a PDF will not open, in place of the
/// PDFium error. [isPdf] is false when the file does not even start like a
/// PDF, such as a renamed document or an HTML page saved as `.pdf`.
String pdfErrorMessage(Object error, {bool isPdf = true}) {
  if (!isPdf) {
    return "This file isn't really a PDF, even though its name ends in .pdf. "
        'It may be a different kind of document that was renamed.';
  }
  if (error is PdfPasswordException) {
    return 'This PDF is protected with a password.';
  }
  return switch (error is PdfException ? error.errorCode : null) {
    _errFormat =>
      'This PDF looks damaged, so it could not be opened. '
          'It may not have finished uploading to Google Drive.',
    _errSecurity =>
      'This PDF uses a kind of protection that cannot be opened '
          'here.',
    _errFile => 'This PDF could not be read from the device.',
    _ => 'This PDF could not be opened.',
  };
}
