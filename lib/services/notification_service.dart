import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

/// Fixed IDs for parking-timer notifications.
abstract final class ParkingNotificationIds {
  static const int tenMinutes = 1001;
  static const int fiveMinutes = 1002;
  static const int expired = 1003;

  static const List<int> all = <int>[
    tenMinutes,
    fiveMinutes,
    expired,
  ];
}

/// A planned parking notification that should be scheduled if still in the future.
class ScheduledParkingNotification {
  const ScheduledParkingNotification({
    required this.id,
    required this.scheduledAt,
    required this.title,
    required this.body,
  });

  final int id;
  final DateTime scheduledAt;
  final String title;
  final String body;
}

/// Builds the parking reminders that still lie in the future.
List<ScheduledParkingNotification> planParkingNotifications({
  required DateTime endTime,
  required DateTime now,
}) {
  final candidates = <ScheduledParkingNotification>[
    ScheduledParkingNotification(
      id: ParkingNotificationIds.tenMinutes,
      scheduledAt: endTime.subtract(const Duration(minutes: 10)),
      title: 'ParkTimer',
      body: 'Deine Parkzeit endet in 10 Minuten.',
    ),
    ScheduledParkingNotification(
      id: ParkingNotificationIds.fiveMinutes,
      scheduledAt: endTime.subtract(const Duration(minutes: 5)),
      title: 'ParkTimer',
      body: 'Deine Parkzeit endet in 5 Minuten.',
    ),
    ScheduledParkingNotification(
      id: ParkingNotificationIds.expired,
      scheduledAt: endTime,
      title: 'Parkzeit abgelaufen',
      body: 'Deine Parkzeit ist jetzt abgelaufen.',
    ),
  ];

  return candidates
      .where((notification) => notification.scheduledAt.isAfter(now))
      .toList(growable: false);
}

/// Central entry point for local notifications.
class NotificationService {
  NotificationService({
    FlutterLocalNotificationsPlugin? plugin,
    DateTime Function()? now,
  })  : _plugin = plugin ?? FlutterLocalNotificationsPlugin(),
        _now = now ?? DateTime.now;

  static final NotificationService instance = NotificationService();

  final FlutterLocalNotificationsPlugin _plugin;
  final DateTime Function() _now;

  bool _initialized = false;
  bool _timeZoneConfigured = false;

  bool get isInitialized => _initialized;

  /// Initializes the plugin, timezone data and Android 13+ permissions.
  Future<void> initialize() async {
    if (_initialized) {
      return;
    }

    await _configureLocalTimeZone();

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
    await androidImplementation?.requestExactAlarmsPermission();
    return granted ?? false;
  }

  /// Cancels all previously scheduled parking notifications, then schedules
  /// future reminders for [endTime].
  Future<void> scheduleParkingNotifications(DateTime endTime) async {
    await cancelParkingNotifications();

    if (!_isAndroid) {
      return;
    }

    if (!_initialized) {
      await initialize();
    }

    final planned = planParkingNotifications(
      endTime: endTime,
      now: _now(),
    );

    const details = NotificationDetails(
      android: AndroidNotificationDetails(
        'parktimer_parking',
        'Parkzeiten',
        channelDescription: 'Erinnerungen für aktive Parkzeiten',
        importance: Importance.high,
        priority: Priority.high,
      ),
    );

    for (final notification in planned) {
      final scheduledDate = tz.TZDateTime.from(
        notification.scheduledAt,
        tz.local,
      );

      await _plugin.zonedSchedule(
        id: notification.id,
        title: notification.title,
        body: notification.body,
        scheduledDate: scheduledDate,
        notificationDetails: details,
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      );
    }
  }

  /// Cancels the fixed parking-timer notification IDs.
  Future<void> cancelParkingNotifications() async {
    for (final id in ParkingNotificationIds.all) {
      await _plugin.cancel(id: id);
    }
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

  Future<void> _configureLocalTimeZone() async {
    if (_timeZoneConfigured) {
      return;
    }

    tzdata.initializeTimeZones();

    try {
      if (!kIsWeb) {
        final timeZoneInfo = await FlutterTimezone.getLocalTimezone();
        tz.setLocalLocation(tz.getLocation(timeZoneInfo.identifier));
      } else {
        tz.setLocalLocation(tz.UTC);
      }
    } catch (_) {
      tz.setLocalLocation(tz.UTC);
    }

    _timeZoneConfigured = true;
  }

  bool get _isAndroid =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
}
