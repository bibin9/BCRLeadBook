import 'dart:convert';
import 'dart:io';
import 'dart:ui' show Rect;

import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

/// Platform file pickers and the system share sheet. Files are written to the
/// app's temporary folder first and handed to the share sheet, from which the
/// user chooses where to keep them (Files, Drive, email, ...).
class FileService {
  FileService._();

  static Future<List<String>> _write(Map<String, String> files) async {
    final dir = await getTemporaryDirectory();
    final out = <String>[];
    for (final e in files.entries) {
      final f = File(p.join(dir.path, e.key));
      await f.writeAsBytes(utf8.encode(e.value), flush: true);
      out.add(f.path);
    }
    return out;
  }

  /// Removes export/backup files left in the temporary folder by earlier
  /// shares, so private data does not linger. Runs at start-up (deleting right
  /// after sharing could break the receiving app, which may still be reading).
  static Future<void> cleanupTempExports() async {
    try {
      final dir = await getTemporaryDirectory();
      await for (final e in dir.list()) {
        if (e is! File) continue;
        final n = p.basename(e.path);
        if (n.startsWith('bcr-leadbook-backup-') ||
            const {'leads_overview.csv', 'renewals.csv', 'contacts.csv', 'products.csv', 'meetings.csv', 'follow_ups.csv', 'README.txt'}.contains(n)) {
          await e.delete();
        }
      }
    } catch (_) {}
  }

  /// Returns true if the share sheet was shown.
  /// [origin] anchors the share popover on iPad (ignored on phones).
  static Future<bool> shareTextFiles(Map<String, String> files, {String? subject, Rect? origin}) async {
    final paths = await _write(files);
    final result = await SharePlus.instance.share(ShareParams(
      files: [for (final path in paths) XFile(path)],
      subject: subject,
      sharePositionOrigin: origin,
    ));
    return result.status != ShareResultStatus.unavailable ||
        paths.isNotEmpty; // some platforms cannot report a result
  }

  /// Lets the user choose a file and returns its text, or null if cancelled.
  static Future<({String name, String text})?> pickTextFile() async {
    final f = await FilePicker.pickFile(type: FileType.any);
    if (f == null) return null;
    final bytes = await f.readAsBytes();
    return (name: f.name, text: utf8.decode(bytes, allowMalformed: false));
  }
}
