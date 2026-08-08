import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:signals/signals_flutter.dart';

import 'package:flowprompt/models/recent_file.dart';
import 'package:flowprompt/router/app_router.gr.dart';
import 'package:flowprompt/services/google_drive_service.dart';
import 'package:flowprompt/services/service_locator.dart';
import 'package:flowprompt/signals/prompter_signals.dart';

@RoutePage()
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  Future<void> _openLocalFile(BuildContext context) async {
    final loaded = await Services.file.pickAndLoadLocalFile();
    if (loaded && context.mounted) {
      context.router.push(const PrompterRoute());
    }
  }

  Future<void> _openFromGoogleDrive(
    BuildContext context, {
    bool googleDocsOnly = false,
  }) async {
    // Ensure signed in
    if (!isSignedInToGoogle.value) {
      final signedIn = await Services.googleDrive.signIn();
      if (!signedIn) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Google Sign-In failed')),
          );
        }
        return;
      }
    }

    if (!context.mounted) return;

    // Show loading while fetching file list
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    final driveFiles = await Services.googleDrive.listTextFiles();
    final files = googleDocsOnly
        ? driveFiles
              .where(
                (file) =>
                    file.mimeType == 'application/vnd.google-apps.document',
              )
              .toList()
        : driveFiles;

    if (!context.mounted) return;
    Navigator.of(context).pop(); // Dismiss loading

    if (files.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            googleDocsOnly
                ? 'No Google Docs found in Google Drive'
                : 'No supported files found in Google Drive',
          ),
        ),
      );
      return;
    }

    // Show full-screen file picker
    final selected = await Navigator.of(context).push<DriveFileInfo>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (context) => _DriveFilePicker(
          files: files,
          title: googleDocsOnly ? 'Google Docs' : 'Google Drive Files',
        ),
      ),
    );

    if (selected == null || !context.mounted) return;

    // Show loading while downloading
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    final loaded = await Services.googleDrive.loadDriveFile(selected);

    if (!context.mounted) return;
    Navigator.of(context).pop(); // Dismiss loading

    if (loaded) {
      context.router.push(const PrompterRoute());
    } else {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Failed to load file')));
    }
  }

  Future<void> _openRecentFile(BuildContext context, RecentFile file) async {
    bool loaded;

    if (file.source == FileSource.local) {
      loaded = await Services.file.loadLocalFileFromPath(file.path);
    } else if (file.driveFileId != null) {
      // Ensure signed in for Drive files
      if (!isSignedInToGoogle.value) {
        final signedIn = await Services.googleDrive.signIn();
        if (!signedIn) {
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Sign in to Google to access Drive files'),
              ),
            );
          }
          return;
        }
      }

      loaded = await Services.googleDrive.loadDriveFile(
        DriveFileInfo(
          id: file.driveFileId!,
          name: file.name,
          mimeType: file.mimeType ?? 'application/octet-stream',
        ),
      );
    } else {
      loaded = false;
    }

    if (loaded && context.mounted) {
      context.router.push(const PrompterRoute());
    } else if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not open "${file.name}"')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: false,
      appBar: AppBar(
        title: Text(
          'Flow Prompt',
          style: GoogleFonts.robotoSlab(fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            tooltip: 'Settings',
            onPressed: () => context.router.push(const SettingsRoute()),
          ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 600),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 32),
                  // App icon
                  Icon(
                    Icons.auto_stories,
                    size: 80,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Script Prompter',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.robotoSlab(
                      fontSize: 24,
                      fontWeight: FontWeight.w300,
                      color: Theme.of(
                        context,
                      ).colorScheme.onSurface.withValues(alpha: 0.7),
                    ),
                  ),
                  const SizedBox(height: 48),

                  // Action buttons
                  FilledButton.icon(
                    onPressed: () => _openLocalFile(context),
                    icon: const Icon(Icons.folder_open),
                    label: const Text('Open Local File'),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      textStyle: const TextStyle(fontSize: 18),
                    ),
                  ),
                  const SizedBox(height: 16),
                  OutlinedButton.icon(
                    onPressed: () => _openFromGoogleDrive(context),
                    icon: const Icon(Icons.cloud_download),
                    label: const Text('Open from Google Drive'),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      textStyle: const TextStyle(fontSize: 18),
                    ),
                  ),
                  const SizedBox(height: 16),
                  OutlinedButton.icon(
                    onPressed: () =>
                        _openFromGoogleDrive(context, googleDocsOnly: true),
                    icon: const Icon(Icons.description),
                    label: const Text('Open from Google Docs'),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      textStyle: const TextStyle(fontSize: 18),
                    ),
                  ),

                  const SizedBox(height: 40),

                  // Recent files
                  SignalBuilder(
                    builder: (context) {
                      final recent = recentFiles.value;

                      if (recent.isNotEmpty) {
                        return Expanded(
                          child: Column(
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      'Recent Files',
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleMedium
                                          ?.copyWith(
                                            fontWeight: FontWeight.bold,
                                          ),
                                    ),
                                  ),
                                  TextButton.icon(
                                    onPressed: () {
                                      Services.preferences.clearRecentFiles();
                                    },
                                    icon: const Icon(Icons.clear_all, size: 18),
                                    label: const Text('Clear'),
                                    style: TextButton.styleFrom(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Expanded(
                                child: ListView.separated(
                                  itemCount: recent.length,
                                  separatorBuilder: (_, _) =>
                                      const Divider(height: 1),
                                  itemBuilder: (context, index) {
                                    final file = recent[index];
                                    return ListTile(
                                      leading: Icon(
                                        file.source == FileSource.googleDrive
                                            ? Icons.cloud
                                            : Icons.insert_drive_file,
                                        color: switch (file.fileType) {
                                          ScriptFileType.markdown =>
                                            Colors.blue,
                                          ScriptFileType.pdf => Colors.red,
                                          ScriptFileType.html => Colors.orange,
                                          ScriptFileType.text => Colors.grey,
                                        },
                                      ),
                                      title: Text(
                                        file.name,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      subtitle: Text(file.sourceLabel),
                                      onTap: () =>
                                          _openRecentFile(context, file),
                                    );
                                  },
                                ),
                              ),
                            ],
                          ),
                        );
                      }

                      return Expanded(
                        child: Center(
                          child: Text(
                            'Open a file to get started',
                            style: Theme.of(context).textTheme.bodyLarge
                                ?.copyWith(
                                  color: Theme.of(context).colorScheme.onSurface
                                      .withValues(alpha: 0.5),
                                ),
                          ),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Full-screen browser to pick a file from Google Drive
class _DriveFilePicker extends StatefulWidget {
  const _DriveFilePicker({required this.files, required this.title});

  final List<DriveFileInfo> files;
  final String title;

  @override
  State<_DriveFilePicker> createState() => _DriveFilePickerState();
}

class _DriveFilePickerState extends State<_DriveFilePicker> {
  final _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final files = _query.isEmpty
        ? widget.files
        : widget.files
              .where((file) => file.name.toLowerCase().contains(_query))
              .toList();

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        leading: IconButton(
          icon: const Icon(Icons.close),
          tooltip: 'Cancel',
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  hintText: 'Search files',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: _query.isEmpty
                      ? null
                      : IconButton(
                          icon: const Icon(Icons.clear),
                          tooltip: 'Clear search',
                          onPressed: () {
                            _searchController.clear();
                            setState(() => _query = '');
                          },
                        ),
                  border: const OutlineInputBorder(),
                ),
                textInputAction: TextInputAction.search,
                onChanged: (value) {
                  setState(() => _query = value.toLowerCase().trim());
                },
              ),
            ),
            Expanded(
              child: files.isEmpty
                  ? const Center(child: Text('No matching files'))
                  : ListView.separated(
                      itemCount: files.length,
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final file = files[index];
                        final isGoogleDoc =
                            file.mimeType ==
                            'application/vnd.google-apps.document';
                        final isMarkdown = file.name.endsWith('.md');
                        return ListTile(
                          leading: Icon(
                            isGoogleDoc
                                ? Icons.description
                                : isMarkdown
                                ? Icons.description
                                : Icons.text_snippet,
                            color: isGoogleDoc || isMarkdown
                                ? Colors.blue
                                : Colors.grey,
                          ),
                          title: Text(
                            file.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: file.modifiedTime != null
                              ? Text(
                                  _formatDate(file.modifiedTime!),
                                  style: Theme.of(context).textTheme.bodySmall,
                                )
                              : null,
                          onTap: () => Navigator.of(context).pop(file),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatDate(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }
}
