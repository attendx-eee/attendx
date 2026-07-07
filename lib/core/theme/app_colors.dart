import 'package:flutter/material.dart';

/// Brand palette derived from the AttendX logo:
/// royal blue "A" -> teal checkmark/book gradient.
class AppColors {
  AppColors._();

  static const background = Color(0xFFF5F7FB);

  static const surface = Colors.white;

  /// Royal blue from the logo's "A".
  static const primary = Color(0xFF2563EB);

  static const primaryDark = Color(0xFF1D4ED8);

  static const secondary = Color(0xFF60A5FA);

  /// Teal from the logo's checkmark and book gradient.
  static const teal = Color(0xFF14C4B8);

  static const tealDark = Color(0xFF0D9488);

  static const success = Color(0xFF22C55E);

  static const warning = Color(0xFFF59E0B);

  static const danger = Color(0xFFEF4444);

  static const textPrimary = Color(0xFF111827);

  static const textSecondary = Color(0xFF6B7280);

  static const divider = Color(0xFFE5E7EB);

  static const shadow = Color(0x14000000);

  /// Signature blue -> teal sweep, matching the logo.
  static const brandGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [primary, teal],
  );
}
