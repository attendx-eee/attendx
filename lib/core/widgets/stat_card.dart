import 'package:flutter/material.dart';

import '../responsive/responsive.dart';
import '../theme/app_text_styles.dart';
import 'primary_card.dart';

class StatCard extends StatelessWidget {

  final IconData icon;

  final String title;

  final String value;

  final Color color;

  const StatCard({
    super.key,
    required this.icon,
    required this.title,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {

    return PrimaryCard(

      child: Column(

        crossAxisAlignment: CrossAxisAlignment.start,

        children: [

          CircleAvatar(

            radius: Responsive.w(22),

            backgroundColor: color.withValues(alpha: .12),

            child: Icon(
              icon,
              color: color,
              size: Responsive.sp(22),
            ),
          ),

          SizedBox(height: Responsive.h(18)),

          Text(
            value,
            style: AppTextStyles.headline.copyWith(
              color: color,
            ),
          ),

          SizedBox(height: Responsive.h(4)),

          Text(
            title,
            style: AppTextStyles.body,
          ),
        ],
      ),
    );
  }
}