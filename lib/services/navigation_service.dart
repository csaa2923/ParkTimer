import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:parktimer/services/parking_location_store.dart';

typedef UrlLauncher = Future<bool> Function(
  Uri url, {
  LaunchMode mode,
});

/// Opens a saved parking position in a platform-appropriate maps app/browser.
class NavigationService {
  NavigationService({
    UrlLauncher? launchUrlFn,
    TargetPlatform? platform,
    bool? isWeb,
  })  : _launchUrlFn = launchUrlFn ?? _defaultLaunch,
        _platform = platform ?? defaultTargetPlatform,
        _isWeb = isWeb ?? kIsWeb;

  static final NavigationService instance = NavigationService();

  final UrlLauncher _launchUrlFn;
  final TargetPlatform _platform;
  final bool _isWeb;

  static Future<bool> _defaultLaunch(
    Uri url, {
    LaunchMode mode = LaunchMode.platformDefault,
  }) {
    return launchUrl(url, mode: mode);
  }

  /// Builds ordered map URI candidates for the given coordinates.
  List<Uri> buildNavigationUris({
    required double latitude,
    required double longitude,
  }) {
    final lat = latitude.toString();
    final lng = longitude.toString();

    final googleHttps = Uri.parse(
      'https://www.google.com/maps/search/?api=1&query=$lat,$lng',
    );
    final appleHttps = Uri.parse(
      'https://maps.apple.com/?daddr=$lat,$lng',
    );

    if (_isWeb) {
      return <Uri>[googleHttps];
    }

    switch (_platform) {
      case TargetPlatform.android:
        return <Uri>[
          Uri.parse('google.navigation:q=$lat,$lng'),
          Uri.parse('geo:$lat,$lng?q=$lat,$lng'),
          googleHttps,
        ];
      case TargetPlatform.iOS:
        return <Uri>[
          Uri.parse('maps://?daddr=$lat,$lng'),
          appleHttps,
        ];
      default:
        // Windows, macOS, Linux: open a browser map.
        return <Uri>[googleHttps];
    }
  }

  /// Tries platform-specific map URIs until one opens successfully.
  Future<bool> openNavigation(SavedParkingLocation location) async {
    final uris = buildNavigationUris(
      latitude: location.latitude,
      longitude: location.longitude,
    );

    for (final uri in uris) {
      try {
        final launched = await _launchUrlFn(
          uri,
          mode: LaunchMode.externalApplication,
        );
        if (launched) {
          return true;
        }
      } catch (_) {
        // Try the next fallback URI.
      }
    }

    return false;
  }
}
