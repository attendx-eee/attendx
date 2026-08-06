import 'package:custom_refresh_indicator/custom_refresh_indicator.dart';
import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';

/// Branded pull-to-refresh visual for the student dashboard: the AttendX
/// logo sits inside a gradient-colored progress ring that scales in as
/// the list is pulled down, then spins (indeterminate) while the actual
/// refresh is in flight — replacing the plain default Material spinner.
class BrandedRefreshIndicator extends StatelessWidget {
  final IndicatorController controller;

  const BrandedRefreshIndicator({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    // dragging/armed states report 0.0-1.0+ progress; once loading, the
    // ring switches to Flutter's own indeterminate spin (value: null)
    // rather than sitting frozen at 1.0.
    final progress = controller.value.clamp(0.0, 1.0);
    final isLoading = controller.state.isLoading;

    return Padding(
      padding: const EdgeInsets.all(10),
      child: SizedBox(
        width: 38,
        height: 38,
        child: Stack(
          alignment: Alignment.center,
          children: [
            SizedBox(
              width: 38,
              height: 38,
              child: CircularProgressIndicator(
                strokeWidth: 2.6,
                value: isLoading ? null : progress,
                valueColor: const AlwaysStoppedAnimation(AppColors.primary),
                backgroundColor: AppColors.primary.withValues(alpha: .12),
              ),
            ),
            // Logo scales in as the user pulls, so it doesn't just pop
            // into existence at full size the moment the drag starts.
            Transform.scale(
              scale: 0.4 + (progress * 0.6),
              child: ClipOval(
                child: Image.asset(
                  'assets/images/attendx_logo.png',
                  width: 20,
                  height: 20,
                  fit: BoxFit.cover,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
