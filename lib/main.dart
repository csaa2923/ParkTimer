import 'dart:async';

import 'package:flutter/material.dart';

import 'package:parktimer/services/location_service.dart';
import 'package:parktimer/services/navigation_service.dart';
import 'package:parktimer/services/notification_service.dart';
import 'package:parktimer/services/parking_location_store.dart';
import 'package:parktimer/services/parking_session_store.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await NotificationService.instance.initialize();
  } catch (error, stackTrace) {
    debugPrint(
      '[ParkTimer/Notifications] Startup initialize failed: $error\n$stackTrace',
    );
  }
  runApp(const ParkTimerApp());
}

class ParkTimerApp extends StatelessWidget {
  const ParkTimerApp({
    super.key,
    this.now = DateTime.now,
    this.locationService,
    this.parkingLocationStore,
    this.parkingSessionStore,
    this.navigationService,
    this.notificationService,
  });

  /// Injectable clock for tests; defaults to wall clock time.
  final DateTime Function() now;

  /// Injectable location service for tests; defaults to the shared instance.
  final LocationService? locationService;

  /// Injectable parking location store for tests; defaults to the shared instance.
  final ParkingLocationStore? parkingLocationStore;

  /// Injectable parking session store for tests; defaults to the shared instance.
  final ParkingSessionStore? parkingSessionStore;

  /// Injectable navigation service for tests; defaults to the shared instance.
  final NavigationService? navigationService;

  /// Injectable notification service for tests; defaults to the shared instance.
  final NotificationService? notificationService;

