import 'package:flutter/material.dart';

import 'app_colors.dart';

/// Colours shared by every attendance calendar — the student's, the
/// admin's, and the CR's.
///
/// Kept in one place because the same day has to look the same to all
/// three. A student seeing amber where the admin sees green is worse
/// than either colour being wrong.

/// Dark grey for a closed day.
///
/// Deliberately off the present/absent scale. A holiday is not a good or
/// a bad attendance outcome, it's the absence of the question, and a
/// green or red family colour invites reading it as one.
const Color holidayFill = Color(0xFF4B5563);

/// Red at nothing attended, amber at half, green at all of it.
///
/// Two lerps rather than one: interpolating red straight to green passes
/// through a muddy brown at the midpoint, which is exactly where the
/// colour most needs to be legible.
Color attendanceShade(double ratio) {
  final r = ratio.clamp(0.0, 1.0);
  final amber = Colors.amber.shade700;

  return (r <= 0.5
      ? Color.lerp(AppColors.danger, amber, r * 2)
      : Color.lerp(amber, AppColors.success, (r - 0.5) * 2))!;
}
