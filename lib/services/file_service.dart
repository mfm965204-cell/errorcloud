import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Writes decrypted bytes back to the device.
class FileService {
  FileService._();

  /// Opens the platform save dialog (Android: SAF "create document", which
  /// lands in Downloads or wherever the user picks). Returns the saved path, or
  /// null if the user cancelled.
  ///
  /// If the platform cannot show a save dialog, the file is written to the
  /// app's documents directory instead and that path is returned.
  static Future<String?> save(Uint8List bytes, String fileName) async {
    try {
      final path = await FilePicker.platform.saveFile(
        dialogTitle: 'Save decrypted file',
        fileName: fileName,
        bytes: bytes,
      );
      if (path == null) return null;
      return path;
    } catch (_) {
      final dir = await getApplicationDocumentsDirectory();
      final target = File(p.join(dir.path, fileName));
      await target.writeAsBytes(bytes, flush: true);
      return target.path;
    }
  }
}
