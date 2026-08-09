import 'package:flutter/material.dart';

/// Screen-size class, following the Material 3 window size classes that
/// the Flutter team recommends for adaptive layouts.
enum ScreenType { mobile, tablet, desktop }

class Responsive {
  Responsive._();

  static MediaQueryData? _mediaQuery;

  /// Seeded with the design size rather than left `late`.
  ///
  /// These used to be `late` with no initialiser, so anything that read
  /// a size before some widget had called [init] threw a
  /// LateInitializationError. That is a very easy trap: AppTextStyles
  /// computes its font sizes through [sp] in a lazy static initialiser,
  /// so merely *mentioning* AppTextStyles.headline on a screen that
  /// hadn't called init would throw — and in a release web build a throw
  /// during build paints a blank grey page with no message at all.
  ///
  /// A text style should never be able to take the whole app down. The
  /// design dimensions are a correct answer until a real MediaQuery
  /// arrives, and [init] overwrites them on the first build anyway.
  static double screenWidth = _designWidth;
  static double screenHeight = _designHeight;

  // ------------------------------------------------------------------
  // Breakpoints. Kept here as the single source of truth so every screen
  // shifts layout at the same widths instead of each one inventing its
  // own thresholds.
  // ------------------------------------------------------------------
  static const double mobileMaxWidth = 600;
  static const double tabletMaxWidth = 1200;

  /// How much a large phone is allowed to inflate the design sizes.
  ///
  /// Every size in this app is expressed against a 390 x 844 phone.
  /// A 430px phone can carry slightly larger text and padding; beyond
  /// about 15% it just looks blown up.
  static const double _maxPhoneScale = 1.15;

  static const double _minPhoneScale = 0.85;

  /// Comfortable reading width for a single column of content on a wide
  /// screen. Content wider than this gets centred rather than stretched.
  static const double contentMaxWidth = 1100;

  static const double _designWidth = 390;
  static const double _designHeight = 844;

  static void init(BuildContext context) {
    final query = MediaQuery.of(context);
    _mediaQuery = query;

    screenWidth = query.size.width;
    screenHeight = query.size.height;
  }

  /// The multiplier applied to every design-time size.
  ///
  /// On a phone this tracks the screen, so a 430px handset gets slightly
  /// roomier text than a 360px one. On a tablet or a browser it is
  /// exactly 1 — design sizes, unscaled.
  ///
  /// That flat 1 is deliberate. Scaling a phone ratio up to desktop
  /// widths is what made the console's text and padding look inflated:
  /// a 14px label became 19px and an 18px gutter became 28px, which
  /// reads as a phone app stretched over a monitor rather than a desktop
  /// tool. Desktop UI conventions are already expressed in the design
  /// numbers; the right thing to do on a big screen is use more of it
  /// for layout, not to make everything bigger.
  static double get _scale {
    if (screenWidth >= mobileMaxWidth) return 1;
    return (screenWidth / _designWidth)
        .clamp(_minPhoneScale, _maxPhoneScale);
  }

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

  static double w(double value) => value * _scale;

  /// Vertical sizes track screen height on phones, where a tall handset
  /// really does want more breathing room. On anything larger the design
  /// value is used as-is: a browser window is short and wide, so
  /// following its height would squash spacing rather than open it up.
  static double h(double value) {
    if (screenWidth >= mobileMaxWidth) return value;
    return screenHeight * (value / _designHeight);
  }

  static double sp(double value) => value * _scale;

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
