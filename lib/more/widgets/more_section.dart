import 'package:flutter/material.dart';

import '../../core/responsive/responsive.dart';
import '../../core/theme/app_spacing.dart';
import '../models/more_item.dart';
import 'more_tile.dart';

class MoreSection extends StatelessWidget {
  final String title;
  final List<MoreItem> items;

  const MoreSection({
    super.key,
    required this.title,
    required this.items,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [

        Padding(
          padding: EdgeInsets.only(
            left: Responsive.w(6),
            bottom: Responsive.h(10),
          ),
          child: Text(
            title.toUpperCase(),
            style: TextStyle(
              fontSize: Responsive.sp(12),
              fontWeight: FontWeight.w700,
              color: Colors.grey.shade600,
              letterSpacing: 1.1,
            ),
          ),
        ),

        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 16,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Column(
            children: List.generate(items.length, (index) {
              return Column(
                children: [

                  MoreTile(item: items[index]),

                  if (index != items.length - 1)
                    Divider(
                      indent: Responsive.w(74),
                      endIndent: Responsive.w(18),
                      height: 1,
                      thickness: .6,
                      color: Colors.grey.shade200,
                    ),
                ],
              );
            }),
          ),
        ),

        SizedBox(height: Responsive.h(AppSpacing.lg)),
      ],
    );
  }
}