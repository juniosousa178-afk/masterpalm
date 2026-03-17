// lib/screens/backup_screen.dart
// Web: exporta dados como JSON para download.
// Mobile/Desktop: backup local completo com zip.

export 'backup_screen_web.dart'
    if (dart.library.io) 'backup_screen_mobile.dart';
