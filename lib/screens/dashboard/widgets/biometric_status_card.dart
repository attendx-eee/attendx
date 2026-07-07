import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/responsive/responsive.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/widgets/primary_card.dart';
import '../../../core/widgets/section_header.dart';

class BiometricStatusCard extends StatelessWidget {
  final bool enrolled;
  final Timestamp? enrolledAt;
  final VoidCallback onPressed;

  const BiometricStatusCard({
    super.key,
    required this.enrolled,
    required this.enrolledAt,
    required this.onPressed,
  });

  String get enrollmentDate {
    if (enrolledAt == null) return "--";

    final date = enrolledAt!.toDate();

    return "${date.day}/${date.month}/${date.year}";
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [

        const SectionHeader(
          title: "Biometric Authentication",
          subtitle: "Secure facial authentication status",
        ),

        SizedBox(height: Responsive.h(18)),

        PrimaryCard(
          child: Column(
            children: [

              Row(
                children: [

                  CircleAvatar(
                    radius: Responsive.w(24),
                    backgroundColor: enrolled
                        ? Colors.green.shade100
                        : Colors.orange.shade100,
                    child: Icon(
                      enrolled
                          ? Icons.verified_user_rounded
                          : Icons.face_retouching_off,
                      color: enrolled
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
                          enrolled
                              ? "Biometrics Active"
                              : "Enrollment Required",
                          style: AppTextStyles.title,
                        ),

                        SizedBox(height: Responsive.h(4)),

                        Text(
                          enrolled
                              ? "Your facial identity is securely registered."
                              : "Register your face to enable attendance.",
                          style: AppTextStyles.body,
                        ),
                      ],
                    ),
                  ),
                ],
              ),

              SizedBox(height: Responsive.h(22)),

              Divider(),

              SizedBox(height: Responsive.h(18)),

              Row(
                mainAxisAlignment:
                    MainAxisAlignment.spaceBetween,
                children: [

                  Column(
                    crossAxisAlignment:
                        CrossAxisAlignment.start,
                    children: [

                      Text(
                        "Enrollment",
                        style: AppTextStyles.caption,
                      ),

                      SizedBox(height: Responsive.h(4)),

                      Text(
                        enrollmentDate,
                        style: AppTextStyles.body,
                      ),
                    ],
                  ),

                  Container(
                    padding: Responsive.symmetric(
                        horizontal: 12,
                        vertical: 6),
                    decoration: BoxDecoration(
                      color: enrolled
                          ? Colors.green.shade50
                          : Colors.orange.shade50,
                      borderRadius:
                          BorderRadius.circular(100),
                    ),
                    child: Text(
                      enrolled
                          ? "ACTIVE"
                          : "PENDING",
                      style: TextStyle(
                        color: enrolled
                            ? Colors.green
                            : Colors.orange,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  )
                ],
              ),

              SizedBox(height: Responsive.h(24)),

              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: onPressed,
                  icon: Icon(
                    enrolled
                        ? Icons.refresh
                        : Icons.face,
                  ),
                  label: Text(
                    enrolled
                        ? "Update Biometrics"
                        : "Enroll Face",
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}