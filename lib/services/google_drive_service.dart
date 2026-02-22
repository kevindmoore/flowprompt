import 'dart:convert';
import 'dart:typed_data';

import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:http/http.dart' as http;
import 'package:lumberdash/lumberdash.dart';

import 'package:flowprompt/models/recent_file.dart';
import 'package:flowprompt/services/preferences_service.dart';
import 'package:flowprompt/signals/prompter_signals.dart';

/// Info about a file from Google Drive
class DriveFileInfo {
  const DriveFileInfo({
    required this.id,
    required this.name,
    required this.mimeType,
    this.modifiedTime,
  });

  final String id;
  final String name;
  final String mimeType;
  final DateTime? modifiedTime;

  ScriptFileType get fileType {
    if (mimeType == 'application/vnd.google-apps.document') {
      return ScriptFileType.html;
    }
    
    final lower = name.toLowerCase();
    if (lower.endsWith('.md')) return ScriptFileType.markdown;
    if (lower.endsWith('.pdf')) return ScriptFileType.pdf;
    return ScriptFileType.text;
  }
}

/// Authenticated HTTP client for Google APIs
class _AuthClient extends http.BaseClient {
  _AuthClient(this._headers, this._inner);

  final Map<String, String> _headers;
  final http.Client _inner;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    request.headers.addAll(_headers);
    return _inner.send(request);
  }
}

class GoogleDriveService {
  GoogleDriveService(this.preferencesService);

  final PreferencesService preferencesService;

  final GoogleSignIn _googleSignIn = GoogleSignIn(
    scopes: ['https://www.googleapis.com/auth/drive.readonly'],
  );

  /// Check if user is currently signed in
  Future<bool> checkSignedIn() async {
    final account = await _googleSignIn.signInSilently();
    final signedIn = account != null;
    isSignedInToGoogle.value = signedIn;
    return signedIn;
  }

  /// Sign in to Google
  Future<bool> signIn() async {
    try {
      logMessage('GoogleDriveService: Starting sign in...');
      final account = await _googleSignIn.signIn();
      final signedIn = account != null;
      isSignedInToGoogle.value = signedIn;
      if (signedIn) {
        logMessage('GoogleDriveService: Signed in as ${account.email}');
      } else {
        logWarning('GoogleDriveService: Sign in returned null (user cancelled?)');
      }
      return signedIn;
    } catch (e, stackTrace) {
      logWarning(
        'GoogleDriveService: Sign in failed: '
        'type=${e.runtimeType}, message=$e',
      );
      logWarning('GoogleDriveService: Stack trace: $stackTrace');
      isSignedInToGoogle.value = false;
      return false;
    }
  }

  /// Sign out of Google
  Future<void> signOut() async {
    await _googleSignIn.signOut();
    isSignedInToGoogle.value = false;
    logMessage('GoogleDriveService: Signed out');
  }

  /// Get the current signed-in user's email
  String? get currentUserEmail => _googleSignIn.currentUser?.email;

  /// Get an authenticated Drive API client
  Future<drive.DriveApi?> _getDriveApi() async {
    final account = _googleSignIn.currentUser;
    if (account == null) return null;

    final auth = await account.authentication;
    final token = auth.accessToken;
    if (token == null) return null;

    final authClient = _AuthClient({
      'Authorization': 'Bearer $token',
    }, http.Client());

    return drive.DriveApi(authClient);
  }

  /// List .txt, .md, .pdf and Google Docs from Google Drive
  Future<List<DriveFileInfo>> listTextFiles() async {
    try {
      final driveApi = await _getDriveApi();
      if (driveApi == null) {
        logWarning('GoogleDriveService: Not authenticated');
        return [];
      }

      // Query broadly for text-like, PDF files, and Google Docs
      const query = "trashed=false and ("
          "mimeType='application/vnd.google-apps.document' or "
          "mimeType='text/plain' or "
          "mimeType='text/markdown' or "
          "mimeType='text/x-markdown' or "
          "mimeType='application/pdf' or "
          "mimeType='application/octet-stream' or "
          "name contains '.txt' or "
          "name contains '.md' or "
          "name contains '.pdf'"
          ")";

      logMessage('GoogleDriveService: Querying Drive with: $query');

      final fileList = await driveApi.files.list(
        q: query,
        spaces: 'drive',
        orderBy: 'modifiedTime desc',
        $fields: 'files(id, name, mimeType, modifiedTime)',
        pageSize: 100,
      );

      final files = fileList.files ?? [];
      logMessage(
        'GoogleDriveService: Drive returned ${files.length} files before filtering',
      );

      // Log first few results for debugging
      for (final f in files.take(5)) {
        logMessage(
          '  -> "${f.name}" (mimeType: ${f.mimeType})',
        );
      }

      // Filter
      final filtered = files
          .where(
            (f) =>
                f.name != null &&
                f.mimeType != null &&
                (f.mimeType == 'application/vnd.google-apps.document' ||
                    f.name!.endsWith('.txt') ||
                    f.name!.endsWith('.md') ||
                    f.name!.endsWith('.pdf')),
          )
          .map(
            (f) => DriveFileInfo(
              id: f.id!,
              name: f.name!,
              mimeType: f.mimeType!,
              modifiedTime: f.modifiedTime,
            ),
          )
          .toList();

      logMessage('GoogleDriveService: Found ${filtered.length} files after filtering');
      return filtered;
    } catch (e) {
      logWarning('GoogleDriveService: Error listing files: $e');
      return [];
    }
  }

  /// Download file bytes. Exports Google Docs to plain text.
  Future<Uint8List?> _downloadFileBytes(String fileId, String mimeType) async {
    try {
      final driveApi = await _getDriveApi();
      if (driveApi == null) return null;

      drive.Media media;
      
      if (mimeType == 'application/vnd.google-apps.document') {
         // Export Google Docs to HTML
         media = await driveApi.files.export(
            fileId,
            'text/html',
            downloadOptions: drive.DownloadOptions.fullMedia,
         ) as drive.Media;
      } else {
        // Download regular files directly
        media = await driveApi.files.get(
              fileId,
              downloadOptions: drive.DownloadOptions.fullMedia,
            ) as drive.Media;
      }

      final bytes = <int>[];
      await for (final chunk in media.stream) {
        bytes.addAll(chunk);
      }

      return Uint8List.fromList(bytes);
    } catch (e) {
      logWarning('GoogleDriveService: Error downloading file: $e');
      return null;
    }
  }

  /// Load a Drive file's content into the prompter
  Future<bool> loadDriveFile(DriveFileInfo file) async {
    try {
      final bytes = await _downloadFileBytes(file.id, file.mimeType);
      if (bytes == null) return false;

      if (file.fileType == ScriptFileType.pdf) {
        // Store raw bytes for visual PDF rendering
        pdfBytes.value = bytes;
        scriptContent.value = '';
      } else {
        pdfBytes.value = null;
        scriptContent.value = utf8.decode(bytes, allowMalformed: true);
      }

      scriptFileName.value = file.name;
      scriptFileType.value = file.fileType;
      isScrolling.value = false;

      preferencesService.addRecentFile(
        RecentFile(
          name: file.name,
          path: 'drive://${file.id}',
          source: FileSource.googleDrive,
          fileType: file.fileType,
          driveFileId: file.id,
          mimeType: file.mimeType,
        ),
      );

      logMessage(
        'GoogleDriveService: Loaded "${file.name}" (${bytes.length} bytes)',
      );
      return true;
    } catch (e) {
      logWarning('GoogleDriveService: Error loading file: $e');
      return false;
    }
  }
}
