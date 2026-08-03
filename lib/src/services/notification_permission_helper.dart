import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';

/// Ensures POST_NOTIFICATIONS permission is granted on Android 13+ so
/// media notifications can be shown.
/// On desktop platforms (Windows/macOS/Linux), notifications don't require runtime permissions.
class NotificationPermissionHelper {
  NotificationPermissionHelper._();

  static Future<void> requestNotificationsIfNeeded() async {
    // Only Android requires runtime notification permissions
    if (!kIsWeb && Platform.isAndroid) {
      // On Android 13+ a runtime permission is required for notifications
      final status = await Permission.notification.status;
      if (!status.isGranted) {
        await Permission.notification.request();
      }
    }
    // Windows/macOS/Linux don't need runtime notification permissions
  }
}
