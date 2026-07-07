import 'package:flutter/material.dart';
import '../../core/responsive/responsive.dart';
import '../models/period_model.dart';
import '../../core/theme/app_colors.dart';

class PeriodCard extends StatelessWidget {
  final PeriodModel period;
  final VoidCallback? onTap;

  const PeriodCard({
    super.key,
    required this.period,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final bool free = period.isFree;

    return Card(
      margin: EdgeInsets.only(bottom: Responsive.h(14)),
      elevation: 1.5,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: Responsive.all(18),
          child: Row(
            children: [

              SizedBox(
                width: Responsive.w(72),
                child: Column(
                  children: [

                    Text(
                      period.startTime,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: Responsive.sp(15),
                      ),
                    ),

                    SizedBox(height: Responsive.h(6)),

                    Text(
                      period.endTime,
                      style: TextStyle(
                        color: Colors.grey,
                        fontSize: Responsive.sp(12),
                      ),
                    ),
                  ],
                ),
              ),

              Container(
                width: 1,
                height: Responsive.h(70),
                color: Colors.grey.shade300,
              ),

              SizedBox(width: Responsive.w(18)),

              Expanded(
                child: free
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [

                          Row(
                            children: [

                              Icon(
                                Icons.free_breakfast,
                                color: Colors.green,
                                size: Responsive.sp(20),
                              ),

                              SizedBox(width: Responsive.w(8)),

                              Text(
                                "FREE PERIOD",
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: Colors.green,
                                  fontSize: Responsive.sp(15),
                                ),
                              ),
                            ],
                          ),

                          SizedBox(height: Responsive.h(8)),

                          Text(
                            "No class scheduled",
                            style: TextStyle(
                              color: Colors.grey,
                              fontSize: Responsive.sp(12),
                            ),
                          ),
                        ],
                      )
                    : Column(
                        crossAxisAlignment:
                            CrossAxisAlignment.start,
                        children: [

                          Text(
                            period.subject,
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: Responsive.sp(16),
                            ),
                          ),

                          SizedBox(height: Responsive.h(8)),

                          Text(
                            period.facultyName,
                            style: TextStyle(
                              color: Colors.grey.shade700,
                              fontSize: Responsive.sp(13),
                            ),
                          ),

                          SizedBox(height: Responsive.h(5)),

                          Row(
                            children: [

                              Icon(
                                Icons.meeting_room_outlined,
                                size: Responsive.sp(16),
                                color: AppColors.primary,
                              ),

                              SizedBox(width: Responsive.w(6)),

                              Text(
                                period.room,
                                style: TextStyle(
                                  fontSize: Responsive.sp(13),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
              ),

              Icon(
                Icons.chevron_right,
                color: Colors.grey,
              ),
            ],
          ),
        ),
      ),
    );
  }
}