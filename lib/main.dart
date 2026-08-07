import 'dart:async';

import 'package:flutter/material.dart';

import 'package:parktimer/services/notification_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await NotificationService.instance.initialize();
  runApp(const ParkTimerApp());
}

class ParkTimerApp extends StatelessWidget {
  const ParkTimerApp({
    super.key,
    this.now = DateTime.now,
  });

  /// Injectable clock for tests; defaults to wall clock time.
  final DateTime Function() now;

  static const Color primaryBlue = Color(0xFF1E3A8A);
  static const Color accentGreen = Color(0xFF22C55E);
  static const Color backgroundGray = Color(0xFFF5F7FA);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ParkTimer',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: primaryBlue,
          primary: primaryBlue,
          secondary: accentGreen,
          surface: backgroundGray,
          brightness: Brightness.light,
        ),
        scaffoldBackgroundColor: backgroundGray,
      ),
      home: StartScreen(now: now),
    );
  }
}

class StartScreen extends StatefulWidget {
  const StartScreen({
    super.key,
    this.now = DateTime.now,
  });

  final DateTime Function() now;

  @override
  State<StartScreen> createState() => StartScreenState();
}

class StartScreenState extends State<StartScreen> {
  Timer? _ticker;
  DateTime? _endTime;
  Duration _remaining = Duration.zero;
  bool _isRunning = false;
  bool _isExpired = false;

  bool get isRunning => _isRunning;
  bool get isExpired => _isExpired;
  Duration get remaining => _remaining;
  DateTime? get endTime => _endTime;

