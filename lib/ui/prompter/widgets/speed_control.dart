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

    return Row(
      children: [
        // Slower button
        IconButton(
          icon: const Icon(Icons.remove_circle_outline, color: Colors.white),
          onPressed: speed > 10
              ? () {
                  onInteraction();
                  Services.preferences.saveScrollSpeed(
                    (speed - 10).clamp(10, 200),
                  );
                }
              : null,
          tooltip: 'Slower',
        ),

        // Speed slider
        Expanded(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Speed: ${speed.round()} px/s',
                style: const TextStyle(color: Colors.white70, fontSize: 12),
              ),
              SliderTheme(
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
                  value: speed,
                  min: 10,
                  max: 200,
                  divisions: 19,
                  onChanged: (value) {
                    onInteraction();
                    Services.preferences.saveScrollSpeed(value);
                  },
                ),
              ),
            ],
          ),
        ),

        // Faster button
        IconButton(
          icon: const Icon(Icons.add_circle_outline, color: Colors.white),
          onPressed: speed < 200
              ? () {
                  onInteraction();
                  Services.preferences.saveScrollSpeed(
                    (speed + 10).clamp(10, 200),
                  );
                }
              : null,
          tooltip: 'Faster',
        ),
      ],
    );
  }
}
