# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Flow Prompt is a Flutter teleprompter application for tablets that supports text files (.txt), Markdown (.md), PDF documents, and Google Docs. It provides auto-scrolling functionality with customizable speed, font settings, and a mirror mode for use with teleprompter glass.

## Development Commands

### Build and Run
```bash
flutter run                    # Run on connected device/emulator
flutter build apk              # Build Android APK
flutter build ios              # Build iOS app (requires macOS)
```

### Code Generation
```bash
# Generate auto_route navigation code
flutter pub run build_runner build --delete-conflicting-outputs

# Watch mode for continuous generation during development
flutter pub run build_runner watch --delete-conflicting-outputs
```

### App Icons and Splash Screens
```bash
# Generate app icons from assets/images/app_icon_adaptive.png
flutter pub run flutter_launcher_icons

# Generate splash screens from assets/images/app_icon_splash.png
flutter pub run flutter_native_splash:create
```

### Testing
```bash
flutter test                   # Run all tests
flutter test test/widget_test.dart  # Run specific test file
```

### Linting
```bash
flutter analyze                # Run static analysis
```

## Architecture

### State Management
The app uses **signals** (from the `signals` package) for reactive state management. All global application state is defined in `lib/signals/prompter_signals.dart`:
- Script content, file name, and file type
- Auto-scroll state (playing/paused) and scroll speed
- UI preferences (font size, font family, dark mode, mirrored display)
- Recent files list
- Google Sign-In state

These signals are reactive and can be watched by UI components. Signals are persisted via `PreferencesService`.

### Service Locator Pattern
Services are accessed through a simple static service locator in `lib/services/service_locator.dart`:
- `Services.preferences` - User preferences and settings persistence
- `Services.file` - Local file operations (picker, loading, encoding detection)
- `Services.googleDrive` - Google Drive authentication and file operations

Services are initialized in `main()` before the app starts.

### Navigation
Uses **auto_route** for type-safe navigation. Routes are defined in `lib/router/app_router.dart`:
- `HomeRoute` - File selection and recent files (initial route)
- `PrompterRoute` - Teleprompter display with auto-scroll controls
- `SettingsRoute` - User preferences (speed, fonts, appearance)

Generated route code is in `lib/router/app_router.gr.dart` (do not edit manually).

### File Handling
The app supports four file types (enum `ScriptFileType`):
- **text** - Plain text files (.txt)
- **markdown** - Markdown files (.md) rendered with `flutter_markdown`
- **pdf** - PDF files rendered visually with `syncfusion_flutter_pdfviewer`
- **html** - Google Docs exported as HTML (rendered with `flutter_widget_from_html`)

`FileService` handles local file loading with automatic encoding detection (UTF-8, UTF-16 LE/BE, Latin-1). `GoogleDriveService` handles Drive authentication, file listing, and downloading (Google Docs are exported to HTML).

### Prompter Screen Architecture
`PrompterScreen` (`lib/ui/prompter/prompter_screen.dart`) is the core component:
- Uses `Ticker` (via `SingleTickerProviderStateMixin`) for smooth frame-by-frame auto-scrolling
- Maintains separate scroll controllers for text (`ScrollController`) and PDF (`PdfViewerController`)
- Implements 3-second countdown before auto-scroll starts
- Auto-hides controls after 4 seconds when scrolling
- Supports manual scrolling while auto-scrolling is active (disables auto-scroll temporarily)
- Progress bar at top shows scroll position
- Mirror mode flips content horizontally using `Transform` with `Matrix4.rotationY`

### Recent Files
Recent files are tracked in `recentFiles` signal (max 20 entries). Each `RecentFile` stores:
- File name and path (local path or `drive://{fileId}`)
- Source (local vs Google Drive)
- File type (for icon and rendering)
- Drive metadata (fileId, mimeType) for re-loading Drive files

Recent files are persisted as JSON in SharedPreferences.

## Local Package Dependency
This project depends on a local package `utilities` (located at `../utilities`). This package provides shared utilities used across multiple Flutter apps in the parent directory.

## Key Technical Decisions

### Encoding Detection
Text files are decoded with automatic encoding detection (`FileService._decodeBytes`):
1. Check for UTF-8 BOM (0xEF 0xBB 0xBF)
2. Check for UTF-16 LE BOM (0xFF 0xFE)
3. Check for UTF-16 BE BOM (0xFE 0xFF)
4. Try UTF-8 decoding
5. Fallback to Latin-1 if UTF-8 fails

### Google Docs Handling
Google Docs are exported as HTML (not plain text) to preserve formatting. The HTML is sanitized in `PrompterScreen._buildContent`:
- All `<style>` blocks are removed
- All inline `style="..."` attributes are removed
- This ensures the app's font, size, and color settings are used while preserving semantic structure (`<h1>`, `<b>`, `<ul>`, etc.)

### PDF Auto-Scroll
PDF scrolling uses `PdfViewerController.jumpTo(yOffset:)` with a manually tracked `_pdfScrollY` position. End-of-document detection checks if the controller's actual scroll offset stops changing despite incrementing `_pdfScrollY`.

### Wakelock
`wakelock_plus` keeps the screen on while the prompter is active (enabled in `PrompterScreen.initState`, disabled in `dispose`).

### Fullscreen Mode
Prompter screen uses `SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky)` for fullscreen (restored to `edgeToEdge` on dispose).

## Important Notes

- Google Sign-In requires platform-specific configuration files (not in repo): `android/app/google-services.json` and `ios/Runner/GoogleService-Info.plist`
- Generated files (`*.gr.dart`) should not be manually edited
- The app targets tablets (optimized for landscape orientation and larger screens)
- Logging uses `lumberdash` with `ColorizeLumberdash` for console output