  void startTimer(Duration duration) {
    _ticker?.cancel();

    final end = widget.now().add(duration);
    setState(() {
      _endTime = end;
      _remaining = duration;
      _isRunning = true;
      _isExpired = false;
    });

    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _onTick());
  }

  void stopTimer() {
    _ticker?.cancel();
    _ticker = null;

    setState(() {
      _endTime = null;
      _remaining = Duration.zero;
      _isRunning = false;
      _isExpired = false;
    });
  }

  Future<void> openCustomTimePicker() async {
    final duration = await showCustomTimeSheet(context);
    if (!mounted || duration == null) {
      return;
    }
    startTimer(duration);
  }

  Future<void> _onTestNotificationPressed() async {
    await NotificationService.instance.requestPermissions();
    await NotificationService.instance.showTestNotification();
  }

  void _onTick() {
    final end = _endTime;
    if (end == null) {
      return;
    }

    final remaining = end.difference(widget.now());
    if (remaining <= Duration.zero) {
      _ticker?.cancel();
      _ticker = null;

      setState(() {
        _remaining = Duration.zero;
        _isRunning = false;
        _isExpired = true;
      });
      return;
    }

    setState(() {
      _remaining = remaining;
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight: constraints.maxHeight - 48,
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      children: [
                        const SizedBox(height: 12),
                        Text(
                          '🚗 ParkTimer',
                          style: Theme.of(context)
                              .textTheme
                              .headlineMedium
                              ?.copyWith(
                                color: ParkTimerApp.primaryBlue,
                                fontWeight: FontWeight.w700,
                                letterSpacing: -0.5,
                              ),
                        ),
                        const SizedBox(height: 40),
                        Container(
                          width: 140,
                          height: 140,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: ParkTimerApp.primaryBlue
                                    .withValues(alpha: 0.12),
                                blurRadius: 28,
                                offset: const Offset(0, 12),
                              ),
                            ],
                          ),
                          child: const Icon(
                            Icons.local_parking_rounded,
                            size: 72,
                            color: ParkTimerApp.primaryBlue,
                          ),
                        ),
                        const SizedBox(height: 28),
                        _StatusSection(
                          isRunning: _isRunning,
                          isExpired: _isExpired,
                          endTime: _endTime,
                          remaining: _remaining,
                        ),
                        const SizedBox(height: 36),
                        DurationButton(
                          label: '30 Minuten',
                          onPressed: () =>
                              startTimer(const Duration(minutes: 30)),
                        ),
                        const SizedBox(height: 16),
                        DurationButton(
                          label: '1 Stunde',
                          onPressed: () =>
                              startTimer(const Duration(hours: 1)),
                        ),
                        const SizedBox(height: 16),
                        DurationButton(
                          label: '2 Stunden',
                          onPressed: () =>
                              startTimer(const Duration(hours: 2)),
                        ),
                        const SizedBox(height: 16),
                        DurationButton(
                          label: 'Eigene Zeit',
                          isAccent: true,
                          onPressed: openCustomTimePicker,
                        ),
                        if (_isRunning) ...[
                          const SizedBox(height: 16),
                          StopTimerButton(onPressed: stopTimer),
                        ],
                      ],
                    ),
                    Padding(
                      padding: const EdgeInsets.only(top: 32, bottom: 8),
                      child: Column(
                        children: [
                          TextButton(
                            onPressed: _onTestNotificationPressed,
                            style: TextButton.styleFrom(
                              foregroundColor: const Color(0xFF9CA3AF),
                              textStyle: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            child: const Text('Test-Benachrichtigung'),
                          ),
                          const SizedBox(height: 4),
                          const LocationButton(),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _StatusSection extends StatelessWidget {
  const _StatusSection({
    required this.isRunning,
    required this.isExpired,
    required this.endTime,
    required this.remaining,
  });

  final bool isRunning;
  final bool isExpired;
  final DateTime? endTime;
  final Duration remaining;

  @override
  Widget build(BuildContext context) {
    final titleStyle = Theme.of(context).textTheme.titleLarge?.copyWith(
          color: ParkTimerApp.primaryBlue,
          fontWeight: FontWeight.w600,
        );

    if (isExpired) {
      return Text(
        'Parkzeit abgelaufen',
        textAlign: TextAlign.center,
        style: titleStyle?.copyWith(
          color: const Color(0xFFDC2626),
          fontWeight: FontWeight.w700,
        ),
      );
    }

    if (isRunning && endTime != null) {
      return Column(
        children: [
          Text(
            'Parken bis ${formatClockTime(endTime!)}',
            textAlign: TextAlign.center,
            style: titleStyle,
          ),
          const SizedBox(height: 12),
          Text(
            formatCountdown(remaining),
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.displaySmall?.copyWith(
                  color: ParkTimerApp.primaryBlue,
                  fontWeight: FontWeight.w700,
                  fontFeatures: const [FontFeature.tabularFigures()],
                  letterSpacing: 1,
                ),
          ),
        ],
      );
    }

    return Text(
      'Parkzeit starten',
      style: titleStyle,
    );
  }
}

Future<Duration?> showCustomTimeSheet(BuildContext context) {
  return showModalBottomSheet<Duration>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    builder: (context) => const CustomTimeSheet(),
  );
}

class CustomTimeSheet extends StatefulWidget {
  const CustomTimeSheet({super.key});

  @override
  State<CustomTimeSheet> createState() => CustomTimeSheetState();
}

class CustomTimeSheetState extends State<CustomTimeSheet> {
  static const int maxHours = 12;
  static const int maxMinutes = 59;

  int hours = 0;
  int minutes = 1;

  bool get isValid => hours > 0 || minutes > 0;

  Duration get selectedDuration => Duration(hours: hours, minutes: minutes);

  void setHours(int value) {
    setState(() {
      hours = value.clamp(0, maxHours);
    });
  }

  void setMinutes(int value) {
    setState(() {
      minutes = value.clamp(0, maxMinutes);
    });
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;

    return Padding(
      padding: EdgeInsets.fromLTRB(24, 16, 24, 24 + bottomInset),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 44,
            height: 5,
            decoration: BoxDecoration(
              color: const Color(0xFFD1D5DB),
              borderRadius: BorderRadius.circular(999),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            'Eigene Parkzeit',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  color: ParkTimerApp.primaryBlue,
                  fontWeight: FontWeight.w700,
                ),
          ),
          const SizedBox(height: 8),
          Text(
            'Stunden und Minuten wählen',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: const Color(0xFF6B7280),
                ),
          ),
          const SizedBox(height: 28),
          Row(
            children: [
              Expanded(
                child: _TimeUnitPicker(
                  label: 'Stunden',
                  value: hours,
                  incrementKey: const Key('custom_hours_increment'),
                  decrementKey: const Key('custom_hours_decrement'),
                  valueKey: const Key('custom_hours_value'),
                  onIncrement: () => setHours(hours + 1),
                  onDecrement: () => setHours(hours - 1),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _TimeUnitPicker(
                  label: 'Minuten',
                  value: minutes,
                  incrementKey: const Key('custom_minutes_increment'),
                  decrementKey: const Key('custom_minutes_decrement'),
                  valueKey: const Key('custom_minutes_value'),
                  onIncrement: () => setMinutes(minutes + 1),
                  onDecrement: () => setMinutes(minutes - 1),
                ),
              ),
            ],
          ),
          if (!isValid) ...[
            const SizedBox(height: 16),
            Text(
              'Mindestens 1 Minute auswählen',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: const Color(0xFFDC2626),
                    fontWeight: FontWeight.w600,
                  ),
            ),
          ],
          const SizedBox(height: 28),
          SizedBox(
            width: double.infinity,
            height: 60,
            child: ElevatedButton(
              key: const Key('custom_time_confirm'),
              onPressed: isValid
                  ? () => Navigator.of(context).pop(selectedDuration)
                  : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: ParkTimerApp.accentGreen,
                disabledBackgroundColor:
                    ParkTimerApp.accentGreen.withValues(alpha: 0.4),
                foregroundColor: Colors.white,
                disabledForegroundColor: Colors.white70,
                elevation: 4,
                shadowColor: ParkTimerApp.accentGreen.withValues(alpha: 0.4),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18),
                ),
                textStyle: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
              ),
              child: const Text('Parkzeit starten'),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: TextButton(
              key: const Key('custom_time_cancel'),
              onPressed: () => Navigator.of(context).pop(),
              style: TextButton.styleFrom(
                foregroundColor: const Color(0xFF6B7280),
                textStyle: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              child: const Text('Abbrechen'),
            ),
          ),
        ],
      ),
    );
  }
}

