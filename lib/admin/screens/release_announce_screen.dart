import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../core/constants/app_config.dart';
import '../../core/responsive/responsive.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_radius.dart';
import '../../core/theme/app_text_styles.dart';
import '../../notifications/services/notification_service.dart';

/// Publishes a release and tells everybody about it.
///
/// Publishing used to mean editing `app_meta/android` by hand in the
/// Firebase console and hoping people noticed the prompt the next time
/// they opened the app. Someone who hadn't opened it in a fortnight
/// stayed on an old build indefinitely — which matters here, because
/// the old build talks to the same database and can write records the
/// new one interprets differently.
///
/// This does both halves: writes the metadata installed apps check, and
/// sends a push so the prompt arrives whether or not the app is open.
class ReleaseAnnounceScreen extends StatefulWidget {
  const ReleaseAnnounceScreen({super.key});

  @override
  State<ReleaseAnnounceScreen> createState() =>
      _ReleaseAnnounceScreenState();
}

class _ReleaseAnnounceScreenState extends State<ReleaseAnnounceScreen> {
  final _version = TextEditingController();
  final _versionCode = TextEditingController();
  final _apkUrl = TextEditingController();
  final _notes = TextEditingController();

  bool _loading = true;
  bool _busy = false;
  String? _status;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final c in [_version, _versionCode, _apkUrl, _notes]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection(AppConfig.appMetaCollection)
          .doc(AppConfig.appMetaDoc)
          .get();

      final data = doc.data() ?? const <String, dynamic>{};

      _version.text = (data['latestVersion'] ?? '').toString();
      _versionCode.text = (data['latestVersionCode'] ?? '').toString();
      _apkUrl.text = (data['apkUrl'] ?? '').toString();
      _notes.text = (data['notes'] ?? '').toString();
    } catch (e) {
      _status = "Couldn't read the current release: $e";
      _failed = true;
    }

    if (mounted) setState(() => _loading = false);
  }

  Future<void> _publish({required bool announce}) async {
    final version = _version.text.trim();
    final code = int.tryParse(_versionCode.text.trim());
    final url = _apkUrl.text.trim();

    if (version.isEmpty || code == null || url.isEmpty) {
      setState(() {
        _failed = true;
        _status = 'Version, version code and APK link are all required.';
      });
      return;
    }

    setState(() {
      _busy = true;
      _status = null;
      _failed = false;
    });

    try {
      await FirebaseFirestore.instance
          .collection(AppConfig.appMetaCollection)
          .doc(AppConfig.appMetaDoc)
          .set({
        'latestVersion': version,
        'latestVersionCode': code,
        'apkUrl': url,
        'notes': _notes.text.trim(),
        'forceUpdate': false,
        'publishedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      var sent = 0;
      if (announce) {
        sent = await NotificationService.instance.announceUpdate(
          version: version,
          apkUrl: url,
          notes: _notes.text.trim(),
        );
      }

      if (mounted) {
        setState(() {
          _failed = false;
          _status = announce
              ? 'Published, and $sent people notified. Pushes go out '
                  'within a minute.'
              : 'Published. Nobody has been notified — installed apps '
                  'will find it at their next launch.';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _failed = true;
          _status = "Couldn't publish: $e";
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    Responsive.init(context);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Publish a release'),
        backgroundColor: AppColors.background,
        surfaceTintColor: AppColors.background,
        elevation: 0,
        foregroundColor: AppColors.textPrimary,
      ),
      body: MaxWidthBody(
        maxWidth: 640,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: Responsive.all(20),
                children: [
                  if (_busy) const LinearProgressIndicator(minHeight: 2),

                  Text(
                    'This console is running ${AppConfig.appVersion}. '
                    'Upload the APK to the website first — announcing a '
                    'version whose file is not live yet sends everyone '
                    'to a 404.',
                    style: AppTextStyles.caption,
                  ),
                  SizedBox(height: Responsive.h(18)),

                  _field(_version, 'Version', 'e.g. 1.2.6',
                      Icons.tag_rounded),
                  SizedBox(height: Responsive.h(12)),
                  _field(_versionCode, 'Version code',
                      'A whole number, higher than the last one',
                      Icons.numbers_rounded,
                      numeric: true),
                  SizedBox(height: Responsive.h(12)),
                  _field(_apkUrl, 'APK link', 'https://…/attendx-v1.2.6.apk',
                      Icons.link_rounded),
                  SizedBox(height: Responsive.h(12)),
                  _field(_notes, "What's new", 'Shown in the notification',
                      Icons.notes_rounded,
                      lines: 3),

                  SizedBox(height: Responsive.h(10)),
                  Container(
                    padding: Responsive.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.warning.withValues(alpha: .10),
                      borderRadius: BorderRadius.circular(AppRadius.sm),
                    ),
                    child: Text(
                      'The version code is what phones actually compare. '
                      'Android refuses to install a build whose code is '
                      'not higher than the one already on the device, so '
                      'this has to go up every release even when the '
                      'version name barely changes.',
                      style: AppTextStyles.caption,
                    ),
                  ),

                  if (_status != null) ...[
                    SizedBox(height: Responsive.h(14)),
                    Container(
                      padding: Responsive.all(12),
                      decoration: BoxDecoration(
                        color: (_failed
                                ? AppColors.danger
                                : AppColors.success)
                            .withValues(alpha: .10),
                        borderRadius: BorderRadius.circular(AppRadius.sm),
                      ),
                      child: Text(
                        _status!,
                        style: AppTextStyles.caption.copyWith(
                          color: _failed
                              ? AppColors.danger
                              : AppColors.success,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],

                  SizedBox(height: Responsive.h(20)),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed:
                          _busy ? null : () => _publish(announce: true),
                      icon: const Icon(Icons.campaign_rounded, size: 18),
                      label: const Text('Publish and notify everyone'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        padding: Responsive.symmetric(vertical: 15),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(AppRadius.sm),
                        ),
                      ),
                    ),
                  ),
                  SizedBox(height: Responsive.h(10)),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton(
                      onPressed:
                          _busy ? null : () => _publish(announce: false),
                      child: const Text('Publish quietly'),
                    ),
                  ),
                  SizedBox(height: Responsive.h(8)),
                  Text(
                    'Quiet publishing still lets the app find the update '
                    'on its own — it just does not push. Useful for a fix '
                    'that only matters to whoever hits the bug.',
                    style: AppTextStyles.caption,
                  ),
                  SizedBox(height: Responsive.h(24)),
                ],
              ),
      ),
    );
  }

  Widget _field(
    TextEditingController controller,
    String label,
    String hint,
    IconData icon, {
    bool numeric = false,
    int lines = 1,
  }) =>
      TextField(
        controller: controller,
        maxLines: lines,
        keyboardType: numeric ? TextInputType.number : null,
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          hintStyle: AppTextStyles.caption,
          prefixIcon: Icon(icon, size: Responsive.sp(18)),
          filled: true,
          fillColor: AppColors.surface,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppRadius.sm),
          ),
        ),
      );
}
