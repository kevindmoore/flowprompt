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
final scrollSpeed = signal<double>(30.0);

/// Live multiplier applied by speech following (not persisted)
final speechSpeedMultiplier = signal<double>(1.0);

/// Current prompter progress from top (0.0) to bottom (1.0)
final currentPrompterProgress = signal<double>(0.0);

/// Whether speech following is enabled
final speechFollowEnabled = signal<bool>(true);

/// Whether the speech recognizer is actively listening
final speechListening = signal<bool>(false);

/// Short speech-follow status text for the prompter controls
final speechFollowStatus = signal<String>('Off');

/// Text font size (persisted)
final fontSize = signal<double>(32.0);

/// Selected font family name (persisted)
final fontFamily = signal<String>('Roboto Slab');

/// Recently opened files with name, path/id, and source
final recentFiles = signal<List<RecentFile>>([]);

/// Dark mode preference (persisted)
final isDarkMode = signal<bool>(true);

/// Whether the text is mirrored (for teleprompter glass)
final isMirrored = signal<bool>(false);

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
  speechSpeedMultiplier.value = 1.0;
  currentPrompterProgress.value = 0.0;
  speechFollowEnabled.value = true;
  speechListening.value = false;
  speechFollowStatus.value = 'Off';
  isMirrored.value = false;
  controlsVisible.value = true;
}
