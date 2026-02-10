import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:signals/signals_flutter.dart';

import 'package:flowprompt/services/service_locator.dart';
import 'package:flowprompt/signals/prompter_signals.dart';

/// Curated list of fonts suitable for script prompting
const _availableFonts = [
  'Roboto Slab',
  'Roboto',
  'Lora',
  'Merriweather',
  'Open Sans',
  'Source Sans 3',
  'Noto Sans',
  'PT Serif',
  'Playfair Display',
  'IBM Plex Serif',
  'Libre Baskerville',
];

@RoutePage()
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final dark = isDarkMode.watch(context);
    final currentFontSize = fontSize.watch(context);
    final currentSpeed = scrollSpeed.watch(context);
    final currentFont = fontFamily.watch(context);
    final signedIn = isSignedInToGoogle.watch(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.router.maybePop(),
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // Appearance
            const _SectionHeader(title: 'Appearance'),
            SwitchListTile(
              title: const Text('Dark Mode'),
              subtitle: const Text(
                'Dark background reduces glare for prompting',
              ),
              value: dark,
              onChanged: (value) => Services.preferences.saveDarkMode(value),
              secondary: Icon(dark ? Icons.dark_mode : Icons.light_mode),
            ),
            const Divider(),

            // Font family
            ListTile(
              leading: const Icon(Icons.font_download),
              title: const Text('Font Family'),
              subtitle: Text(currentFont),
              onTap: () => _showFontPicker(context, currentFont),
            ),
            const Divider(),

            // Font size
            ListTile(
              leading: const Icon(Icons.format_size),
              title: const Text('Default Font Size'),
              subtitle: Text('${currentFontSize.round()} pt'),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Slider(
                value: currentFontSize,
                min: 16,
                max: 80,
                divisions: 16,
                label: '${currentFontSize.round()}',
                onChanged: (value) => Services.preferences.saveFontSize(value),
              ),
            ),

            // Preview
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: dark ? Colors.black : Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Theme.of(context).dividerColor),
              ),
              child: Text(
                'The quick brown fox jumps over the lazy dog.',
                style: GoogleFonts.getFont(
                  currentFont,
                  fontSize: currentFontSize.clamp(16, 40),
                  color: dark ? Colors.white : Colors.black,
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Scrolling
            const _SectionHeader(title: 'Scrolling'),
            ListTile(
              leading: const Icon(Icons.speed),
              title: const Text('Default Scroll Speed'),
              subtitle: Text('${currentSpeed.round()} px/s'),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Slider(
                value: currentSpeed,
                min: 10,
                max: 200,
                divisions: 19,
                label: '${currentSpeed.round()}',
                onChanged: (value) =>
                    Services.preferences.saveScrollSpeed(value),
              ),
            ),
            const SizedBox(height: 16),

            // Google Drive
            const _SectionHeader(title: 'Google Drive'),
            if (signedIn)
              ListTile(
                leading: const Icon(Icons.cloud_done, color: Colors.green),
                title: Text(
                  Services.googleDrive.currentUserEmail ?? 'Signed In',
                ),
                subtitle: const Text('Connected to Google Drive'),
                trailing: TextButton(
                  onPressed: () async {
                    await Services.googleDrive.signOut();
                  },
                  child: const Text('Sign Out'),
                ),
              )
            else
              ListTile(
                leading: const Icon(Icons.cloud_off),
                title: const Text('Not connected'),
                subtitle: const Text('Sign in to browse Google Drive files'),
                trailing: FilledButton(
                  onPressed: () async {
                    final success = await Services.googleDrive.signIn();
                    if (!success && context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Google Sign-In failed')),
                      );
                    }
                  },
                  child: const Text('Sign In'),
                ),
              ),
            const SizedBox(height: 16),

            // Data
            const _SectionHeader(title: 'Data'),
            ListTile(
              leading: const Icon(Icons.delete_outline),
              title: const Text('Clear Recent Files'),
              subtitle: Text(
                '${recentFiles.watch(context).length} files in history',
              ),
              onTap: () {
                Services.preferences.clearRecentFiles();
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Recent files cleared')),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showFontPicker(BuildContext context, String currentFont) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Choose Font'),
        content: SizedBox(
          width: double.maxFinite,
          height: 400,
          child: ListView.builder(
            itemCount: _availableFonts.length,
            itemBuilder: (context, index) {
              final font = _availableFonts[index];
              final isSelected = font == currentFont;
              return ListTile(
                title: Text(
                  font,
                  style: GoogleFonts.getFont(font, fontSize: 18),
                ),
                trailing: isSelected
                    ? const Icon(Icons.check, color: Colors.green)
                    : null,
                selected: isSelected,
                onTap: () {
                  Services.preferences.saveFontFamily(font);
                  Navigator.of(context).pop();
                },
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
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 16, bottom: 8, left: 16),
      child: Text(
        title.toUpperCase(),
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: Theme.of(context).colorScheme.primary,
          fontWeight: FontWeight.bold,
          letterSpacing: 1.2,
        ),
      ),
    );
  }
}
