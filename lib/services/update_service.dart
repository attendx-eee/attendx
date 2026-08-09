import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/constants/app_config.dart';
import '../core/theme/app_colors.dart';

/// Self-update check, driven by the Firestore doc `app_meta/android`:
///
/// { latestVersionCode: 4, latestVersion: "1.2.1",
///   apkUrl: "https://`user`.github.io/`repo`/attendx-v1.2.1.apk",
///   forceUpdate: false, notes: "Bug fixes..." }
///
/// Called on the login screen. If a newer versionCode exists, the user
/// is prompted to download the new APK from the website; when
/// `forceUpdate` is true the dialog cannot be dismissed.
/// What a manual update check found.
class UpdateStatus {
  /// True when a newer build is published.
  final bool available;

  /// The version the user is running.
  final String current;

  /// The published version. Same as [current] when up to date.
  final String latest;

  final String notes;
  final String apkUrl;

  /// Set when the check itself failed — no network, rules, bad doc.
  final String? error;

  const UpdateStatus({
    required this.available,
    required this.current,
    required this.latest,
    this.notes = '',
    this.apkUrl = '',
    this.error,
  });
}

class UpdateService {
  UpdateService._();

  static final UpdateService instance = UpdateService._();

  bool _checkedThisSession = false;

  /// Checks for a newer build without showing anything.
  ///
  /// The automatic prompt on the dashboard only fires once per session
  /// and only when an update exists — which leaves no way to answer "am
  /// I on the latest version?" if you dismissed it or never saw it.
  /// This backs the Settings entry that does.
  Future<UpdateStatus> checkStatus() async {
    const current = AppConfig.appVersion;

    if (kIsWeb) {
      return const UpdateStatus(
        available: false,
        current: current,
        latest: current,
      );
    }

    try {
      final snapshot = await FirebaseFirestore.instance
          .collection(AppConfig.appMetaCollection)
          .doc(AppConfig.appMetaDoc)
          .get();

      final data = snapshot.data();
      if (data == null) {
        return const UpdateStatus(
          available: false,
          current: current,
          latest: current,
          error: 'No release information published yet.',
        );
      }

      final latestCode = ((data['latestVersionCode'] ?? 0) as num).toInt();
      final latestVersion =
          (data['latestVersion'] ?? current).toString();

      return UpdateStatus(
        available: latestCode > AppConfig.appVersionCode,
        current: current,
        latest: latestVersion,
        notes: (data['notes'] ?? '').toString(),
        apkUrl: (data['apkUrl'] ?? '').toString(),
      );
    } catch (e) {
      return UpdateStatus(
        available: false,
        current: current,
        latest: current,
        error: 'Could not reach the update server.',
      );
    }
  }

  /// Opens the APK link. Android's download manager takes it from there
  /// and offers to install once the file lands.
  Future<bool> downloadUpdate(String apkUrl) async {
    if (apkUrl.isEmpty) return false;
    try {
      return await launchUrl(
        Uri.parse(apkUrl),
        mode: LaunchMode.externalApplication,
      );
    } catch (e) {
      debugPrint('Update download failed: $e');
      return false;
    }
  }

  Future<void> checkForUpdate(BuildContext context) async {
    if (kIsWeb) return; // the web app is always the latest deployment
    if (_checkedThisSession) return;
    _checkedThisSession = true;

    try {
      final snapshot = await FirebaseFirestore.instance
          .collection(AppConfig.appMetaCollection)
          .doc(AppConfig.appMetaDoc)
          .get();

      final data = snapshot.data();
      if (data == null) return;

      final latestCode =
          ((data['latestVersionCode'] ?? 0) as num).toInt();
      if (latestCode <= AppConfig.appVersionCode) return; // up to date

      final latestVersion =
          (data['latestVersion'] ?? '').toString();
      final apkUrl = (data['apkUrl'] ?? '').toString();
      final force = data['forceUpdate'] == true;
      final notes = (data['notes'] ?? '').toString();

      if (apkUrl.isEmpty) return;
      if (!context.mounted) return;

      await showDialog<void>(
        context: context,
        barrierDismissible: !force,
        builder: (dialogContext) => PopScope(
          canPop: !force,
          child: AlertDialog(
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16)),
            icon: const Icon(Icons.system_update_rounded,
                color: AppColors.primary, size: 44),
            title: Text(
              "Update Available${latestVersion.isEmpty ? '' : ' — v$latestVersion'}",
              textAlign: TextAlign.center,
              style: const TextStyle(
                  fontWeight: FontWeight.bold, fontSize: 18),
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  force
                      ? "This version is no longer supported. Please update to continue using AttendX."
                      : "A newer version of AttendX is available with improvements and fixes.",
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 13, height: 1.4),
                ),
                if (notes.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppColors.background,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      notes,
                      style: const TextStyle(
                          fontSize: 12, height: 1.4),
                    ),
                  ),
                ],
              ],
            ),
            actions: [
              if (!force)
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text("Later",
                      style: TextStyle(color: Colors.grey)),
                ),
              ElevatedButton.icon(
                onPressed: () async {
                  final uri = Uri.parse(apkUrl);
                  await launchUrl(uri,
                      mode: LaunchMode.externalApplication);
                  // Keep the dialog open for forced updates.
                  if (!force && dialogContext.mounted) {
                    Navigator.pop(dialogContext);
                  }
                },
                icon: const Icon(Icons.download_rounded, size: 18),
                label: const Text("Update Now"),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8)),
                ),
              ),
            ],
          ),
        ),
      );
    } catch (e) {
      debugPrint('Update check failed: $e');
    }
  }
}