class _TimeUnitPicker extends StatelessWidget {
  const _TimeUnitPicker({
    required this.label,
    required this.value,
    required this.onIncrement,
    required this.onDecrement,
    required this.incrementKey,
    required this.decrementKey,
    required this.valueKey,
  });

  final String label;
  final int value;
  final VoidCallback onIncrement;
  final VoidCallback onDecrement;
  final Key incrementKey;
  final Key decrementKey;
  final Key valueKey;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
      decoration: BoxDecoration(
        color: ParkTimerApp.backgroundGray,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        children: [
          Text(
            label,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: ParkTimerApp.primaryBlue,
                  fontWeight: FontWeight.w600,
                ),
          ),
          const SizedBox(height: 8),
          IconButton(
            key: incrementKey,
            onPressed: onIncrement,
            iconSize: 32,
            style: IconButton.styleFrom(
              foregroundColor: ParkTimerApp.primaryBlue,
              minimumSize: const Size(56, 56),
            ),
            icon: const Icon(Icons.keyboard_arrow_up_rounded),
          ),
          Text(
            '$value',
            key: valueKey,
            style: Theme.of(context).textTheme.displaySmall?.copyWith(
                  color: ParkTimerApp.primaryBlue,
                  fontWeight: FontWeight.w700,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
          ),
          IconButton(
            key: decrementKey,
            onPressed: onDecrement,
            iconSize: 32,
            style: IconButton.styleFrom(
              foregroundColor: ParkTimerApp.primaryBlue,
              minimumSize: const Size(56, 56),
            ),
            icon: const Icon(Icons.keyboard_arrow_down_rounded),
          ),
        ],
      ),
    );
  }
}

class DurationButton extends StatelessWidget {
  const DurationButton({
    super.key,
    required this.label,
    this.onPressed,
    this.isAccent = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool isAccent;

  @override
  Widget build(BuildContext context) {
    final backgroundColor =
        isAccent ? ParkTimerApp.accentGreen : ParkTimerApp.primaryBlue;

    return SizedBox(
      width: double.infinity,
      height: 60,
      child: ElevatedButton(
        onPressed: onPressed ?? () {},
        style: ElevatedButton.styleFrom(
          backgroundColor: backgroundColor,
          foregroundColor: Colors.white,
          elevation: 4,
          shadowColor: backgroundColor.withValues(alpha: 0.4),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          textStyle: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.2,
          ),
        ),
        child: Text(label),
      ),
    );
  }
}

class StopTimerButton extends StatelessWidget {
  const StopTimerButton({super.key, required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 56,
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFFDC2626),
          foregroundColor: Colors.white,
          elevation: 3,
          shadowColor: const Color(0xFFDC2626).withValues(alpha: 0.35),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          textStyle: const TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w600,
          ),
        ),
        child: const Text('Timer stoppen'),
      ),
    );
  }
}

class LocationButton extends StatelessWidget {
  const LocationButton({super.key});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 56,
      child: ElevatedButton.icon(
        onPressed: () {},
        icon: const Icon(Icons.location_on_outlined, size: 22),
        label: const Text('Standort merken'),
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFFE5E7EB),
          foregroundColor: const Color(0xFF4B5563),
          elevation: 2,
          shadowColor: Colors.black26,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          textStyle: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

String formatClockTime(DateTime time) {
  final hour = time.hour.toString().padLeft(2, '0');
  final minute = time.minute.toString().padLeft(2, '0');
  return '$hour:$minute';
}

String formatCountdown(Duration duration) {
  final hours = duration.inHours.toString().padLeft(2, '0');
  final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
  final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
  return '$hours:$minutes:$seconds';
}
