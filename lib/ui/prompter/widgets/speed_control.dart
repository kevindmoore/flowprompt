import 'package:flutter/material.dart';
import 'package:signals/signals_flutter.dart';

import 'package:flowprompt/services/service_locator.dart';
import 'package:flowprompt/signals/prompter_signals.dart';

class SpeedControl extends StatelessWidget {
  const SpeedControl({super.key, required this.onInteraction});

  final VoidCallback onInteraction;

  @override
  Widget build(BuildContext context) {
    final speed = scrollSpeed.watch(context);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'Speed: ${speed.round()} px/s',
          style: const TextStyle(
            color: Colors.white70,
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Slower button
            IconButton(
              icon: const Icon(
                Icons.remove_circle_outline,
                color: Colors.white,
              ),
              iconSize: 36,
              onPressed: speed > 5
                  ? () {
                      onInteraction();
                      Services.preferences.saveScrollSpeed(
                        (speed - 2).clamp(5, 100),
                      );
                    }
                  : null,
              tooltip: 'Slower',
            ),

            // Speed slider
            Expanded(
              child: SliderTheme(
                data: SliderThemeData(
                  activeTrackColor: Colors.white70,
                  inactiveTrackColor: Colors.white24,
                  thumbColor: Colors.white,
                  overlayColor: Colors.white24,
                  trackHeight: 3,
                  thumbShape: const RoundSliderThumbShape(
                    enabledThumbRadius: 8,
                  ),
                ),
                child: Slider(
                  value: speed.clamp(5, 100),
                  min: 5,
                  max: 100,
                  divisions: 19,
                  onChanged: (value) {
                    onInteraction();
                    Services.preferences.saveScrollSpeed(value);
                  },
                ),
              ),
            ),

            // Faster button
            IconButton(
              icon: const Icon(
                Icons.add_circle_outline,
                color: Colors.white,
              ),
              iconSize: 36,
              onPressed: speed < 100
                  ? () {
                      onInteraction();
                      Services.preferences.saveScrollSpeed(
                        (speed + 2).clamp(5, 100),
                      );
                    }
                  : null,
              tooltip: 'Faster',
            ),
          ],
        ),
      ],
    );
  }
}
