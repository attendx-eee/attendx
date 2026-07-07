import 'package:flutter/material.dart';
import '../responsive/responsive.dart';
import 'app_colors.dart';

class AppTextStyles {
  AppTextStyles._();

  static TextStyle display = TextStyle(
    fontSize: Responsive.sp(30),
    fontWeight: FontWeight.w700,
    color: AppColors.textPrimary,
    height: 1.2,
  );

  static TextStyle headline = TextStyle(
    fontSize: Responsive.sp(22),
    fontWeight: FontWeight.w700,
    color: AppColors.textPrimary,
  );

  static TextStyle title = TextStyle(
    fontSize: Responsive.sp(18),
    fontWeight: FontWeight.w600,
    color: AppColors.textPrimary,
  );

  static TextStyle body = TextStyle(
    fontSize: Responsive.sp(14),
    fontWeight: FontWeight.w500,
    color: AppColors.textSecondary,
  );

  static TextStyle caption = TextStyle(
    fontSize: Responsive.sp(12),
    fontWeight: FontWeight.w500,
    color: AppColors.textSecondary,
  );
}