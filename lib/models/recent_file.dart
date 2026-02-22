import 'dart:convert';

enum FileSource { local, googleDrive }

enum ScriptFileType { text, markdown, pdf, html }

class RecentFile {
  const RecentFile({
    required this.name,
    required this.path,
    required this.source,
    required this.fileType,
    this.driveFileId,
    this.mimeType,
  });

  final String name;
  final String path;
  final FileSource source;
  final ScriptFileType fileType;
  final String? driveFileId;
  final String? mimeType;

  String get sourceLabel => source == FileSource.local ? 'Local' : 'Drive';

  String get icon {
    switch (fileType) {
      case ScriptFileType.markdown:
        return '📝';
      case ScriptFileType.pdf:
        return '📕';
      case ScriptFileType.text:
      case ScriptFileType.html:
        return '📄';
    }
  }

  Map<String, dynamic> toJson() => {
    'name': name,
    'path': path,
    'source': source.name,
    'fileType': fileType.name,
    'driveFileId': driveFileId,
    'mimeType': mimeType,
  };

  factory RecentFile.fromJson(Map<String, dynamic> json) => RecentFile(
    name: json['name'] as String,
    path: json['path'] as String,
    source: FileSource.values.byName(json['source'] as String),
    fileType: ScriptFileType.values.byName(json['fileType'] as String),
    driveFileId: json['driveFileId'] as String?,
    mimeType: json['mimeType'] as String?,
  );

  static String encodeList(List<RecentFile> files) =>
      jsonEncode(files.map((f) => f.toJson()).toList());

  static List<RecentFile> decodeList(String jsonStr) {
    final list = jsonDecode(jsonStr) as List<dynamic>;
    return list
        .map((e) => RecentFile.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RecentFile &&
          runtimeType == other.runtimeType &&
          name == other.name &&
          source == other.source;

  @override
  int get hashCode => name.hashCode ^ source.hashCode;
}
