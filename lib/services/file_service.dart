import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:lumberdash/lumberdash.dart';

import 'package:flowprompt/models/recent_file.dart';
import 'package:flowprompt/services/preferences_service.dart';
import 'package:flowprompt/signals/prompter_signals.dart';

class FileService {
  FileService(this.preferencesService);

  final PreferencesService preferencesService;

  /// Opens a file picker for .txt, .md, and .pdf files, loads the content
  /// Returns true if a file was successfully loaded
  Future<bool> pickAndLoadLocalFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['txt', 'md', 'pdf'],
        allowMultiple: false,
      );

      if (result == null || result.files.isEmpty) {
        return false;
      }

      final file = result.files.first;
      final path = file.path;
      if (path == null) {
        logWarning('FileService: File path is null');
        return false;
      }

      return await loadLocalFileFromPath(path);
    } catch (e) {
      logWarning('FileService: Error picking file: $e');
      return false;
    }
  }

  /// Loads a local file by its path
  Future<bool> loadLocalFileFromPath(String path) async {
    try {
      final file = File(path);
      if (!await file.exists()) {
        logWarning('FileService: File does not exist: $path');
        return false;
      }

      final bytes = await file.readAsBytes();
      final name = path.split('/').last;
      final fileType = _detectFileType(name);

      if (fileType == ScriptFileType.pdf) {
        // Store raw bytes for visual PDF rendering
        pdfBytes.value = bytes;
        scriptContent.value = '';
      } else {
        pdfBytes.value = null;
        scriptContent.value = _decodeBytes(bytes);
      }

      scriptFileName.value = name;
      scriptFileType.value = fileType;
      isScrolling.value = false;

      preferencesService.addRecentFile(
        RecentFile(
          name: name,
          path: path,
          source: FileSource.local,
          fileType: fileType,
        ),
      );

      return true;
    } catch (e) {
      logWarning('FileService: Error loading file: $e');
      return false;
    }
  }

  /// Detect encoding and decode bytes to string.
  /// Supports UTF-8 (with/without BOM), UTF-16 LE/BE, and Latin-1 fallback.
  String _decodeBytes(Uint8List bytes) {
    if (bytes.length >= 3 &&
        bytes[0] == 0xEF &&
        bytes[1] == 0xBB &&
        bytes[2] == 0xBF) {
      // UTF-8 BOM -- skip the 3-byte BOM and decode as UTF-8
      return utf8.decode(bytes.sublist(3));
    }

    if (bytes.length >= 2 && bytes[0] == 0xFF && bytes[1] == 0xFE) {
      // UTF-16 Little Endian BOM
      return _decodeUtf16Le(bytes.sublist(2));
    }

    if (bytes.length >= 2 && bytes[0] == 0xFE && bytes[1] == 0xFF) {
      // UTF-16 Big Endian BOM
      return _decodeUtf16Be(bytes.sublist(2));
    }

    // Try UTF-8 first
    try {
      return utf8.decode(bytes);
    } on FormatException {
      logMessage('FileService: Not valid UTF-8, falling back to Latin-1');
      return latin1.decode(bytes);
    }
  }

  String _decodeUtf16Le(Uint8List bytes) {
    final buffer = StringBuffer();
    for (var i = 0; i + 1 < bytes.length; i += 2) {
      buffer.writeCharCode(bytes[i] | (bytes[i + 1] << 8));
    }
    return buffer.toString();
  }

  String _decodeUtf16Be(Uint8List bytes) {
    final buffer = StringBuffer();
    for (var i = 0; i + 1 < bytes.length; i += 2) {
      buffer.writeCharCode((bytes[i] << 8) | bytes[i + 1]);
    }
    return buffer.toString();
  }

  /// Detect file type from file name extension
  static ScriptFileType _detectFileType(String name) {
    final lower = name.toLowerCase();
    if (lower.endsWith('.md')) return ScriptFileType.markdown;
    if (lower.endsWith('.pdf')) return ScriptFileType.pdf;
    return ScriptFileType.text;
  }

}
