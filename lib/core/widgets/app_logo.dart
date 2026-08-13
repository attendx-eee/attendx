import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// The AttendX mark, wherever the app signs its own name.
///
/// There were five of these before this widget existed, and only two of
/// them were the logo. The rest were stand-ins from the Material set —
/// a tick in a gradient circle on the admin rail, a graduation cap on
/// the student app bar — placeholders from early on that nobody went
/// back for. A student and an admin were looking at different marks for
/// the same product.
///
/// The asset is a square PNG with a white background, so it is clipped
/// to whatever shape it is asked for rather than composited. If it ever
/// fails to load the fallback is the wordmark's first letter on the
/// brand gradient, which still reads as AttendX — better than a broken
/// image icon, and better than the generic glyph it replaced.
class AppLogo extends StatelessWidget {
  final double size;

  /// Circle by default; pass a radius for the rounded-square treatment
  /// the mobile app bar uses.
  final double? borderRadius;

  /// Padding inside the shape. The mark has little breathing room of
  /// its own, so it needs some at small sizes.
  final double padding;

  /// A pale tinted plate behind the mark. Off by default — on a white
  /// card the logo is its own shape.
  final bool plate;

  const AppLogo({
    super.key,
    this.size = 40,
    this.borderRadius,
    this.padding = 0,
    this.plate = false,
  });

  @override
  Widget build(BuildContext context) {
    final shape = borderRadius == null
        ? null
        : BorderRadius.circular(borderRadius!);

    final image = Padding(
      padding: EdgeInsets.all(padding),
      child: Image.asset(
        'assets/images/attendx_logo.png',
        fit: BoxFit.contain,
        errorBuilder: (context, error, stack) => _Fallback(size: size),
      ),
    );

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: plate ? AppColors.primary.withValues(alpha: .08) : null,
        shape: shape == null ? BoxShape.circle : BoxShape.rectangle,
        borderRadius: shape,
      ),
      clipBehavior: Clip.antiAlias,
      child: image,
    );
  }
}

/// Shown only if the asset is missing from the bundle.
class _Fallback extends StatelessWidget {
  final double size;

  const _Fallback({required this.size});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(gradient: AppColors.brandGradient),
      alignment: Alignment.center,
      child: Text(
        'A',
        style: TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w800,
          fontSize: size * .5,
        ),
      ),
    );
  }
}
