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
  static const int test = 1099;

  static const List<int> all = <int>[
    tenMinutes,
    fiveMinutes,
    expired,
  ];
}

/// Android notification channel used for all parking reminders.
abstract final class ParkingNotificationChannel {
  static const String id = 'parktimer_parking';
  static const String name = 'Parkzeiten';
  static const String description = 'Erinnerungen für aktive Parkzeiten';
}

/// Shared Android details for every ParkTimer parking notification.
NotificationDetails parkingNotificationDetails() {
  return const NotificationDetails(
    android: AndroidNotificationDetails(
      ParkingNotificationChannel.id,
      ParkingNotificationChannel.name,
      channelDescription: ParkingNotificationChannel.description,
      importance: Importance.high,
      priority: Priority.high,
    ),
  );
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

  AndroidFlutterLocalNotificationsPlugin? get _androidPlugin => _plugin
      .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();

  /// Initializes the plugin, timezone data, Android channel and permissions.
  Future<void> initialize() async {
    if (_initialized) {
      return;
    }

    try {
      await _configureLocalTimeZone();

      const androidSettings =
          AndroidInitializationSettings('@mipmap/ic_launcher');
      const settings = InitializationSettings(android: androidSettings);

      if (_isAndroid) {
        await _plugin.initialize(settings: settings);
        await _ensureParkingNotificationChannel();
        await requestPermissions();
      }

      _initialized = true;
      _debugLog('NotificationService initialized');
    } catch (error, stackTrace) {
      _debugLog(
        'NotificationService.initialize failed: $error\n$stackTrace',
      );
      rethrow;
    }
  }

  /// Requests notification permissions where required.
  ///
  /// - Android 13+: [POST_NOTIFICATIONS] only when not already granted
  /// - Exact alarms only when [canScheduleExactNotifications] is explicitly false
  Future<bool> requestPermissions() async {
    if (!_isAndroid) {
      return false;
    }

    final androidImplementation = _androidPlugin;
    if (androidImplementation == null) {
      return false;
    }

    var notificationsAllowed =
        await androidImplementation.areNotificationsEnabled() ?? true;

    if (!notificationsAllowed) {
      final granted =
          await androidImplementation.requestNotificationsPermission();
      notificationsAllowed = granted ?? false;
      _debugLog('POST_NOTIFICATIONS granted=$granted');
    }

    final canExact =
        await androidImplementation.canScheduleExactNotifications();
    if (canExact == false) {
      final granted =
          await androidImplementation.requestExactAlarmsPermission();
      _debugLog('SCHEDULE_EXACT_ALARM granted=$granted');
    } else {
      _debugLog('Exact alarms available (canScheduleExactNotifications=$canExact)');
    }

    return notificationsAllowed;
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
    final details = parkingNotificationDetails();
    final scheduleMode = await _resolveAndroidScheduleMode();

    _debugLog(
      'Scheduling ${planned.length} parking notification(s) '
      'with mode=$scheduleMode for endTime=$endTime',
    );

    for (final notification in planned) {
      final scheduledDate = tz.TZDateTime.from(
        notification.scheduledAt,
        tz.local,
      );

      try {
        await _plugin.zonedSchedule(
          id: notification.id,
          title: notification.title,
          body: notification.body,
          scheduledDate: scheduledDate,
          notificationDetails: details,
          androidScheduleMode: scheduleMode,
        );
        _debugLog(
          'Scheduled id=${notification.id} at $scheduledDate '
          '(${notification.body})',
        );
      } catch (error, stackTrace) {
        _debugLog(
          'Failed to schedule id=${notification.id} at $scheduledDate: '
          '$error\n$stackTrace',
        );
        rethrow;
      }
    }
  }

  /// Cancels the fixed parking-timer notification IDs.
  Future<void> cancelParkingNotifications() async {
    for (final id in ParkingNotificationIds.all) {
      await _plugin.cancel(id: id);
    }
  }

  /// Shows an immediate local test notification on [ParkingNotificationChannel].
  Future<void> showTestNotification() async {
    if (!_isAndroid) {
      return;
    }

    if (!_initialized) {
      await initialize();
    } else {
      await _ensureParkingNotificationChannel();
    }

    try {
      await _plugin.show(
        id: ParkingNotificationIds.test,
        title: 'ParkTimer',
        body: 'Benachrichtigungen funktionieren.',
        notificationDetails: parkingNotificationDetails(),
      );
      _debugLog('showTestNotification displayed');
    } catch (error, stackTrace) {
      _debugLog('showTestNotification failed: $error\n$stackTrace');
      rethrow;
    }
  }

  Future<void> _ensureParkingNotificationChannel() async {
    final androidImplementation = _androidPlugin;
    if (androidImplementation == null) {
      return;
    }

    const channel = AndroidNotificationChannel(
      ParkingNotificationChannel.id,
      ParkingNotificationChannel.name,
      description: ParkingNotificationChannel.description,
      importance: Importance.high,
    );

    await androidImplementation.createNotificationChannel(channel);
    _debugLog('Ensured notification channel ${ParkingNotificationChannel.id}');
  }

  /// Prefers exact alarms when permitted; otherwise falls back so reminders
  /// are still delivered (possibly a few minutes late).
  Future<AndroidScheduleMode> _resolveAndroidScheduleMode() async {
    final androidImplementation = _androidPlugin;
    if (androidImplementation == null) {
      return AndroidScheduleMode.exactAllowWhileIdle;
    }

    final canExact =
        await androidImplementation.canScheduleExactNotifications();
    if (canExact == false) {
      _debugLog(
        'Exact alarms not permitted; using inexactAllowWhileIdle fallback',
      );
      return AndroidScheduleMode.inexactAllowWhileIdle;
    }

    return AndroidScheduleMode.exactAllowWhileIdle;
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
        _debugLog('Timezone set to ${timeZoneInfo.identifier}');
      } else {
        tz.setLocalLocation(tz.UTC);
      }
    } catch (error, stackTrace) {
      _debugLog(
        'Timezone lookup failed, falling back to UTC: $error\n$stackTrace',
      );
      tz.setLocalLocation(tz.UTC);
    }

    _timeZoneConfigured = true;
  }

  void _debugLog(String message) {
    if (kDebugMode) {
      debugPrint('[ParkTimer/Notifications] $message');
    }
  }

  bool get _isAndroid =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
}
