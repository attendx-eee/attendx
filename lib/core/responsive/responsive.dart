import 'package:flutter/material.dart';

/// Screen-size class, following the Material 3 window size classes that
/// the Flutter team recommends for adaptive layouts.
enum ScreenType { mobile, tablet, desktop }

class Responsive {
  Responsive._();

  static late MediaQueryData _mediaQuery;

  static late double screenWidth;
  static late double screenHeight;

  // ------------------------------------------------------------------
  // Breakpoints. Kept here as the single source of truth so every screen
  // shifts layout at the same widths instead of each one inventing its
  // own thresholds.
  // ------------------------------------------------------------------
  static const double mobileMaxWidth = 600;
  static const double tabletMaxWidth = 1200;

  /// The widest the phone-ratio scaling is allowed to follow.
  ///
  /// Every size in this app is expressed against a 390 x 844 phone. Left
  /// unbounded that ratio is fine on phones and ruinous on a browser: at
  /// 1920px wide, an 18px padding becomes 88px and a card fills half the
  /// window. Past this width the scale simply stops growing, so a desktop
  /// gets phone-sized padding and desktop-sized layouts, which is what
  /// actually reads well.
  static const double _maxScaleWidth = 600;

  /// Comfortable reading width for a single column of content on a wide
  /// screen. Content wider than this gets centred rather than stretched.
  static const double contentMaxWidth = 1100;

  static const double _designWidth = 390;
  static const double _designHeight = 844;

  static void init(BuildContext context) {
    _mediaQuery = MediaQuery.of(context);

    screenWidth = _mediaQuery.size.width;
    screenHeight = _mediaQuery.size.height;
  }

  /// Width the scaling maths uses — real width on phones, clamped on
  /// anything larger.
  static double get _scaleWidth =>
      screenWidth > _maxScaleWidth ? _maxScaleWidth : screenWidth;

  static ScreenType get screenType {
    if (screenWidth < mobileMaxWidth) return ScreenType.mobile;
    if (screenWidth < tabletMaxWidth) return ScreenType.tablet;
    return ScreenType.desktop;
  }

  static bool get isMobile => screenType == ScreenType.mobile;
  static bool get isTablet => screenType == ScreenType.tablet;
  static bool get isDesktop => screenType == ScreenType.desktop;

  /// Wide enough for a side rail and multi-column content.
  static bool get isWide => screenWidth >= tabletMaxWidth;

  /// Picks a value per size class — the readable alternative to
  /// scattering `if (width > 1200)` checks through build methods.
  static T value<T>({
    required T mobile,
    T? tablet,
    T? desktop,
  }) {
    switch (screenType) {
      case ScreenType.desktop:
        return desktop ?? tablet ?? mobile;
      case ScreenType.tablet:
        return tablet ?? mobile;
      case ScreenType.mobile:
        return mobile;
    }
  }

  /// Sensible column count for a card grid at the current width.
  static int gridColumns({int mobile = 2, int tablet = 3, int desktop = 4}) =>
      value(mobile: mobile, tablet: tablet, desktop: desktop);

  static double w(double value) => _scaleWidth * (value / _designWidth);

  /// Vertical sizes track height on phones. On a desktop browser the
  /// window is short and wide, so following its height would squash
  /// spacing; past the scale cap the phone ratio is used instead.
  static double h(double value) {
    if (screenWidth > _maxScaleWidth) return value;
    return screenHeight * (value / _designHeight);
  }

  static double sp(double value) {
    final scale = _scaleWidth / _designWidth;
    return (value * scale).clamp(
      value * 0.85,
      value * 1.35,
    );
  }

  static double radius(double value) => w(value);

  static EdgeInsets all(double value) => EdgeInsets.all(w(value));

  static EdgeInsets symmetric({
    double horizontal = 0,
    double vertical = 0,
  }) {
    return EdgeInsets.symmetric(
      horizontal: w(horizontal),
      vertical: h(vertical),
    );
  }
}

/// Centres its child and caps how wide it can grow.
///
/// Dropped around a page body, this is what stops a list of cards from
/// spanning a 27-inch monitor edge to edge. On a phone it costs nothing —
/// the constraint is never reached.
class MaxWidthBody extends StatelessWidget {
  final Widget child;
  final double maxWidth;

  const MaxWidthBody({
    super.key,
    required this.child,
    this.maxWidth = Responsive.contentMaxWidth,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: child,
      ),
    );
  }
}
