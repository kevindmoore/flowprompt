import 'package:flutter/material.dart';
import 'package:signals/signals_flutter.dart';

import 'package:flowprompt/services/service_locator.dart';
import 'package:flowprompt/signals/prompter_signals.dart';
import 'package:flowprompt/ui/prompter/widgets/speed_control.dart';

class PrompterControls extends StatelessWidget {
  const PrompterControls({
    super.key,
    required this.fileName,
    required this.isScrolling,
    required this.onPlayPause,
    required this.onResetToTop,
    required this.speechEnabled,
    required this.speechActive,
    required this.speechListening,
    required this.onToggleSpeech,
    required this.onBack,
    required this.onInteraction,
  });

  final String fileName;
  final bool isScrolling;
  final bool speechEnabled;
  final bool speechActive;
  final bool speechListening;
  final VoidCallback onPlayPause;
  final VoidCallback onResetToTop;
  final VoidCallback onToggleSpeech;
  final VoidCallback onBack;
  final VoidCallback onInteraction;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Top bar: back button, file name, font controls
        SignalBuilder(
          builder: (context) {
            final currentFontSize = fontSize.value;

            return _TopBar(
              fileName: fileName,
              currentFontSize: currentFontSize,
              speechEnabled: speechEnabled,
              speechActive: speechActive,
              speechListening: speechListening,
              onToggleSpeech: onToggleSpeech,
              onBack: onBack,
              onFontSizeChanged: (size) {
                onInteraction();
                Services.preferences.saveFontSize(size);
              },
            );
          },
        ),

        const Spacer(),

        // Center: Play/Pause button
        _PlayPauseButton(
          isScrolling: isScrolling,
          onPressed: () {
            onInteraction();
            onPlayPause();
          },
        ),

        const Spacer(),

        // Bottom: Speed control and reset
        _BottomBar(
          speechListening: speechListening,
          onResetToTop: () {
            onInteraction();
            onResetToTop();
          },
          onInteraction: onInteraction,
        ),
      ],
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.fileName,
    required this.currentFontSize,
    required this.speechEnabled,
    required this.speechActive,
    required this.speechListening,
    required this.onToggleSpeech,
    required this.onBack,
    required this.onFontSizeChanged,
  });

  final String fileName;
  final double currentFontSize;
  final bool speechEnabled;
  final bool speechActive;
  final bool speechListening;
  final VoidCallback onToggleSpeech;
  final VoidCallback onBack;
  final ValueChanged<double> onFontSizeChanged;

  @override
  Widget build(BuildContext context) {
    final speechColor = speechEnabled && speechActive
        ? _speechColor(listening: speechListening)
        : Colors.white54;

    return Container(
      padding: const EdgeInsets.only(top: 8, left: 8, right: 8),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.black54, Colors.transparent],
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Row(
          children: [
            IconButton(
              icon: const Icon(Icons.arrow_back, color: Colors.white),
              onPressed: onBack,
              tooltip: 'Back',
            ),
            Expanded(
              child: Text(
                fileName,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white70, fontSize: 14),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            IconButton(
              icon: Icon(
                speechEnabled && speechActive
                    ? (speechListening ? Icons.mic : Icons.mic_none)
                    : Icons.mic_off,
                color: speechColor,
              ),
              onPressed: onToggleSpeech,
              tooltip: !speechEnabled
                  ? 'Turn on speech follow'
                  : speechActive
                      ? 'Turn off speech follow'
                      : 'Speech follow ready — starts with Play',
            ),
            // Font size controls
            IconButton(
              icon: const Icon(Icons.text_decrease, color: Colors.white),
              onPressed: currentFontSize > 16
                  ? () => onFontSizeChanged(currentFontSize - 4)
                  : null,
              tooltip: 'Decrease font size',
            ),
            Text(
              '${currentFontSize.round()}',
              style: const TextStyle(color: Colors.white70, fontSize: 14),
            ),
            IconButton(
              icon: const Icon(Icons.text_increase, color: Colors.white),
              onPressed: currentFontSize < 80
                  ? () => onFontSizeChanged(currentFontSize + 4)
                  : null,
              tooltip: 'Increase font size',
            ),
            // Mirror button
            SignalBuilder(
              builder: (context) => IconButton(
                icon: Icon(
                  isMirrored.value ? Icons.flip : Icons.flip_outlined,
                  color: Colors.white,
                ),
                onPressed: () {
                  isMirrored.value = !isMirrored.value;
                },
                tooltip: 'Mirror Text',
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PlayPauseButton extends StatelessWidget {
  const _PlayPauseButton({required this.isScrolling, required this.onPressed});

  final bool isScrolling;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onPressed,
      child: Container(
        width: 80,
        height: 80,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.black45,
          border: Border.all(color: Colors.white30, width: 2),
        ),
        child: Icon(
          isScrolling ? Icons.pause : Icons.play_arrow,
          size: 48,
          color: Colors.white,
        ),
      ),
    );
  }
}

class _BottomBar extends StatelessWidget {
  const _BottomBar({
    required this.speechListening,
    required this.onResetToTop,
    required this.onInteraction,
  });

  final bool speechListening;
  final VoidCallback onResetToTop;
  final VoidCallback onInteraction;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.only(bottom: 8, left: 16, right: 16),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [Colors.black54, Colors.transparent],
        ),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SpeedControl(onInteraction: onInteraction),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                TextButton.icon(
                  onPressed: onResetToTop,
                  icon: const Icon(
                    Icons.vertical_align_top,
                    color: Colors.white70,
                  ),
                  label: const Text(
                    'Reset to Top',
                    style: TextStyle(color: Colors.white70),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

Color _speechColor({required bool listening}) {
  return listening ? Colors.greenAccent : Colors.redAccent;
}