  static const Color primaryBlue = Color(0xFF1E3A8A);
  static const Color accentGreen = Color(0xFF22C55E);
  static const Color backgroundGray = Color(0xFFF5F7FA);
  static const Color warningOrange = Color(0xFFF59E0B);
  static const Color dangerRed = Color(0xFFEF4444);

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
        parkingSessionStore:
            parkingSessionStore ?? ParkingSessionStore.instance,
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
    required this.parkingSessionStore,
    required this.navigationService,
    required this.notificationService,
  });

  final DateTime Function() now;
  final LocationService locationService;
  final ParkingLocationStore parkingLocationStore;
  final ParkingSessionStore parkingSessionStore;
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
    unawaited(_bootstrap());
  }

  Future<void> _bootstrap() async {
    await Future.wait<void>([
      _loadSavedLocation(),
      _restoreParkingSession(),
    ]);
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

  Future<void> _restoreParkingSession() async {
    final session = await widget.parkingSessionStore.load();
    if (!mounted || session == null || !session.isActive) {
      return;
    }

    final now = widget.now();
    if (session.endTime.isAfter(now)) {
      _beginTicker(
        endTime: session.endTime,
        remaining: session.endTime.difference(now),
      );
      // Re-plan remaining notifications; scheduleParkingNotifications cancels
      // existing IDs first to avoid duplicates.
      unawaited(
        widget.notificationService.scheduleParkingNotifications(session.endTime),
      );
      return;
    }

    await widget.parkingSessionStore.clear();
    if (!mounted) {
      return;
    }

    setState(() {
      _endTime = session.endTime;
      _remaining = Duration.zero;
      _isRunning = false;
      _isExpired = true;
    });
  }

  void _beginTicker({
    required DateTime endTime,
    required Duration remaining,
  }) {
    _ticker?.cancel();

    setState(() {
      _endTime = endTime;
      _remaining = remaining;
      _isRunning = true;
      _isExpired = false;
    });

    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _onTick());
  }

  void startTimer(Duration duration) {
    final start = widget.now();
    final end = start.add(duration);

    _beginTicker(endTime: end, remaining: duration);

    unawaited(
      widget.parkingSessionStore.save(
        ParkingSession(
          endTime: end,
          startTime: start,
          isActive: true,
        ),
      ),
    );
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

    unawaited(widget.parkingSessionStore.clear());
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
      unawaited(widget.parkingSessionStore.clear());
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
    final showHeroIcon = !_isRunning && !_isExpired;

    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                '🚗 ParkTimer',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      color: ParkTimerApp.primaryBlue,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.5,
                    ),
              ),
              AnimatedSize(
                duration: const Duration(milliseconds: 280),
                curve: Curves.easeOutCubic,
                child: showHeroIcon
                    ? const Padding(
                        padding: EdgeInsets.only(top: 28, bottom: 20),
                        child: _ParkingHeroIcon(),
                      )
                    : const SizedBox(height: 16),
              ),
              _StatusSection(
                isRunning: _isRunning,
                isExpired: _isExpired,
                endTime: _endTime,
                remaining: _remaining,
              ),
              const SizedBox(height: 28),
              DurationButton(
                label: '30 Minuten',
                onPressed: () => startTimer(const Duration(minutes: 30)),
              ),
              const SizedBox(height: 12),
              DurationButton(
                label: '1 Stunde',
                onPressed: () => startTimer(const Duration(hours: 1)),
              ),
              const SizedBox(height: 12),
              DurationButton(
                label: '2 Stunden',
                onPressed: () => startTimer(const Duration(hours: 2)),
              ),
              const SizedBox(height: 12),
              DurationButton(
                label: 'Eigene Zeit',
                isAccent: true,
                onPressed: openCustomTimePicker,
              ),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 250),
                switchInCurve: Curves.easeOutCubic,
                switchOutCurve: Curves.easeInCubic,
                child: _isRunning
                    ? Padding(
                        key: const ValueKey('stop-timer'),
                        padding: const EdgeInsets.only(top: 12),
                        child: StopTimerButton(onPressed: stopTimer),
                      )
                    : const SizedBox.shrink(key: ValueKey('no-stop-timer')),
              ),
              const SizedBox(height: 24),
              if (hasSavedPosition) ...[
                SavedLocationInfoCard(savedAt: _savedLocation!.savedAt),
                const SizedBox(height: 12),
                NavigateToCarButton(onPressed: navigateToCar),
              ] else
                LocationButton(
                  isLoading: _isSavingLocation,
                  onPressed: rememberLocation,
                ),
              // TEMPORARY: internal notification channel / permission check.
              const SizedBox(height: 16),
              TextButton(
                key: const Key('test_notification_button'),
                onPressed: () {
                  unawaited(widget.notificationService.showTestNotification());
                },
                child: const Text('Benachrichtigung testen'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

Color parkingStatusColor({
  required bool isExpired,
  required bool isRunning,
  required Duration remaining,
}) {
  if (isExpired) {
    return ParkTimerApp.dangerRed;
  }
  if (!isRunning) {
    return ParkTimerApp.primaryBlue;
  }
  if (remaining > const Duration(minutes: 15)) {
    return ParkTimerApp.accentGreen;
  }
  if (remaining >= const Duration(minutes: 5)) {
    return ParkTimerApp.warningOrange;
  }
  return ParkTimerApp.dangerRed;
}

class _ParkingHeroIcon extends StatelessWidget {
  const _ParkingHeroIcon();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: 120,
        height: 120,
        decoration: BoxDecoration(
          color: Colors.white,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: ParkTimerApp.primaryBlue.withValues(alpha: 0.12),
              blurRadius: 24,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: const Icon(
          Icons.local_parking_rounded,
          size: 64,
          color: ParkTimerApp.primaryBlue,
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
    final statusColor = parkingStatusColor(
      isExpired: isExpired,
      isRunning: isRunning,
      remaining: remaining,
    );

    if (isExpired) {
      return Text(
        'Parkzeit abgelaufen',
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              color: statusColor,
              fontWeight: FontWeight.w700,
            ),
      );
    }

    if (isRunning && endTime != null) {
      final baseSize =
          Theme.of(context).textTheme.displaySmall?.fontSize ?? 36;
      final countdownSize = baseSize * 1.2;

      return Column(
        children: [
          Text(
            formatCountdown(remaining),
            textAlign: TextAlign.center,
            style: TextStyle(
              color: statusColor,
              fontSize: countdownSize,
              fontWeight: FontWeight.w700,
              fontFeatures: const [FontFeature.tabularFigures()],
              letterSpacing: 1.2,
              height: 1.05,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Parken bis ${formatClockTime(endTime!)}',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: const Color(0xFF6B7280),
                  fontWeight: FontWeight.w500,
                ),
          ),
        ],
      );
    }

    return Text(
      'Parkzeit starten',
      textAlign: TextAlign.center,
      style: Theme.of(context).textTheme.titleLarge?.copyWith(
            color: ParkTimerApp.primaryBlue,
            fontWeight: FontWeight.w600,
          ),
    );
  }
}

class SavedLocationInfoCard extends StatelessWidget {
  const SavedLocationInfoCard({super.key, required this.savedAt});

  final DateTime savedAt;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: ParkTimerApp.accentGreen.withValues(alpha: 0.28),
        ),
        boxShadow: [
          BoxShadow(
            color: ParkTimerApp.accentGreen.withValues(alpha: 0.08),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: ParkTimerApp.accentGreen.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(
              Icons.location_on_rounded,
              color: ParkTimerApp.accentGreen,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '📍 Standort gespeichert',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        color: const Color(0xFF111827),
                        fontWeight: FontWeight.w700,
                      ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Gespeichert um ${formatClockTime(savedAt)}',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: const Color(0xFF6B7280),
                      ),
                ),
              ],
            ),
          ),
        ],
      ),
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

    return _AnimatedPressScale(
      child: SizedBox(
        width: double.infinity,
        height: 56,
        child: ElevatedButton(
          onPressed: onPressed ?? () {},
          style: ElevatedButton.styleFrom(
            backgroundColor: backgroundColor,
            foregroundColor: Colors.white,
            elevation: 2,
            shadowColor: backgroundColor.withValues(alpha: 0.28),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
            ),
            textStyle: const TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.2,
            ),
          ),
          child: Text(label),
        ),
      ),
    );
  }
}

