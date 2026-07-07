import 'package:flutter/material.dart';

import '../../core/responsive/responsive.dart';
import '../../core/theme/app_spacing.dart';
import '../models/more_item.dart';

class MoreTile extends StatelessWidget {
  final MoreItem item;

  const MoreTile({
    super.key,
    required this.item,
  });

  @override
  Widget build(BuildContext context) {
    final Color textColor =
        item.isDestructive ? Colors.red : Colors.black87;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: item.onTap,
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: Responsive.w(AppSpacing.md),
            vertical: Responsive.h(14),
          ),
          child: Row(
            children: [

              Container(
                width: Responsive.w(46),
                height: Responsive.w(46),
                decoration: BoxDecoration(
                  color: item.iconColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(
                  item.icon,
                  color: item.iconColor,
                  size: Responsive.sp(22),
                ),
              ),

              SizedBox(width: Responsive.w(16)),

              Expanded(
                child: Column(
                  crossAxisAlignment:
                      CrossAxisAlignment.start,
                  children: [

                    Text(
                      item.title,
                      style: TextStyle(
                        fontSize: Responsive.sp(15),
                        fontWeight: FontWeight.w600,
                        color: textColor,
                      ),
                    ),

                    if (item.subtitle != null) ...[
                      SizedBox(height: Responsive.h(3)),
                      Text(
                        item.subtitle!,
                        style: TextStyle(
                          fontSize: Responsive.sp(12),
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ],
                  ],
                ),
              ),

              if (item.showArrow)
                Icon(
                  Icons.chevron_right_rounded,
                  size: Responsive.sp(22),
                  color: Colors.grey.shade500,
                ),
            ],
          ),
        ),
      ),
    );
  }
}