import 'package:flowprompt/services/file_service.dart';
import 'package:flowprompt/services/google_drive_service.dart';
import 'package:flowprompt/services/preferences_service.dart';

/// Simple global service locator for the app
class Services {
  Services._();

  static late final PreferencesService preferences;
  static late final FileService file;
  static late final GoogleDriveService googleDrive;
}