class StopTimerButton extends StatelessWidget {
  const StopTimerButton({super.key, required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return _AnimatedPressScale(
      child: SizedBox(
        width: double.infinity,
        height: 56,
        child: ElevatedButton(
          onPressed: onPressed,
          style: ElevatedButton.styleFrom(
            backgroundColor: ParkTimerApp.dangerRed,
            foregroundColor: Colors.white,
            elevation: 2,
            shadowColor: ParkTimerApp.dangerRed.withValues(alpha: 0.28),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
            ),
            textStyle: const TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.2,
            ),
          ),
          child: const Text('Timer stoppen'),
        ),
      ),
    );
  }
}

class NavigateToCarButton extends StatelessWidget {
  const NavigateToCarButton({super.key, required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return _AnimatedPressScale(
      child: SizedBox(
        width: double.infinity,
        height: 56,
        child: ElevatedButton.icon(
          onPressed: onPressed,
          icon: const Icon(Icons.navigation_rounded, size: 22),
          label: const Text('Zum Auto navigieren'),
          style: ElevatedButton.styleFrom(
            backgroundColor: ParkTimerApp.primaryBlue,
            foregroundColor: Colors.white,
            elevation: 2,
            shadowColor: ParkTimerApp.primaryBlue.withValues(alpha: 0.28),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
            ),
            textStyle: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
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
    this.isLoading = false,
  });

  final VoidCallback onPressed;
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    return _AnimatedPressScale(
      child: SizedBox(
        width: double.infinity,
        height: 56,
        child: ElevatedButton.icon(
          onPressed: isLoading ? null : onPressed,
          icon: const Icon(Icons.location_on_outlined, size: 22),
          label: const Text('Standort merken'),
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFFE5E7EB),
            disabledBackgroundColor: const Color(0xFFE5E7EB).withValues(alpha: 0.7),
            foregroundColor: const Color(0xFF4B5563),
            disabledForegroundColor: const Color(0xFF4B5563).withValues(alpha: 0.8),
            elevation: 1,
            shadowColor: Colors.black12,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
            ),
            textStyle: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}

class _AnimatedPressScale extends StatefulWidget {
  const _AnimatedPressScale({required this.child});

  final Widget child;

  @override
  State<_AnimatedPressScale> createState() => _AnimatedPressScaleState();
}

class _AnimatedPressScaleState extends State<_AnimatedPressScale> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: (_) => setState(() => _pressed = true),
      onPointerUp: (_) => setState(() => _pressed = false),
      onPointerCancel: (_) => setState(() => _pressed = false),
      child: AnimatedScale(
        scale: _pressed ? 0.98 : 1,
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOutCubic,
        child: widget.child,
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
