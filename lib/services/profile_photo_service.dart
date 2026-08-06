import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../core/constants/app_config.dart';

/// Uploads student profile photos to Cloudinary using an unsigned upload
/// preset — no backend or API secret needed, matching the rest of this
/// app's architecture (everything else talks to Firestore directly too).
///
/// One-time setup (fill in AppConfig.cloudinaryCloudName /
/// cloudinaryUploadPreset):
///   1. Create a free account at https://cloudinary.com
///   2. Dashboard -> copy the "Cloud name" shown at the top
///   3. Settings (gear icon) -> Upload -> Upload presets -> Add upload
///      preset:
///        - Signing Mode: Unsigned  (required — lets the app upload
///          directly with no secret key involved)
///        - Restrict allowed formats to images and set a sensible max
///          file size — the preset name ships inside the app and isn't a
///          secret, so these limits are the only abuse guard available
///          without a backend.
///   4. Paste the cloud name + preset name into AppConfig.
///
/// Note: unsigned presets can't enable "Overwrite" (Cloudinary blocks it —
/// otherwise anyone with just the preset name could clobber someone
/// else's file by guessing its id). So every upload here gets its own
/// fresh, Cloudinary-assigned id rather than reusing one per student;
/// re-uploading a photo leaves the old file behind in Cloudinary (a
/// trivial sliver of the free quota) once Firestore's `profileImageUrl`
/// points at the new one instead.
class ProfilePhotoService {
  ProfilePhotoService._();

  static final ProfilePhotoService instance = ProfilePhotoService._();

  /// Uploads [file] as this student's photo and returns its https URL.
  Future<String> upload(String uid, File file) async {
    if (AppConfig.cloudinaryCloudName == 'YOUR_CLOUD_NAME' ||
        AppConfig.cloudinaryUploadPreset == 'YOUR_UPLOAD_PRESET') {
      throw Exception(
        'Cloudinary isn\'t configured yet — set cloudinaryCloudName and '
        'cloudinaryUploadPreset in AppConfig.',
      );
    }

    final uri = Uri.parse(
      'https://api.cloudinary.com/v1_1/${AppConfig.cloudinaryCloudName}/image/upload',
    );

    final request = http.MultipartRequest('POST', uri)
      ..fields['upload_preset'] = AppConfig.cloudinaryUploadPreset
      // No public_id: unsigned presets can't overwrite, so a fixed id per
      // uid would just fail/no-op on the second upload. Cloudinary
      // assigns a fresh unique one instead (see class doc comment).
      ..fields['context'] = 'uid=$uid'
      ..files.add(await http.MultipartFile.fromPath('file', file.path));

    final streamedResponse = await request.send();
    final response = await http.Response.fromStream(streamedResponse);

    if (response.statusCode != 200) {
      throw Exception(
        'Cloudinary upload failed (${response.statusCode}): ${response.body}',
      );
    }

    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    final url = decoded['secure_url'] as String?;
    if (url == null) {
      throw Exception(
        'Cloudinary upload succeeded but returned no secure_url: ${response.body}',
      );
    }
    return url;
  }

  /// Removing an asset outright requires a *signed* Cloudinary request
  /// (API secret), which has no safe place to live without a backend.
  /// Callers just clear the Firestore `profileImageUrl` field instead —
  /// the old file stays in Cloudinary (a trivial sliver of the free
  /// quota) but stops being shown anywhere in the app. Kept as a no-op
  /// method (rather than removed) so call sites don't need special-casing
  /// if signed deletion is ever added later via a small backend.
  Future<void> delete(String uid) async {}
}
