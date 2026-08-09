import 'package:flutter/material.dart';
import '../responsive/responsive.dart';
import 'app_colors.dart';

/// The app's type scale.
///
/// Getters, not static fields. As fields these were lazy statics that
/// each called [Responsive.sp] the first time they were read — which
/// meant two problems at once:
///
/// - reading one before any screen had called `Responsive.init` threw,
///   and a throw during build in a release web build paints a blank
///   grey page with no message;
/// - whichever screen happened to touch a style first froze its size
///   for the rest of the session, so a value computed on a phone-sized
///   window stayed that size after the browser was resized.
///
/// Recomputing per access costs a multiply. That is not worth a class of
/// bug this quiet.
class AppTextStyles {
  AppTextStyles._();

  static TextStyle get display => TextStyle(
        fontSize: Responsive.sp(30),
        fontWeight: FontWeight.w700,
        color: AppColors.textPrimary,
        height: 1.2,
      );

  static TextStyle get headline => TextStyle(
        fontSize: Responsive.sp(22),
        fontWeight: FontWeight.w700,
        color: AppColors.textPrimary,
      );

  static TextStyle get title => TextStyle(
        fontSize: Responsive.sp(18),
        fontWeight: FontWeight.w600,
        color: AppColors.textPrimary,
      );

  static TextStyle get body => TextStyle(
        fontSize: Responsive.sp(14),
        fontWeight: FontWeight.w500,
        color: AppColors.textSecondary,
      );

  static TextStyle get caption => TextStyle(
        fontSize: Responsive.sp(12),
        fontWeight: FontWeight.w500,
        color: AppColors.textSecondary,
      );
}
