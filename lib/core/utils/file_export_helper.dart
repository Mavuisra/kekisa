import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

/// Partage un fichier binaire (Excel, CSV, etc.) sur mobile/desktop.
class FileExportHelper {
  FileExportHelper._();

  static Future<void> shareBytes({
    required Uint8List bytes,
    required String filename,
    String? mimeType,
  }) async {
    if (kIsWeb) {
      throw UnsupportedError('Export fichier non supporte sur le web pour le moment.');
    }
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/$filename');
    await file.writeAsBytes(bytes, flush: true);
    await Share.shareXFiles(
      [XFile(file.path, mimeType: mimeType)],
      subject: filename,
    );
  }
}
