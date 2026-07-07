import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../../core/responsive/responsive.dart';
import '../../../core/widgets/primary_card.dart';
import '../../../core/widgets/section_header.dart';
import '../../../core/theme/app_text_styles.dart';

class TodayAttendanceCard extends StatelessWidget {
  final DocumentSnapshot<Map<String, dynamic>>? attendanceDoc;

  const TodayAttendanceCard({
    super.key,
    required this.attendanceDoc,
  });

  @override
  Widget build(BuildContext context) {
    final data = attendanceDoc?.data();

    final Timestamp? checkIn = data?["checkIn"];
    final Timestamp? checkOut = data?["checkOut"];

    final bool checkedIn = checkIn != null;
    final bool checkedOut = checkOut != null;

    String formatTime(Timestamp? ts) {
      if (ts == null) return "--:--";
      final d = ts.toDate();

      final h = d.hour > 12 ? d.hour - 12 : d.hour;
      final m = d.minute.toString().padLeft(2, '0');
      final ap = d.hour >= 12 ? "PM" : "AM";

      return "$h:$m $ap";
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [

        const SectionHeader(
          title: "Today's Attendance",
          subtitle: "Live attendance session",
        ),

        SizedBox(height: Responsive.h(18)),

        PrimaryCard(
          child: Column(
            children: [

              Row(
                children: [

                  CircleAvatar(
                    radius: Responsive.w(24),
                    backgroundColor: checkedIn
                        ? Colors.green.shade100
                        : Colors.orange.shade100,
                    child: Icon(
                      checkedIn
                          ? Icons.login
                          : Icons.pending_actions,
                      color: checkedIn
                          ? Colors.green
                          : Colors.orange,
                    ),
                  ),

                  SizedBox(width: Responsive.w(16)),

                  Expanded(
                    child: Column(
                      crossAxisAlignment:
                          CrossAxisAlignment.start,
                      children: [

                        Text(
                          checkedIn
                              ? "Checked In"
                              : "Not Checked In",
                          style: AppTextStyles.title,
                        ),

                        SizedBox(height: Responsive.h(4)),

                        Text(
                          checkedIn
                              ? "Attendance session active"
                              : "Waiting for today's verification",
                          style: AppTextStyles.body,
                        ),
                      ],
                    ),
                  )
                ],
              ),

              SizedBox(height: Responsive.h(24)),

              Divider(),

              SizedBox(height: Responsive.h(18)),

              Row(
                mainAxisAlignment:
                    MainAxisAlignment.spaceBetween,
                children: [

                  _item(
                    "Check In",
                    formatTime(checkIn),
                  ),

                  _item(
                    "Check Out",
                    formatTime(checkOut),
                  ),
                ],
              ),

              SizedBox(height: Responsive.h(20)),

              Align(
                alignment: Alignment.centerLeft,
                child: Chip(
                  backgroundColor: checkedOut
                      ? Colors.blue.shade50
                      : checkedIn
                          ? Colors.green.shade50
                          : Colors.orange.shade50,
                  label: Text(
                    checkedOut
                        ? "Completed"
                        : checkedIn
                            ? "In Progress"
                            : "Pending",
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _item(String title, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [

        Text(
          title,
          style: AppTextStyles.caption,
        ),

        SizedBox(height: Responsive.h(4)),

        Text(
          value,
          style: AppTextStyles.body,
        ),
      ],
    );
  }
}