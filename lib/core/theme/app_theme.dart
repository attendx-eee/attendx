import 'package:flutter/material.dart';

import 'app_colors.dart';

/// The AttendX theme, shared by the mobile app and the admin web build.
///
/// Lives here rather than inline in `main.dart` so the web entry point
/// can use it without importing `main.dart` — which pulls in the whole
/// student tree (camera, TFLite, `dart:io`) and won't compile for web.
class AppTheme {
  AppTheme._();

  static ThemeData get light => ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: AppColors.primary,
          primary: AppColors.primary,
          secondary: AppColors.teal,
        ),
        scaffoldBackgroundColor: AppColors.background,
        appBarTheme: const AppBarTheme(
          backgroundColor: AppColors.surface,
          foregroundColor: AppColors.textPrimary,
          elevation: 0,
          centerTitle: false,
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.white,
          ),
        ),
        floatingActionButtonTheme: const FloatingActionButtonThemeData(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
        ),
        progressIndicatorTheme:
            const ProgressIndicatorThemeData(color: AppColors.primary),
        chipTheme: const ChipThemeData(
          side: BorderSide(color: AppColors.divider),
        ),
      );
}
