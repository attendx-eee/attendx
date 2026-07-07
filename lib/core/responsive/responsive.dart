import 'package:flutter/material.dart';

class Responsive {
  Responsive._();

  static late MediaQueryData _mediaQuery;

  static late double screenWidth;
  static late double screenHeight;

  static void init(BuildContext context) {
    _mediaQuery = MediaQuery.of(context);

    screenWidth = _mediaQuery.size.width;
    screenHeight = _mediaQuery.size.height;
  }

  static double w(double value) =>
      screenWidth * (value / 390);

  static double h(double value) =>
      screenHeight * (value / 844);

  static double sp(double value) {
    final scale = screenWidth / 390;
    return (value * scale).clamp(
      value * 0.85,
      value * 1.35,
    );
  }

  static double radius(double value) =>
      w(value);

  static EdgeInsets all(double value) =>
      EdgeInsets.all(w(value));

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