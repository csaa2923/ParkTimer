import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:parktimer/main.dart';
import 'package:parktimer/services/location_service.dart';
import 'package:parktimer/services/navigation_service.dart';
import 'package:parktimer/services/notification_service.dart';
import 'package:parktimer/services/parking_location_store.dart';
import 'package:parktimer/services/parking_session_store.dart';

class _FakeClock {
  _FakeClock(this._now);

  DateTime _now;

  DateTime call() => _now;

  void advance(Duration duration) {
    _now = _now.add(duration);
  }
}

class _FakeLocationService extends LocationService {
  _FakeLocationService({this.shouldSucceed = true});

  final bool shouldSucceed;
  int obtainCallCount = 0;

  @override
  Future<Position> obtainCurrentPosition({
    LocationSettings? locationSettings,
  }) async {
    obtainCallCount += 1;
    if (!shouldSucceed) {
      throw const PermissionDeniedException('denied');
    }

    return Position(
      latitude: 52.52,
      longitude: 13.405,
      timestamp: DateTime(2026, 8, 7, 10),
      accuracy: 5,
      altitude: 0,
      altitudeAccuracy: 0,
      heading: 0,
      headingAccuracy: 0,
      speed: 0,
      speedAccuracy: 0,
    );
  }
}

class _FakeNavigationService extends NavigationService {
  _FakeNavigationService({this.shouldOpen = true})
      : super(
          launchUrlFn: (
            Uri url, {
            LaunchMode mode = LaunchMode.platformDefault,
          }) async =>
              false,
        );

  final bool shouldOpen;
  final List<SavedParkingLocation> openedLocations = <SavedParkingLocation>[];

  @override
  Future<bool> openNavigation(SavedParkingLocation location) async {
    openedLocations.add(location);
    return shouldOpen;
  }
}

class _FakeNotificationService extends NotificationService {
  final List<DateTime> scheduledEndTimes = <DateTime>[];
  int cancelCount = 0;
  int testNotificationCount = 0;

  @override
  Future<void> initialize() async {}

  @override
  Future<void> scheduleParkingNotifications(DateTime endTime) async {
    scheduledEndTimes.add(endTime);
  }

  @override
  Future<void> cancelParkingNotifications() async {
    cancelCount += 1;
  }

  @override
  Future<void> showTestNotification() async {
    testNotificationCount += 1;
  }
}

class _TestStores {
  const _TestStores({
    required this.location,
    required this.session,
  });

  final ParkingLocationStore location;
  final ParkingSessionStore session;
}

Future<_TestStores> _testStores([
  Map<String, Object> values = const <String, Object>{},
]) async {
  SharedPreferences.setMockInitialValues(Map<String, Object>.from(values));
  final preferences = await SharedPreferences.getInstance();
  return _TestStores(
    location: ParkingLocationStore(preferences: preferences),
    session: ParkingSessionStore(preferences: preferences),
  );
}

