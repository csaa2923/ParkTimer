import 'package:geolocator/geolocator.dart';

/// Central entry point for device location access.
///
/// Provides service/permission checks and a one-shot current position lookup.
/// Persistence and navigation are intentionally not handled here.
class LocationService {
  LocationService();

  static final LocationService instance = LocationService();

  /// Returns whether the platform location services (GPS/network) are enabled.
  Future<bool> isLocationServiceEnabled() {
    return Geolocator.isLocationServiceEnabled();
  }

  /// Returns the current location permission status.
  Future<LocationPermission> checkPermission() {
    return Geolocator.checkPermission();
  }

  /// Requests location permission for use while the app is in the foreground.
  Future<LocationPermission> requestPermission() {
    return Geolocator.requestPermission();
  }

  /// Fetches the device's current position.
  ///
  /// Callers should ensure location services are enabled and permission is
  /// granted before invoking this method.
  Future<Position> getCurrentPosition({
    LocationSettings? locationSettings,
  }) {
    return Geolocator.getCurrentPosition(
      locationSettings: locationSettings ??
          const LocationSettings(
            accuracy: LocationAccuracy.high,
          ),
    );
  }

  /// Ensures location services and permission, then returns the current position.
  Future<Position> obtainCurrentPosition({
    LocationSettings? locationSettings,
  }) async {
    final serviceEnabled = await isLocationServiceEnabled();
    if (!serviceEnabled) {
      throw const LocationServiceDisabledException();
    }

    var permission = await checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await requestPermission();
    }

    if (permission == LocationPermission.denied) {
      throw const PermissionDeniedException(
        'Standortberechtigung wurde verweigert.',
      );
    }

    if (permission == LocationPermission.deniedForever) {
      throw const PermissionDeniedException(
        'Standortberechtigung dauerhaft verweigert.',
      );
    }

    return getCurrentPosition(locationSettings: locationSettings);
  }
}
