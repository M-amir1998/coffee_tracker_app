import 'dart:typed_data';

/// Only used on the web; see `web_download.dart`.
void downloadInBrowser(String fileName, Uint8List bytes, String mimeType) =>
    throw UnsupportedError('Browser downloads are only available on the web.');
