import 'package:flutter/material.dart';

import '../../core/responsive/responsive.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_colors.dart';

class StorageCard extends StatelessWidget {
  final double cacheSizeMB;
  final double databaseSizeMB;
  final double imagesSizeMB;
  final VoidCallback onClearCache;

  const StorageCard({
    super.key,
    required this.cacheSizeMB,
    required this.databaseSizeMB,
    required this.imagesSizeMB,
    required this.onClearCache,
  });

  double get total =>
      cacheSizeMB +
      databaseSizeMB +
      imagesSizeMB;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: Responsive.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: .04),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment:
            CrossAxisAlignment.start,
        children: [

          Row(
            children: [

              Container(
                padding: EdgeInsets.all(
                  Responsive.w(12),
                ),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(
                    alpha: .10,
                  ),
                  borderRadius:
                      BorderRadius.circular(14),
                ),
                child: Icon(
                  Icons.storage_rounded,
                  color: AppColors.primary,
                  size: Responsive.sp(24),
                ),
              ),

              SizedBox(width: Responsive.w(14)),

              Expanded(
                child: Column(
                  crossAxisAlignment:
                      CrossAxisAlignment.start,
                  children: [

                    Text(
                      "Storage",
                      style: TextStyle(
                        fontSize:
                            Responsive.sp(16),
                        fontWeight:
                            FontWeight.bold,
                      ),
                    ),

                    Text(
                      "${total.toStringAsFixed(1)} MB Used",
                      style: TextStyle(
                        color:
                            Colors.grey.shade600,
                        fontSize:
                            Responsive.sp(12),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          SizedBox(height: Responsive.h(22)),

          _item(
            "Application Cache",
            cacheSizeMB,
            Colors.orange,
          ),

          SizedBox(height: Responsive.h(14)),

          _item(
            "Offline Database",
            databaseSizeMB,
            Colors.green,
          ),

          SizedBox(height: Responsive.h(14)),

          _item(
            "Images",
            imagesSizeMB,
            Colors.blue,
          ),

          SizedBox(height: Responsive.h(24)),

          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              icon: const Icon(
                Icons.cleaning_services_rounded,
              ),
              label: const Text(
                "Clear Cache",
              ),
              onPressed: onClearCache,
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.red,
                side: BorderSide(
                  color: Colors.red.shade200,
                ),
                shape:
                    RoundedRectangleBorder(
                  borderRadius:
                      BorderRadius.circular(14),
                ),
                padding: EdgeInsets.symmetric(
                  vertical: Responsive.h(14),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _item(
      String title,
      double value,
      Color color,
      ) {
    return Column(
      crossAxisAlignment:
          CrossAxisAlignment.start,
      children: [

        Row(
          mainAxisAlignment:
              MainAxisAlignment.spaceBetween,
          children: [

            Text(
              title,
              style: TextStyle(
                fontSize: Responsive.sp(13),
              ),
            ),

            Text(
              "${value.toStringAsFixed(1)} MB",
              style: TextStyle(
                fontWeight:
                    FontWeight.w600,
                fontSize:
                    Responsive.sp(13),
              ),
            ),
          ],
        ),

        SizedBox(height: Responsive.h(6)),

        LinearProgressIndicator(
          value: total == 0
              ? 0
              : value / total,
          borderRadius:
              BorderRadius.circular(10),
          color: color,
          backgroundColor:
              Colors.grey.shade200,
          minHeight: Responsive.h(7),
        ),
      ],
    );
  }
}