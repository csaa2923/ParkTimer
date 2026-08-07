import 'package:shared_preferences/shared_preferences.dart';

/// In-memory representation of a persisted parking position.
class SavedParkingLocation {
  const SavedParkingLocation({
    required this.latitude,
    required this.longitude,
    required this.savedAt,
  });

  final double latitude;
  final double longitude;
  final DateTime savedAt;
}

/// Lightweight local persistence for the remembered parking position.
class ParkingLocationStore {
  ParkingLocationStore({this._preferences});

  static final ParkingLocationStore instance = ParkingLocationStore();

  static const String _latitudeKey = 'parking_latitude';
  static const String _longitudeKey = 'parking_longitude';
  static const String _savedAtKey = 'parking_saved_at';

  SharedPreferences? _preferences;

  Future<SharedPreferences> _prefs() async {
    return _preferences ??= await SharedPreferences.getInstance();
  }

  /// Persists latitude, longitude and the save timestamp.
  Future<void> save(SavedParkingLocation location) async {
    final prefs = await _prefs();
    await prefs.setDouble(_latitudeKey, location.latitude);
    await prefs.setDouble(_longitudeKey, location.longitude);
    await prefs.setString(_savedAtKey, location.savedAt.toIso8601String());
  }

  /// Loads a previously saved parking position, if present.
  Future<SavedParkingLocation?> load() async {
    final prefs = await _prefs();
    final latitude = prefs.getDouble(_latitudeKey);
    final longitude = prefs.getDouble(_longitudeKey);
    final savedAtRaw = prefs.getString(_savedAtKey);

    if (latitude == null || longitude == null || savedAtRaw == null) {
      return null;
    }

    final savedAt = DateTime.tryParse(savedAtRaw);
    if (savedAt == null) {
      return null;
    }

    return SavedParkingLocation(
      latitude: latitude,
      longitude: longitude,
      savedAt: savedAt,
    );
  }

  /// Deletes the persisted parking position.
  Future<void> clear() async {
    final prefs = await _prefs();
    await prefs.remove(_latitudeKey);
    await prefs.remove(_longitudeKey);
    await prefs.remove(_savedAtKey);
  }
}
