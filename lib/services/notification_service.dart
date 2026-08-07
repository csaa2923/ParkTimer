import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Central entry point for local notifications.
///
/// Currently prepared for Android only. Scheduled notifications are not
/// implemented yet.
class NotificationService {
  NotificationService._();

  static final NotificationService instance = NotificationService._();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  bool _initialized = false;

  bool get isInitialized => _initialized;

  /// Initializes the plugin and requests Android 13+ notification permissions.
  Future<void> initialize() async {
    if (_initialized) {
      return;
    }

    const androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const settings = InitializationSettings(android: androidSettings);

    if (_isAndroid) {
      await _plugin.initialize(settings: settings);
      await requestPermissions();
    }

    _initialized = true;
  }

  /// Requests notification permissions where required (Android 13+).
  Future<bool> requestPermissions() async {
    if (!_isAndroid) {
      return false;
    }

    final androidImplementation = _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();

    final granted =
        await androidImplementation?.requestNotificationsPermission();
    return granted ?? false;
  }

  /// Shows an immediate local test notification.
  Future<void> showTestNotification() async {
    if (!_isAndroid) {
      return;
    }

    const androidDetails = AndroidNotificationDetails(
      'parktimer_general',
      'ParkTimer',
      channelDescription: 'Allgemeine ParkTimer-Benachrichtigungen',
      importance: Importance.defaultImportance,
      priority: Priority.defaultPriority,
    );

    const details = NotificationDetails(android: androidDetails);

    await _plugin.show(
      id: 0,
      title: 'ParkTimer',
      body: 'Benachrichtigungen funktionieren.',
      notificationDetails: details,
    );
  }

  bool get _isAndroid =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
}
