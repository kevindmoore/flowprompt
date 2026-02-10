import 'package:flutter/material.dart';
import 'package:lumberdash/lumberdash.dart';
import 'package:colorize_lumberdash/colorize_lumberdash.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:signals/signals_flutter.dart';

import 'package:flowprompt/router/app_router.dart';
import 'package:flowprompt/services/file_service.dart';
import 'package:flowprompt/services/google_drive_service.dart';
import 'package:flowprompt/services/preferences_service.dart';
import 'package:flowprompt/services/service_locator.dart';
import 'package:flowprompt/signals/prompter_signals.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize logging
  putLumberdashToWork(withClients: [ColorizeLumberdash()]);

  // Initialize shared preferences and services
  final prefs = await SharedPreferences.getInstance();
  Services.preferences = PreferencesService(prefs);
  Services.file = FileService(Services.preferences);
  Services.googleDrive = GoogleDriveService(Services.preferences);

  // Load persisted settings into signals
  Services.preferences.loadSettings();

  // Check Google Sign-In state silently
  await Services.googleDrive.checkSignedIn();

  logMessage('FlowPrompt: Initialization complete');

  runApp(const FlowPromptApp());
}

class FlowPromptApp extends StatefulWidget {
  const FlowPromptApp({super.key});

  @override
  State<FlowPromptApp> createState() => _FlowPromptAppState();
}

class _FlowPromptAppState extends State<FlowPromptApp> {
  final _appRouter = AppRouter();

  @override
  Widget build(BuildContext context) {
    final dark = isDarkMode.watch(context);

    return MaterialApp.router(
      title: 'Flow Prompt',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.indigo,
          brightness: Brightness.light,
        ),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.indigo,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      themeMode: dark ? ThemeMode.dark : ThemeMode.light,
      routerConfig: _appRouter.config(),
    );
  }
}