Future<void> _pumpApp(
  WidgetTester tester, {
  DateTime Function()? now,
  LocationService? locationService,
  ParkingLocationStore? parkingLocationStore,
  ParkingSessionStore? parkingSessionStore,
  NavigationService? navigationService,
  NotificationService? notificationService,
}) async {
  late final ParkingLocationStore locationStore;
  late final ParkingSessionStore sessionStore;

  if (parkingLocationStore != null && parkingSessionStore != null) {
    locationStore = parkingLocationStore;
    sessionStore = parkingSessionStore;
  } else if (parkingLocationStore == null && parkingSessionStore == null) {
    final stores = await _testStores();
    locationStore = stores.location;
    sessionStore = stores.session;
  } else {
    final preferences = await SharedPreferences.getInstance();
    locationStore =
        parkingLocationStore ?? ParkingLocationStore(preferences: preferences);
    sessionStore =
        parkingSessionStore ?? ParkingSessionStore(preferences: preferences);
  }

  await tester.pumpWidget(
    ParkTimerApp(
      now: now ?? DateTime.now,
      locationService: locationService,
      parkingLocationStore: locationStore,
      parkingSessionStore: sessionStore,
      navigationService: navigationService,
      notificationService: notificationService ?? _FakeNotificationService(),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  testWidgets('Start screen shows ParkTimer UI', (WidgetTester tester) async {
    await _pumpApp(tester);

    expect(find.textContaining('ParkTimer'), findsOneWidget);
    expect(find.text('Parkzeit starten'), findsOneWidget);
    expect(find.text('30 Minuten'), findsOneWidget);
    expect(find.text('1 Stunde'), findsOneWidget);
    expect(find.text('2 Stunden'), findsOneWidget);
    expect(find.text('Eigene Zeit'), findsOneWidget);
    expect(find.text('Standort merken'), findsOneWidget);
    expect(find.text('Zum Auto navigieren'), findsNothing);
    expect(find.text('Test-Benachrichtigung'), findsNothing);
    expect(find.text('Timer stoppen'), findsNothing);
  });

  testWidgets('Starting a timer shows end time and countdown',
      (WidgetTester tester) async {
    final clock = _FakeClock(DateTime(2026, 8, 7, 10, 0));
    await _pumpApp(tester, now: clock.call);

    await tester.tap(find.text('30 Minuten'));
    await tester.pumpAndSettle();

    expect(find.text('Parkzeit starten'), findsNothing);
    expect(find.text('Parken bis 10:30'), findsOneWidget);
    expect(find.text('00:30:00'), findsOneWidget);
    expect(find.text('Timer stoppen'), findsOneWidget);

    // Duration buttons stay available while the timer runs.
    expect(find.text('30 Minuten'), findsOneWidget);
    expect(find.text('1 Stunde'), findsOneWidget);
    expect(find.text('2 Stunden'), findsOneWidget);
  });

  testWidgets('Countdown updates every second', (WidgetTester tester) async {
    final clock = _FakeClock(DateTime(2026, 8, 7, 10, 0));
    await _pumpApp(tester, now: clock.call);

    await tester.tap(find.text('1 Stunde'));
    await tester.pump();
    expect(find.text('01:00:00'), findsOneWidget);

    clock.advance(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));

    expect(find.text('00:59:59'), findsOneWidget);
  });

  testWidgets('Starting a new timer replaces the current one',
      (WidgetTester tester) async {
    final clock = _FakeClock(DateTime(2026, 8, 7, 10, 0));
    await _pumpApp(tester, now: clock.call);

    await tester.tap(find.text('30 Minuten'));
    await tester.pump();
    expect(find.text('Parken bis 10:30'), findsOneWidget);

    await tester.tap(find.text('2 Stunden'));
    await tester.pump();

    expect(find.text('Parken bis 12:00'), findsOneWidget);
    expect(find.text('02:00:00'), findsOneWidget);
  });

  testWidgets('Stop button resets the timer UI', (WidgetTester tester) async {
    final clock = _FakeClock(DateTime(2026, 8, 7, 10, 0));
    await _pumpApp(tester, now: clock.call);

    await tester.tap(find.text('30 Minuten'));
    await tester.pump();
    expect(find.text('Timer stoppen'), findsOneWidget);

    await tester.ensureVisible(find.text('Timer stoppen'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Timer stoppen'));
    await tester.pumpAndSettle();

    expect(find.text('Parkzeit starten'), findsOneWidget);
    expect(find.text('Timer stoppen'), findsNothing);
    expect(find.textContaining('Parken bis'), findsNothing);
  });

  testWidgets('Expired timer shows Parkzeit abgelaufen',
      (WidgetTester tester) async {
    final clock = _FakeClock(DateTime(2026, 8, 7, 10, 0));
    await _pumpApp(tester, now: clock.call);

    final state = tester.state<StartScreenState>(find.byType(StartScreen));
    state.startTimer(const Duration(seconds: 2));
    await tester.pumpAndSettle();

    expect(find.text('Parken bis 10:00'), findsOneWidget);
    expect(find.text('00:00:02'), findsOneWidget);

    clock.advance(const Duration(seconds: 2));
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();

    expect(find.text('Parkzeit abgelaufen'), findsOneWidget);
    expect(find.text('Timer stoppen'), findsNothing);
    expect(find.text('00:00:00'), findsNothing);
  });

  test('formatCountdown pads hours minutes and seconds', () {
    expect(formatCountdown(Duration.zero), '00:00:00');
    expect(formatCountdown(const Duration(minutes: 30)), '00:30:00');
    expect(
      formatCountdown(const Duration(hours: 1, minutes: 5, seconds: 9)),
      '01:05:09',
    );
  });

  testWidgets('Eigene Zeit opens custom time sheet', (WidgetTester tester) async {
    await _pumpApp(tester);

    await tester.ensureVisible(find.text('Eigene Zeit'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Eigene Zeit'));
    await tester.pumpAndSettle();

    expect(find.text('Eigene Parkzeit'), findsOneWidget);
    expect(find.text('Stunden'), findsOneWidget);
    expect(find.text('Minuten'), findsOneWidget);
    expect(find.byKey(const Key('custom_time_confirm')), findsOneWidget);
    expect(find.byKey(const Key('custom_time_cancel')), findsOneWidget);
  });

  testWidgets('Custom time starts countdown with selected duration',
      (WidgetTester tester) async {
    final clock = _FakeClock(DateTime(2026, 8, 7, 10, 0));
    await _pumpApp(tester, now: clock.call);

    await tester.ensureVisible(find.text('Eigene Zeit'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Eigene Zeit'));
    await tester.pumpAndSettle();

    // Default is 0h 1m. Set to 1h 15m.
    await tester.tap(find.byKey(const Key('custom_hours_increment')));
    await tester.pump();
    for (var i = 0; i < 14; i++) {
      await tester.tap(find.byKey(const Key('custom_minutes_increment')));
      await tester.pump();
    }

    expect(find.byKey(const Key('custom_hours_value')), findsOneWidget);
    expect(
      tester.widget<Text>(find.byKey(const Key('custom_hours_value'))).data,
      '1',
    );
    expect(
      tester.widget<Text>(find.byKey(const Key('custom_minutes_value'))).data,
      '15',
    );

    await tester.tap(find.byKey(const Key('custom_time_confirm')));
    await tester.pumpAndSettle();

    expect(find.text('Eigene Parkzeit'), findsNothing);
    expect(find.text('Parken bis 11:15'), findsOneWidget);
    expect(find.text('01:15:00'), findsOneWidget);
    expect(find.text('Timer stoppen'), findsOneWidget);
  });

  testWidgets('Custom time cancel keeps running timer unchanged',
      (WidgetTester tester) async {
    final clock = _FakeClock(DateTime(2026, 8, 7, 10, 0));
    await _pumpApp(tester, now: clock.call);

    await tester.tap(find.text('30 Minuten'));
    await tester.pump();
    expect(find.text('Parken bis 10:30'), findsOneWidget);
    expect(find.text('00:30:00'), findsOneWidget);

    await tester.ensureVisible(find.text('Eigene Zeit'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Eigene Zeit'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('custom_hours_increment')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('custom_time_cancel')));
    await tester.pumpAndSettle();

    expect(find.text('Eigene Parkzeit'), findsNothing);
    expect(find.text('Parken bis 10:30'), findsOneWidget);
    expect(find.text('00:30:00'), findsOneWidget);
  });

  testWidgets('Custom time requires at least one minute',
      (WidgetTester tester) async {
    await _pumpApp(tester);

    await tester.ensureVisible(find.text('Eigene Zeit'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Eigene Zeit'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('custom_minutes_decrement')));
    await tester.pump();

    expect(find.text('Mindestens 1 Minute auswählen'), findsOneWidget);

    final confirmButton = tester.widget<ElevatedButton>(
      find.byKey(const Key('custom_time_confirm')),
    );
    expect(confirmButton.onPressed, isNull);

    await tester.tap(find.byKey(const Key('custom_time_confirm')));
    await tester.pumpAndSettle();

    expect(find.text('Eigene Parkzeit'), findsOneWidget);
    expect(find.textContaining('Parken bis'), findsNothing);
  });

  testWidgets('Custom time replaces an already running timer',
      (WidgetTester tester) async {
    final clock = _FakeClock(DateTime(2026, 8, 7, 10, 0));
    await _pumpApp(tester, now: clock.call);

    await tester.tap(find.text('30 Minuten'));
    await tester.pump();
    expect(find.text('Parken bis 10:30'), findsOneWidget);

    await tester.ensureVisible(find.text('Eigene Zeit'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Eigene Zeit'));
    await tester.pumpAndSettle();

    // Default sheet value is 0h 1m; raise hours to get 1h 1m.
    await tester.tap(find.byKey(const Key('custom_hours_increment')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('custom_time_confirm')));
    await tester.pumpAndSettle();

    expect(find.text('Parken bis 11:01'), findsOneWidget);
    expect(find.text('01:01:00'), findsOneWidget);
  });

  testWidgets('Standort merken persists position and updates button',
      (WidgetTester tester) async {
    final clock = _FakeClock(DateTime(2026, 8, 7, 10, 0));
    final locationService = _FakeLocationService();
    final stores = await _testStores();

    await _pumpApp(
      tester,
      now: clock.call,
      locationService: locationService,
      parkingLocationStore: stores.location,
      parkingSessionStore: stores.session,
    );

    expect(find.text('Standort merken'), findsOneWidget);

    await tester.ensureVisible(find.text('Standort merken'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Standort merken'));
    await tester.pumpAndSettle();

    expect(locationService.obtainCallCount, 1);
    expect(find.text('Standort gespeichert'), findsOneWidget);
    expect(find.text('📍 Standort gespeichert'), findsOneWidget);
    expect(find.text('Gespeichert um 10:00'), findsOneWidget);
    expect(find.text('Zum Auto navigieren'), findsOneWidget);
    expect(find.text('Standort merken'), findsNothing);
    expect(find.text('Standort gespeichert ✓'), findsNothing);

    final state = tester.state<StartScreenState>(find.byType(StartScreen));
    expect(state.hasSavedPosition, isTrue);
    expect(state.savedPosition?.latitude, 52.52);
    expect(state.savedPosition?.longitude, 13.405);
    expect(state.savedPosition?.savedAt, DateTime(2026, 8, 7, 10));

    final persisted = await stores.location.load();
    expect(persisted?.latitude, 52.52);
    expect(persisted?.longitude, 13.405);
    expect(persisted?.savedAt, DateTime(2026, 8, 7, 10));
  });

  testWidgets('Standort merken failure keeps original button label',
      (WidgetTester tester) async {
    final locationService = _FakeLocationService(shouldSucceed: false);
    await _pumpApp(tester, locationService: locationService);

    await tester.ensureVisible(find.text('Standort merken'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Standort merken'));
    await tester.pumpAndSettle();

    expect(find.text('Standort merken'), findsOneWidget);
    expect(find.text('📍 Standort gespeichert'), findsNothing);
    expect(
      find.text('Standort konnte nicht gespeichert werden'),
      findsOneWidget,
    );
  });

  testWidgets('Persisted parking location is restored on app start',
      (WidgetTester tester) async {
    final stores = await _testStores(<String, Object>{
      'parking_latitude': 52.52,
      'parking_longitude': 13.405,
      'parking_saved_at': '2026-08-07T10:00:00.000',
    });

    await _pumpApp(
      tester,
      locationService: _FakeLocationService(),
      parkingLocationStore: stores.location,
      parkingSessionStore: stores.session,
    );

    expect(find.text('📍 Standort gespeichert'), findsOneWidget);
    expect(find.text('Gespeichert um 10:00'), findsOneWidget);
    expect(find.text('Zum Auto navigieren'), findsOneWidget);
    expect(find.text('Standort merken'), findsNothing);

    final state = tester.state<StartScreenState>(find.byType(StartScreen));
    expect(state.hasSavedPosition, isTrue);
    expect(state.savedPosition?.latitude, 52.52);
    expect(state.savedPosition?.longitude, 13.405);
  });

  testWidgets('clearSavedLocation removes persisted parking position',
      (WidgetTester tester) async {
    final stores = await _testStores(<String, Object>{
      'parking_latitude': 52.52,
      'parking_longitude': 13.405,
      'parking_saved_at': '2026-08-07T10:00:00.000',
    });

    await _pumpApp(
      tester,
      locationService: _FakeLocationService(),
      parkingLocationStore: stores.location,
      parkingSessionStore: stores.session,
    );
    expect(find.text('📍 Standort gespeichert'), findsOneWidget);
    expect(find.text('Zum Auto navigieren'), findsOneWidget);

    final state = tester.state<StartScreenState>(find.byType(StartScreen));
    await state.clearSavedLocation();
    await tester.pumpAndSettle();

    expect(find.text('Standort merken'), findsOneWidget);
    expect(find.text('📍 Standort gespeichert'), findsNothing);
    expect(find.text('Zum Auto navigieren'), findsNothing);
    expect(await stores.location.load(), isNull);
  });

  testWidgets('Zum Auto navigieren opens saved coordinates',
      (WidgetTester tester) async {
    final navigationService = _FakeNavigationService();
    final stores = await _testStores(<String, Object>{
      'parking_latitude': 52.52,
      'parking_longitude': 13.405,
      'parking_saved_at': '2026-08-07T10:00:00.000',
    });

    await _pumpApp(
      tester,
      locationService: _FakeLocationService(),
      parkingLocationStore: stores.location,
      parkingSessionStore: stores.session,
      navigationService: navigationService,
    );

    await tester.ensureVisible(find.text('Zum Auto navigieren'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Zum Auto navigieren'));
    await tester.pumpAndSettle();

    expect(navigationService.openedLocations, hasLength(1));
    expect(navigationService.openedLocations.single.latitude, 52.52);
    expect(navigationService.openedLocations.single.longitude, 13.405);
    expect(find.text('Karten-App konnte nicht geöffnet werden'), findsNothing);
  });

  testWidgets('Zum Auto navigieren shows snackbar when opening fails',
      (WidgetTester tester) async {
    final navigationService = _FakeNavigationService(shouldOpen: false);
    final stores = await _testStores(<String, Object>{
      'parking_latitude': 52.52,
      'parking_longitude': 13.405,
      'parking_saved_at': '2026-08-07T10:00:00.000',
    });

    await _pumpApp(
      tester,
      locationService: _FakeLocationService(),
      parkingLocationStore: stores.location,
      parkingSessionStore: stores.session,
      navigationService: navigationService,
    );

    await tester.ensureVisible(find.text('Zum Auto navigieren'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Zum Auto navigieren'));
    await tester.pumpAndSettle();

    expect(
      find.text('Karten-App konnte nicht geöffnet werden'),
      findsOneWidget,
    );
  });

  testWidgets('Starting a timer schedules parking notifications',
      (WidgetTester tester) async {
    final clock = _FakeClock(DateTime(2026, 8, 7, 10, 0));
    final notifications = _FakeNotificationService();
    await _pumpApp(
      tester,
      now: clock.call,
      notificationService: notifications,
    );

    await tester.tap(find.text('30 Minuten'));
    await tester.pump();
    await tester.pump();

    expect(notifications.scheduledEndTimes, <DateTime>[
      DateTime(2026, 8, 7, 10, 30),
    ]);
  });

  testWidgets('Replacing a timer schedules notifications for the new end time',
      (WidgetTester tester) async {
    final clock = _FakeClock(DateTime(2026, 8, 7, 10, 0));
    final notifications = _FakeNotificationService();
    await _pumpApp(
      tester,
      now: clock.call,
      notificationService: notifications,
    );

    await tester.tap(find.text('30 Minuten'));
    await tester.pump();
    await tester.tap(find.text('1 Stunde'));
    await tester.pump();
    await tester.pump();

    expect(notifications.scheduledEndTimes, <DateTime>[
      DateTime(2026, 8, 7, 10, 30),
      DateTime(2026, 8, 7, 11, 0),
    ]);
  });

  testWidgets('Stopping a timer cancels parking notifications',
      (WidgetTester tester) async {
    final clock = _FakeClock(DateTime(2026, 8, 7, 10, 0));
    final notifications = _FakeNotificationService();
    await _pumpApp(
      tester,
      now: clock.call,
      notificationService: notifications,
    );

    await tester.tap(find.text('30 Minuten'));
    await tester.pump();

    await tester.ensureVisible(find.text('Timer stoppen'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Timer stoppen'));
    await tester.pump();
    await tester.pump();

    expect(notifications.cancelCount, 1);
  });

  test('ParkingLocationStore save load and clear', () async {
    final stores = await _testStores();
    final location = SavedParkingLocation(
      latitude: 48.137,
      longitude: 11.575,
      savedAt: DateTime(2026, 8, 7, 12, 30),
    );

    await stores.location.save(location);
    final loaded = await stores.location.load();
    expect(loaded?.latitude, 48.137);
    expect(loaded?.longitude, 11.575);
    expect(loaded?.savedAt, DateTime(2026, 8, 7, 12, 30));

    await stores.location.clear();
    expect(await stores.location.load(), isNull);
  });

  test('ParkingSessionStore save load and clear', () async {
    final stores = await _testStores();
    final session = ParkingSession(
      endTime: DateTime(2026, 8, 7, 10, 30),
      startTime: DateTime(2026, 8, 7, 10),
      isActive: true,
    );

    await stores.session.save(session);
    final loaded = await stores.session.load();
    expect(loaded?.endTime, DateTime(2026, 8, 7, 10, 30));
    expect(loaded?.startTime, DateTime(2026, 8, 7, 10));
    expect(loaded?.isActive, isTrue);

    await stores.session.clear();
    expect(await stores.session.load(), isNull);
  });

  testWidgets('Active parking session is restored after app restart',
      (WidgetTester tester) async {
    final notifications = _FakeNotificationService();
    final stores = await _testStores(<String, Object>{
      'parking_session_end_time': '2026-08-07T10:30:00.000',
      'parking_session_start_time': '2026-08-07T10:00:00.000',
      'parking_session_is_active': true,
    });
    final clock = _FakeClock(DateTime(2026, 8, 7, 10, 10));

    await _pumpApp(
      tester,
      now: clock.call,
      parkingLocationStore: stores.location,
      parkingSessionStore: stores.session,
      notificationService: notifications,
    );

    expect(find.text('Parken bis 10:30'), findsOneWidget);
    expect(find.text('00:20:00'), findsOneWidget);
    expect(find.text('Timer stoppen'), findsOneWidget);

    final state = tester.state<StartScreenState>(find.byType(StartScreen));
    expect(state.isRunning, isTrue);
    expect(state.endTime, DateTime(2026, 8, 7, 10, 30));
    expect(state.remaining, const Duration(minutes: 20));
    expect(notifications.scheduledEndTimes, <DateTime>[
      DateTime(2026, 8, 7, 10, 30),
    ]);
  });

  testWidgets('Restored remaining time is calculated from absolute endTime',
      (WidgetTester tester) async {
    final stores = await _testStores(<String, Object>{
      'parking_session_end_time': '2026-08-07T11:00:00.000',
      'parking_session_start_time': '2026-08-07T10:00:00.000',
      'parking_session_is_active': true,
    });
    final clock = _FakeClock(DateTime(2026, 8, 7, 10, 37, 15));

    await _pumpApp(
      tester,
      now: clock.call,
      parkingLocationStore: stores.location,
      parkingSessionStore: stores.session,
    );

    expect(find.text('Parken bis 11:00'), findsOneWidget);
    expect(find.text('00:22:45'), findsOneWidget);
  });

  testWidgets('Expired parking session is recognized on app start',
      (WidgetTester tester) async {
    final stores = await _testStores(<String, Object>{
      'parking_session_end_time': '2026-08-07T10:00:00.000',
      'parking_session_start_time': '2026-08-07T09:30:00.000',
      'parking_session_is_active': true,
    });
    final clock = _FakeClock(DateTime(2026, 8, 7, 10, 5));

    await _pumpApp(
      tester,
      now: clock.call,
      parkingLocationStore: stores.location,
      parkingSessionStore: stores.session,
    );

    expect(find.text('Parkzeit abgelaufen'), findsOneWidget);
    expect(find.text('Timer stoppen'), findsNothing);
    expect(await stores.session.load(), isNull);

    final state = tester.state<StartScreenState>(find.byType(StartScreen));
    expect(state.isExpired, isTrue);
    expect(state.isRunning, isFalse);
  });

  testWidgets('Stopping a timer deletes the parking session',
      (WidgetTester tester) async {
    final clock = _FakeClock(DateTime(2026, 8, 7, 10, 0));
    final stores = await _testStores();
    final notifications = _FakeNotificationService();

    await _pumpApp(
      tester,
      now: clock.call,
      parkingLocationStore: stores.location,
      parkingSessionStore: stores.session,
      notificationService: notifications,
    );

    await tester.tap(find.text('30 Minuten'));
    await tester.pump();
    await tester.pump();

    expect(await stores.session.load(), isNotNull);

    await tester.ensureVisible(find.text('Timer stoppen'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Timer stoppen'));
    await tester.pump();
    await tester.pump();

    expect(await stores.session.load(), isNull);
    expect(notifications.cancelCount, 1);
    expect(find.text('Parkzeit starten'), findsOneWidget);
  });

  testWidgets('Starting a new timer replaces the stored parking session',
      (WidgetTester tester) async {
    final clock = _FakeClock(DateTime(2026, 8, 7, 10, 0));
    final stores = await _testStores();

    await _pumpApp(
      tester,
      now: clock.call,
      parkingLocationStore: stores.location,
      parkingSessionStore: stores.session,
    );

    await tester.tap(find.text('30 Minuten'));
    await tester.pump();
    await tester.pump();

    var session = await stores.session.load();
    expect(session?.endTime, DateTime(2026, 8, 7, 10, 30));
    expect(session?.startTime, DateTime(2026, 8, 7, 10));

    await tester.tap(find.text('1 Stunde'));
    await tester.pump();
    await tester.pump();

    session = await stores.session.load();
    expect(session?.endTime, DateTime(2026, 8, 7, 11, 0));
    expect(session?.startTime, DateTime(2026, 8, 7, 10));
    expect(find.text('Parken bis 11:00'), findsOneWidget);
  });

  test('NavigationService builds Android map fallbacks', () {
    final service = NavigationService(
      platform: TargetPlatform.android,
      isWeb: false,
      launchUrlFn: (
        Uri url, {
        LaunchMode mode = LaunchMode.platformDefault,
      }) async =>
          false,
    );

    final uris = service.buildNavigationUris(
      latitude: 52.52,
      longitude: 13.405,
    );

    expect(uris.map((uri) => uri.toString()).toList(), <String>[
      'google.navigation:q=52.52,13.405',
      'geo:52.52,13.405?q=52.52,13.405',
      'https://www.google.com/maps/search/?api=1&query=52.52,13.405',
    ]);
  });

  test('NavigationService builds iOS map fallbacks', () {
    final service = NavigationService(
      platform: TargetPlatform.iOS,
      isWeb: false,
      launchUrlFn: (
        Uri url, {
        LaunchMode mode = LaunchMode.platformDefault,
      }) async =>
          false,
    );

    final uris = service.buildNavigationUris(
      latitude: 52.52,
      longitude: 13.405,
    );

    expect(uris.map((uri) => uri.toString()).toList(), <String>[
      'maps://?daddr=52.52,13.405',
      'https://maps.apple.com/?daddr=52.52,13.405',
    ]);
  });

  test('NavigationService builds browser fallback for web/windows', () {
    final webService = NavigationService(
      platform: TargetPlatform.android,
      isWeb: true,
      launchUrlFn: (
        Uri url, {
        LaunchMode mode = LaunchMode.platformDefault,
      }) async =>
          false,
    );
    final windowsService = NavigationService(
      platform: TargetPlatform.windows,
      isWeb: false,
      launchUrlFn: (
        Uri url, {
        LaunchMode mode = LaunchMode.platformDefault,
      }) async =>
          false,
    );

    expect(
      webService
          .buildNavigationUris(latitude: 1, longitude: 2)
          .single
          .toString(),
      'https://www.google.com/maps/search/?api=1&query=1.0,2.0',
    );
    expect(
      windowsService
          .buildNavigationUris(latitude: 1, longitude: 2)
          .single
          .toString(),
      'https://www.google.com/maps/search/?api=1&query=1.0,2.0',
    );
  });

  test('NavigationService tries fallbacks until one opens', () async {
    final attempted = <String>[];
    final service = NavigationService(
      platform: TargetPlatform.android,
      isWeb: false,
      launchUrlFn: (
        Uri url, {
        LaunchMode mode = LaunchMode.platformDefault,
      }) async {
        attempted.add(url.toString());
        return url.scheme == 'https';
      },
    );

    final opened = await service.openNavigation(
      SavedParkingLocation(
        latitude: 52.52,
        longitude: 13.405,
        savedAt: DateTime(2026, 8, 7),
      ),
    );

    expect(opened, isTrue);
    expect(attempted, <String>[
      'google.navigation:q=52.52,13.405',
      'geo:52.52,13.405?q=52.52,13.405',
      'https://www.google.com/maps/search/?api=1&query=52.52,13.405',
    ]);
  });

  test('planParkingNotifications schedules 10, 5 and expiry for long timers', () {
    final now = DateTime(2026, 8, 7, 10);
    final endTime = now.add(const Duration(minutes: 30));

    final planned = planParkingNotifications(endTime: endTime, now: now);

    expect(planned.map((item) => item.id).toList(), <int>[
      ParkingNotificationIds.tenMinutes,
      ParkingNotificationIds.fiveMinutes,
      ParkingNotificationIds.expired,
    ]);
    expect(planned[0].scheduledAt, DateTime(2026, 8, 7, 10, 20));
    expect(planned[0].title, 'ParkTimer');
    expect(planned[0].body, 'Deine Parkzeit endet in 10 Minuten.');
    expect(planned[1].scheduledAt, DateTime(2026, 8, 7, 10, 25));
    expect(planned[1].body, 'Deine Parkzeit endet in 5 Minuten.');
    expect(planned[2].scheduledAt, endTime);
    expect(planned[2].title, 'Parkzeit abgelaufen');
    expect(planned[2].body, 'Deine Parkzeit ist jetzt abgelaufen.');
  });

  test('planParkingNotifications skips past reminders for short timers', () {
    final now = DateTime(2026, 8, 7, 10);
    final endTime = now.add(const Duration(minutes: 7));

    final planned = planParkingNotifications(endTime: endTime, now: now);

    expect(planned.map((item) => item.id).toList(), <int>[
      ParkingNotificationIds.fiveMinutes,
      ParkingNotificationIds.expired,
    ]);
    expect(planned.first.scheduledAt, DateTime(2026, 8, 7, 10, 2));
  });

  test('planParkingNotifications keeps only expiry under five minutes', () {
    final now = DateTime(2026, 8, 7, 10);
    final endTime = now.add(const Duration(minutes: 3));

    final planned = planParkingNotifications(endTime: endTime, now: now);

    expect(planned, hasLength(1));
    expect(planned.single.id, ParkingNotificationIds.expired);
    expect(planned.single.scheduledAt, endTime);
  });

  test('parkingNotificationDetails uses the dedicated parking channel', () {
    final details = parkingNotificationDetails();
    final android = details.android!;

    expect(android.channelId, ParkingNotificationChannel.id);
    expect(android.channelName, ParkingNotificationChannel.name);
    expect(
      android.channelDescription,
      ParkingNotificationChannel.description,
    );
    expect(android.importance, Importance.high);
    expect(android.priority, Priority.high);
    expect(ParkingNotificationChannel.id, 'parktimer_parking');
    expect(ParkingNotificationChannel.name, 'Parkzeiten');
  });

  testWidgets('Test notification button triggers showTestNotification',
      (tester) async {
    final notifications = _FakeNotificationService();

    await _pumpApp(
      tester,
      notificationService: notifications,
    );

    final button = find.byKey(const Key('test_notification_button'));
    await tester.ensureVisible(button);
    await tester.pumpAndSettle();
    await tester.tap(button);
    await tester.pump();

    expect(notifications.testNotificationCount, 1);
    expect(find.text('Benachrichtigung testen'), findsOneWidget);
  });
}
