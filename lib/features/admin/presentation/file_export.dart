import 'dart:convert';

import 'package:coffee_tracker/features/admin/presentation/web_download_stub.dart'
    if (dart.library.js_interop) 'package:coffee_tracker/features/admin/presentation/web_download.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:share_plus/share_plus.dart';

/// Saves a generated text file in the way that is natural on each platform:
/// a browser download on the web, a "Save as" dialog on desktop and the
/// share sheet on phones. Returns false when the user cancelled.
Future<bool> exportTextFile(
  BuildContext context, {
  required String fileName,
  required String content,
  String mimeType = 'text/csv',
}) async {
  final safeName = fileName.replaceAll(RegExp(r'[\\/:*?"<>|]'), '-');
  final bytes = Uint8List.fromList(utf8.encode(content));

  if (kIsWeb) {
    downloadInBrowser(safeName, bytes, mimeType);
    return true;
  }

  switch (defaultTargetPlatform) {
    case TargetPlatform.android || TargetPlatform.iOS:
      final box = context.findRenderObject() as RenderBox?;
      final result = await SharePlus.instance.share(
        ShareParams(
          files: [XFile.fromData(bytes, mimeType: mimeType, name: safeName)],
          fileNameOverrides: [safeName],
          sharePositionOrigin: box == null ? null : box.localToGlobal(Offset.zero) & box.size,
        ),
      );
      return result.status != ShareResultStatus.dismissed;
    case TargetPlatform.windows || TargetPlatform.macOS || TargetPlatform.linux || TargetPlatform.fuchsia:
      final location = await getSaveLocation(
        suggestedName: safeName,
        acceptedTypeGroups: const [
          XTypeGroup(label: 'CSV', extensions: ['csv'], mimeTypes: ['text/csv']),
        ],
      );
      if (location == null) return false;
      await XFile.fromData(bytes, mimeType: mimeType, name: safeName).saveTo(location.path);
      return true;
  }
}
