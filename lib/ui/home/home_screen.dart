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

  Future<void> _openFromGoogleDrive(BuildContext context) async {
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

    final files = await Services.googleDrive.listTextFiles();

    if (!context.mounted) return;
    Navigator.of(context).pop(); // Dismiss loading

    if (files.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No .txt or .md files found in Google Drive'),
        ),
      );
      return;
    }

    // Show file picker dialog
    final selected = await showDialog<DriveFileInfo>(
      context: context,
      builder: (context) => _DriveFilePicker(files: files),
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
        DriveFileInfo(id: file.driveFileId!, name: file.name),
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
    final recent = recentFiles.watch(context);

    return Scaffold(
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

                  const SizedBox(height: 40),

                  // Recent files
                  if (recent.isNotEmpty) ...[
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Recent Files',
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(fontWeight: FontWeight.bold),
                          ),
                        ),
                        TextButton.icon(
                          onPressed: () {
                            Services.preferences.clearRecentFiles();
                          },
                          icon: const Icon(Icons.clear_all, size: 18),
                          label: const Text('Clear'),
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Expanded(
                      child: ListView.separated(
                        itemCount: recent.length,
                        separatorBuilder: (_, _) => const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final file = recent[index];
                          return ListTile(
                            leading: Icon(
                              file.source == FileSource.googleDrive
                                  ? Icons.cloud
                                  : Icons.insert_drive_file,
                              color: switch (file.fileType) {
                                ScriptFileType.markdown => Colors.blue,
                                ScriptFileType.pdf => Colors.red,
                                ScriptFileType.text => Colors.grey,
                              },
                            ),
                            title: Text(
                              file.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: Text(file.sourceLabel),
                            onTap: () => _openRecentFile(context, file),
                          );
                        },
                      ),
                    ),
                  ] else
                    Expanded(
                      child: Center(
                        child: Text(
                          'Open a file to get started',
                          style: Theme.of(context).textTheme.bodyLarge
                              ?.copyWith(
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurface.withValues(alpha: 0.5),
                              ),
                        ),
                      ),
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

/// Dialog to browse and pick a file from Google Drive
class _DriveFilePicker extends StatelessWidget {
  const _DriveFilePicker({required this.files});

  final List<DriveFileInfo> files;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Google Drive Files'),
      content: SizedBox(
        width: double.maxFinite,
        height: 400,
        child: ListView.separated(
          itemCount: files.length,
          separatorBuilder: (_, _) => const Divider(height: 1),
          itemBuilder: (context, index) {
            final file = files[index];
            final isMarkdown = file.name.endsWith('.md');
            return ListTile(
              leading: Icon(
                isMarkdown ? Icons.description : Icons.text_snippet,
                color: isMarkdown ? Colors.blue : Colors.grey,
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
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
      ],
    );
  }

  String _formatDate(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }
}
