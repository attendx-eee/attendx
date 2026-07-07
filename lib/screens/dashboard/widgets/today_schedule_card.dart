import 'package:flutter/material.dart';

import '../../../core/responsive/responsive.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/primary_card.dart';
import '../../../core/widgets/section_header.dart';
import '../../../core/widgets/status_chip.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../timetable/models/timetable_override_model.dart';

class TodayScheduleCard extends StatelessWidget {
  final List<Map<String, dynamic>> classes;
  final String title;
  final String subtitle;

  const TodayScheduleCard({
    super.key,
    required this.classes,
    this.title = "Today's Schedule",
    this.subtitle = "Academic timetable",
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [

        SectionHeader(
          title: title,
          subtitle: subtitle,
        ),

        SizedBox(height: Responsive.h(18)),

        PrimaryCard(
          child: classes.isEmpty
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Text("No classes scheduled today"),
                  ),
                )
              : Column(
                  children: List.generate(
                    classes.length,
                    (index) => _ScheduleTile(
                      data: classes[index],
                      isLast: index == classes.length - 1,
                    ),
                  ),
                ),
        ),
      ],
    );
  }
}

class _ScheduleTile extends StatelessWidget {

  final Map<String, dynamic> data;
  final bool isLast;

  const _ScheduleTile({
    required this.data,
    required this.isLast,
  });

  String? get _status => data["status"];

  bool get _cancelled => _status == OverrideType.cancelled;
  bool get _replaced => _status == OverrideType.replacement;
  bool get _roomChanged => _status == OverrideType.roomChange;
  bool get _completed => data["completed"] == true;

  ChipState get _chipState {
    if (_cancelled) return ChipState.danger;
    if (_replaced) return ChipState.info;
    return ChipState.warning;
  }

  @override
  Widget build(BuildContext context) {

    return Opacity(
      opacity: _completed && !_cancelled ? 0.6 : 1,
      child: Column(
      children: [

        Row(

          children: [

            SizedBox(
              width: Responsive.w(56),
              child: Column(
                children: [

                  Text(
                    data["start"],
                    style: AppTextStyles.body,
                  ),

                  SizedBox(height: Responsive.h(4)),

                  Text(
                    data["end"],
                    style: AppTextStyles.caption,
                  )
                ],
              ),
            ),

            SizedBox(width: Responsive.w(18)),

            Expanded(

              child: Column(

                crossAxisAlignment: CrossAxisAlignment.start,

                children: [

                  Text(
                    data["subject"],
                    style: AppTextStyles.title.copyWith(
                      decoration:
                          _cancelled ? TextDecoration.lineThrough : null,
                      color: _cancelled
                          ? AppColors.textSecondary
                          : AppColors.textPrimary,
                    ),
                  ),

                  if (_replaced && (data["oldSubject"] ?? '') != '')
                    Text(
                      "was: ${data["oldSubject"]}",
                      style: AppTextStyles.caption.copyWith(
                        decoration: TextDecoration.lineThrough,
                      ),
                    ),

                  SizedBox(height: Responsive.h(4)),

                  Text(
                    data["faculty"],
                    style: AppTextStyles.body,
                  ),

                  SizedBox(height: Responsive.h(2)),

                  Text(
                    _roomChanged && (data["oldRoom"] ?? '') != ''
                        ? "${data["room"]} (was ${data["oldRoom"]})"
                        : data["room"],
                    style: AppTextStyles.caption,
                  ),

                  if ((data["note"] ?? '') != '') ...[
                    SizedBox(height: Responsive.h(2)),
                    Text(
                      "Note: ${data["note"]}",
                      style: AppTextStyles.caption
                          .copyWith(fontStyle: FontStyle.italic),
                    ),
                  ],
                ],
              ),
            ),

            if (_status != null)
              StatusChip(
                text: OverrideType.label(_status!),
                state: _chipState,
              )
            else if (_completed)
              const StatusChip(
                text: "COMPLETED",
                state: ChipState.success,
              )
            else
              Icon(
                Icons.chevron_right_rounded,
                color: Colors.grey.shade400,
              )

          ],
        ),

        if (!isLast) ...[
          SizedBox(height: Responsive.h(18)),
          const Divider(),
          SizedBox(height: Responsive.h(18)),
        ]

      ],
      ),
    );
  }
}
