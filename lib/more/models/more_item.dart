import 'package:flutter/material.dart';

class MoreItem {
  final String title;
  final String? subtitle;
  final IconData icon;
  final Color iconColor;
  final VoidCallback? onTap;
  final bool showArrow;
  final bool isDestructive;

  const MoreItem({
    required this.title,
    required this.icon,
    required this.iconColor,
    this.subtitle,
    this.onTap,
    this.showArrow = true,
    this.isDestructive = false,
  });
}