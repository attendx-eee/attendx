import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';

/// Where a register was taken, and on what.
///
/// Every field is optional, because every field can legitimately be
/// missing: location turned off, permission refused, indoors with no
/// fix, an iPhone where the Android flags do not exist. A scan is never
/// blocked for want of any of this.
class ScanProvenance {
  final double? latitude;
  final double? longitude;

  /// Metres. A fix accurate to 40m cannot tell one classroom from the
  /// one below it, so the figure is stored alongside the position and
  /// anyone reading it can judge what it is worth.
  final double? accuracy;

  /// Developer options were enabled on the phone that took the register.
  final bool? developerOptions;

  /// USB debugging was enabled.
  final bool? adbEnabled;

  const ScanProvenance({
    this.latitude,
    this.longitude,
    this.accuracy,
    this.developerOptions,
    this.adbEnabled,
  });

  bool get hasPosition => latitude != null && longitude != null;

  /// Worth mentioning to the lecturer before they save.
  bool get flagged => developerOptions == true || adbEnabled == true;

  Map<String, dynamic> toMap() => {
        if (latitude != null) 'capturedLat': latitude,
        if (longitude != null) 'capturedLng': longitude,
        if (accuracy != null) 'capturedAccuracy': accuracy,
        if (developerOptions != null) 'developerOptions': developerOptions,
        if (adbEnabled != null) 'adbEnabled': adbEnabled,
      };
}

/// Collects the provenance stamp for a classroom scan.
///
/// Deliberately advisory. None of this proves a register is honest and
/// none of it is treated as if it did: a location fix indoors is
/// accurate to tens of metres, and the device flags are trivially turned
/// off by anyone who meant to turn them off. What it gives the
/// department is a record — where the phone was and what state it was
/// in — for the one case a year where a register is questioned and
/// somebody has to look into it.
///
/// Nothing here ever throws into the caller. A register that could not
/// be saved because the GPS was slow would be a far worse failure than
/// one saved without a position.
class ScanProvenanceService {
  ScanProvenanceService._();

  static final ScanProvenanceService instance = ScanProvenanceService._();

  static const MethodChannel _channel = MethodChannel('attendx/device');

  /// Long enough for a fix indoors, short enough that nobody is left
  /// staring at a spinner after pressing save.
  static const Duration _fixTimeout = Duration(seconds: 6);

  Future<ScanProvenance> collect() async {
    final position = await _position();
    final flags = await _flags();

    return ScanProvenance(
      latitude: position?.latitude,
      longitude: position?.longitude,
      accuracy: position?.accuracy,
      developerOptions: flags['developerOptions'],
      adbEnabled: flags['adbEnabled'],
    );
  }

  Future<Position?> _position() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) return null;

      var permission = await Geolocator.checkPermission();

      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      // deniedForever means the lecturer has said no and meant it. Asking
      // again on every register would be the kind of nagging that gets an
      // app uninstalled.
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return null;
      }

      return await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium,
          timeLimit: _fixTimeout,
        ),
      );
    } catch (e) {
      // Timed out, no signal, permission revoked mid-call — all of them
      // mean the same thing here, which is that there is no position to
      // record.
      debugPrint('Scan location unavailable: $e');
      return null;
    }
  }

  Future<Map<String, bool?>> _flags() async {
    // A debug build is on a tethered phone with USB debugging on by
    // definition — that is how it got there. Flagging it would mean
    // every test register carried a warning, and a warning that is
    // always on is one nobody reads.
    if (kDebugMode) return const {};

    try {
      final raw = await _channel.invokeMapMethod<String, dynamic>('flags');
      if (raw == null) return const {};

      return {
        'developerOptions': raw['developerOptions'] as bool?,
        'adbEnabled': raw['adbEnabled'] as bool?,
      };
    } catch (e) {
      // iOS has no such channel, and an older build of the app has no
      // such handler. Neither is an error worth surfacing.
      debugPrint('Device flags unavailable: $e');
      return const {};
    }
  }
}
