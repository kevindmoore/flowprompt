import 'dart:typed_data';

import 'package:signals/signals.dart';

import 'package:flowprompt/models/recent_file.dart';

/// The loaded file content
final scriptContent = signal<String>('');

/// Display name of the current file
final scriptFileName = signal<String>('');

/// File type determines rendering (.txt vs .md vs .pdf)
final scriptFileType = signal<ScriptFileType>(ScriptFileType.text);

/// Raw PDF bytes for visual rendering (null when not a PDF)
final pdfBytes = signal<Uint8List?>(null);

/// Play/pause state for auto-scrolling
final isScrolling = signal<bool>(false);

/// Scroll speed in pixels per second (persisted)
final scrollSpeed = signal<double>(50.0);

/// Text font size (persisted)
final fontSize = signal<double>(32.0);

/// Selected font family name (persisted)
final fontFamily = signal<String>('Roboto Slab');

/// Recently opened files with name, path/id, and source
final recentFiles = signal<List<RecentFile>>([]);

/// Dark mode preference (persisted)
final isDarkMode = signal<bool>(true);

/// Overlay controls visibility
final controlsVisible = signal<bool>(true);

/// Google Sign-In state
final isSignedInToGoogle = signal<bool>(false);

/// Whether a file is currently loaded and ready for prompting
final isFileLoaded = computed<bool>(
  () => scriptContent.value.isNotEmpty || pdfBytes.value != null,
);

/// Reset all script-related signals (when navigating away from prompter)
void resetScript() {
  scriptContent.value = '';
  scriptFileName.value = '';
  scriptFileType.value = ScriptFileType.text;
  pdfBytes.value = null;
  isScrolling.value = false;
  controlsVisible.value = true;
}
