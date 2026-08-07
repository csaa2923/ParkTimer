import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:parktimer/main.dart';

class _FakeClock {
  _FakeClock(this._now);

  DateTime _now;

  DateTime call() => _now;

  void advance(Duration duration) {
    _now = _now.add(duration);
  }
}

void main() {
  testWidgets('Start screen shows ParkTimer UI', (WidgetTester tester) async {
    await tester.pumpWidget(const ParkTimerApp());

    expect(find.textContaining('ParkTimer'), findsOneWidget);
    expect(find.text('Parkzeit starten'), findsOneWidget);
    expect(find.text('30 Minuten'), findsOneWidget);
    expect(find.text('1 Stunde'), findsOneWidget);
    expect(find.text('2 Stunden'), findsOneWidget);
    expect(find.text('Eigene Zeit'), findsOneWidget);
    expect(find.text('Standort merken'), findsOneWidget);
    expect(find.text('Timer stoppen'), findsNothing);
  });

  testWidgets('Starting a timer shows end time and countdown',
      (WidgetTester tester) async {
    final clock = _FakeClock(DateTime(2026, 8, 7, 10, 0));
    await tester.pumpWidget(ParkTimerApp(now: clock.call));

    await tester.tap(find.text('30 Minuten'));
    await tester.pump();

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
    await tester.pumpWidget(ParkTimerApp(now: clock.call));

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
    await tester.pumpWidget(ParkTimerApp(now: clock.call));

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
    await tester.pumpWidget(ParkTimerApp(now: clock.call));

    await tester.tap(find.text('30 Minuten'));
    await tester.pump();
    expect(find.text('Timer stoppen'), findsOneWidget);

    await tester.ensureVisible(find.text('Timer stoppen'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Timer stoppen'));
    await tester.pump();

    expect(find.text('Parkzeit starten'), findsOneWidget);
    expect(find.text('Timer stoppen'), findsNothing);
    expect(find.textContaining('Parken bis'), findsNothing);
  });

  testWidgets('Expired timer shows Parkzeit abgelaufen',
      (WidgetTester tester) async {
    final clock = _FakeClock(DateTime(2026, 8, 7, 10, 0));
    await tester.pumpWidget(ParkTimerApp(now: clock.call));

    final state = tester.state<StartScreenState>(find.byType(StartScreen));
    state.startTimer(const Duration(seconds: 2));
    await tester.pump();

    expect(find.text('Parken bis 10:00'), findsOneWidget);
    expect(find.text('00:00:02'), findsOneWidget);

    clock.advance(const Duration(seconds: 2));
    await tester.pump(const Duration(seconds: 2));

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
    await tester.pumpWidget(const ParkTimerApp());

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
    await tester.pumpWidget(ParkTimerApp(now: clock.call));

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
    await tester.pumpWidget(ParkTimerApp(now: clock.call));

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
    await tester.pumpWidget(const ParkTimerApp());

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
    await tester.pumpWidget(ParkTimerApp(now: clock.call));

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
}
