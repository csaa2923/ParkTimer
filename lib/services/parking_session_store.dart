import 'package:shared_preferences/shared_preferences.dart';

/// Persisted parking timer session.
class ParkingSession {
  const ParkingSession({
    required this.endTime,
    required this.startTime,
    required this.isActive,
  });

  final DateTime endTime;
  final DateTime startTime;
  final bool isActive;
}

/// Local persistence for an active parking timer session.
class ParkingSessionStore {
  ParkingSessionStore({this._preferences});

  static final ParkingSessionStore instance = ParkingSessionStore();

  static const String _endTimeKey = 'parking_session_end_time';
  static const String _startTimeKey = 'parking_session_start_time';
  static const String _isActiveKey = 'parking_session_is_active';

  SharedPreferences? _preferences;

  Future<SharedPreferences> _prefs() async {
    return _preferences ??= await SharedPreferences.getInstance();
  }

  /// Persists an active parking session with absolute end time.
  Future<void> save(ParkingSession session) async {
    final prefs = await _prefs();
    await prefs.setString(_endTimeKey, session.endTime.toIso8601String());
    await prefs.setString(_startTimeKey, session.startTime.toIso8601String());
    await prefs.setBool(_isActiveKey, session.isActive);
  }

  /// Loads a previously saved parking session, if present.
  Future<ParkingSession?> load() async {
    final prefs = await _prefs();
    final endTimeRaw = prefs.getString(_endTimeKey);
    final startTimeRaw = prefs.getString(_startTimeKey);
    final isActive = prefs.getBool(_isActiveKey);

    if (endTimeRaw == null || startTimeRaw == null || isActive == null) {
      return null;
    }

    final endTime = DateTime.tryParse(endTimeRaw);
    final startTime = DateTime.tryParse(startTimeRaw);
    if (endTime == null || startTime == null) {
      return null;
    }

    return ParkingSession(
      endTime: endTime,
      startTime: startTime,
      isActive: isActive,
    );
  }

  /// Deletes the persisted parking session.
  Future<void> clear() async {
    final prefs = await _prefs();
    await prefs.remove(_endTimeKey);
    await prefs.remove(_startTimeKey);
    await prefs.remove(_isActiveKey);
  }
}
