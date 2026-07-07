import 'package:flutter/material.dart';

import '../responsive/responsive.dart';
import '../theme/app_colors.dart';

class PrimaryButton extends StatelessWidget {

  final String text;

  final IconData? icon;

  final VoidCallback onPressed;

  final Color? color;

  const PrimaryButton({

    super.key,

    required this.text,

    required this.onPressed,

    this.icon,

    this.color,
  });

  @override
  Widget build(BuildContext context) {

    return SizedBox(

      width: double.infinity,

      height: Responsive.h(54),

      child: ElevatedButton.icon(

        onPressed: onPressed,

        icon: icon == null
            ? const SizedBox.shrink()
            : Icon(icon),

        label: Text(text),

        style: ElevatedButton.styleFrom(

          elevation: 0,

          backgroundColor: color ?? AppColors.primary,

          foregroundColor: Colors.white,

          shape: RoundedRectangleBorder(

            borderRadius: BorderRadius.circular(

              Responsive.radius(18),

            ),
          ),
        ),
      ),
    );
  }
}