import 'dart:async';

import 'package:flutter/material.dart';

import 'package:parktimer/services/location_service.dart';
import 'package:parktimer/services/navigation_service.dart';
import 'package:parktimer/services/notification_service.dart';
import 'package:parktimer/services/parking_location_store.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await NotificationService.instance.initialize();
  runApp(const ParkTimerApp());
}

class ParkTimerApp extends StatelessWidget {
  const ParkTimerApp({
    super.key,
    this.now = DateTime.now,
    this.locationService,
    this.parkingLocationStore,
    this.navigationService,
    this.notificationService,
  });

  /// Injectable clock for tests; defaults to wall clock time.
  final DateTime Function() now;

  /// Injectable location service for tests; defaults to the shared instance.
  final LocationService? locationService;

  /// Injectable parking location store for tests; defaults to the shared instance.
  final ParkingLocationStore? parkingLocationStore;

  /// Injectable navigation service for tests; defaults to the shared instance.
  final NavigationService? navigationService;

  /// Injectable notification service for tests; defaults to the shared instance.
  final NotificationService? notificationService;

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
      home: StartScreen(
        now: now,
        locationService: locationService ?? LocationService.instance,
        parkingLocationStore:
            parkingLocationStore ?? ParkingLocationStore.instance,
        navigationService: navigationService ?? NavigationService.instance,
        notificationService:
            notificationService ?? NotificationService.instance,
      ),
    );
  }
}

class StartScreen extends StatefulWidget {
  const StartScreen({
    super.key,
    this.now = DateTime.now,
    required this.locationService,
    required this.parkingLocationStore,
    required this.navigationService,
    required this.notificationService,
  });

  final DateTime Function() now;
  final LocationService locationService;
  final ParkingLocationStore parkingLocationStore;
  final NavigationService navigationService;
  final NotificationService notificationService;

  @override
  State<StartScreen> createState() => StartScreenState();
}

class StartScreenState extends State<StartScreen> {
  Timer? _ticker;
  DateTime? _endTime;
  Duration _remaining = Duration.zero;
  bool _isRunning = false;
  bool _isExpired = false;
  SavedParkingLocation? _savedLocation;
  bool _isSavingLocation = false;

  bool get isRunning => _isRunning;
  bool get isExpired => _isExpired;
  Duration get remaining => _remaining;
  DateTime? get endTime => _endTime;
  SavedParkingLocation? get savedPosition => _savedLocation;
  bool get hasSavedPosition => _savedLocation != null;

  @override
  void initState() {
    super.initState();
    _loadSavedLocation();
  }

  Future<void> _loadSavedLocation() async {
    final saved = await widget.parkingLocationStore.load();
    if (!mounted || saved == null) {
      return;
    }

    setState(() {
      _savedLocation = saved;
    });
  }

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
    unawaited(widget.notificationService.scheduleParkingNotifications(end));
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

    unawaited(widget.notificationService.cancelParkingNotifications());
  }

  Future<void> openCustomTimePicker() async {
    final duration = await showCustomTimeSheet(context);
    if (!mounted || duration == null) {
      return;
    }
    startTimer(duration);
  }

  Future<void> rememberLocation() async {
    if (_isSavingLocation) {
      return;
    }

    setState(() {
      _isSavingLocation = true;
    });

    try {
      final position = await widget.locationService.obtainCurrentPosition();
      final savedLocation = SavedParkingLocation(
        latitude: position.latitude,
        longitude: position.longitude,
        savedAt: widget.now(),
      );
      await widget.parkingLocationStore.save(savedLocation);
      if (!mounted) {
        return;
      }

      setState(() {
        _savedLocation = savedLocation;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Standort gespeichert')),
      );
    } catch (_) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Standort konnte nicht gespeichert werden')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isSavingLocation = false;
        });
      }
    }
  }

  /// Clears the persisted parking location. No UI entry point yet.
  Future<void> clearSavedLocation() async {
    await widget.parkingLocationStore.clear();
    if (!mounted) {
      return;
    }

    setState(() {
      _savedLocation = null;
    });
  }

  Future<void> navigateToCar() async {
    final location = _savedLocation;
    if (location == null) {
      return;
    }

    final opened = await widget.navigationService.openNavigation(location);
    if (!mounted) {
      return;
    }

    if (!opened) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Karten-App konnte nicht geöffnet werden'),
        ),
      );
    }
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
                          LocationButton(
                            isSaved: hasSavedPosition,
                            isLoading: _isSavingLocation,
                            onPressed: rememberLocation,
                          ),
                          if (hasSavedPosition) ...[
                            const SizedBox(height: 12),
                            NavigateToCarButton(onPressed: navigateToCar),
                          ],
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

class NavigateToCarButton extends StatelessWidget {
  const NavigateToCarButton({super.key, required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 56,
      child: ElevatedButton.icon(
        onPressed: onPressed,
        icon: const Icon(Icons.directions_rounded, size: 22),
        label: const Text('Zum Auto navigieren'),
        style: ElevatedButton.styleFrom(
          backgroundColor: ParkTimerApp.primaryBlue,
          foregroundColor: Colors.white,
          elevation: 3,
          shadowColor: ParkTimerApp.primaryBlue.withValues(alpha: 0.35),
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

class LocationButton extends StatelessWidget {
  const LocationButton({
    super.key,
    required this.onPressed,
    this.isSaved = false,
    this.isLoading = false,
  });

  final VoidCallback onPressed;
  final bool isSaved;
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    final backgroundColor =
        isSaved ? ParkTimerApp.accentGreen : const Color(0xFFE5E7EB);
    final foregroundColor =
        isSaved ? Colors.white : const Color(0xFF4B5563);

    return SizedBox(
      width: double.infinity,
      height: 56,
      child: ElevatedButton.icon(
        onPressed: isLoading ? null : onPressed,
        icon: Icon(
          isSaved ? Icons.location_on : Icons.location_on_outlined,
          size: 22,
        ),
        label: Text(
          isSaved ? 'Standort gespeichert ✓' : 'Standort merken',
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: backgroundColor,
          disabledBackgroundColor: backgroundColor.withValues(alpha: 0.7),
          foregroundColor: foregroundColor,
          disabledForegroundColor: foregroundColor.withValues(alpha: 0.8),
          elevation: 2,
          shadowColor: isSaved
              ? ParkTimerApp.accentGreen.withValues(alpha: 0.35)
              : Colors.black26,
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
