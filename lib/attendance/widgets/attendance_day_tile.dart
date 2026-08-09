import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/attendance_palette.dart';
import '../models/day_summary.dart';

/// One date in a month grid.
///
/// A day isn't one number. A student can sit through both theory
/// lectures and skip the lab, and a single fill colour has to average
/// that into something that describes neither. So when a day has both,
/// the tile splits: theory on the left, lab on the right, each shaded by
/// its own attendance and labelled with its own count.
///
/// The date moves to the top-left corner to leave the middle free for
/// the split. Holidays take the whole tile and carry the occasion's name
/// instead of any counts, since there was nothing to attend.
class AttendanceDayTile extends StatelessWidget {
  final int day;

  /// Per-class counts. Null when the day has no timetable at all.
  final DaySummary? summary;

  /// Non-null when the college was closed. Outranks everything else.
  final String? holidayName;

  /// Colour the day resolves to without any class registers — the gate
  /// verdict. Used whole-tile when there's nothing finer to show.
  final Color fallbackFill;
  final Color fallbackText;

  final bool isToday;
  final bool selected;

  /// Small corner dot: a human set this day, not the scanner.
  final bool manual;

  /// Faded, for days that can't be acted on.
  final bool dimmed;

  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  const AttendanceDayTile({
    super.key,
    required this.day,
    required this.summary,
    required this.holidayName,
    required this.fallbackFill,
    required this.fallbackText,
    this.isToday = false,
    this.selected = false,
    this.manual = false,
    this.dimmed = false,
    this.onTap,
    this.onLongPress,
  });

  bool get _isHoliday => holidayName != null;

  /// Whether there's a theory/lab split worth drawing.
  bool get _splits {
    final s = summary;
    return !_isHoliday && s != null && s.total > 0;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // Below this the icons and fractions become unreadable smudges,
        // so the tile falls back to a plain two-tone split.
        final compact = constraints.maxWidth < 52;

        return Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: onTap,
            onLongPress: onLongPress,
            child: Opacity(
              opacity: dimmed ? .65 : 1,
              child: Container(
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  color: _isHoliday
                      ? holidayFill
                      : (_splits ? Colors.white : fallbackFill),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: selected
                        ? AppColors.primary
                        : (isToday ? AppColors.primary : AppColors.divider),
                    width: selected ? 3 : (isToday ? 2 : 1),
                  ),
                ),
                child: Stack(
                  children: [
                    if (_splits) _buildSplit(compact),
                    if (_isHoliday) _buildHoliday(compact),
                    _buildDate(),
                    if (manual)
                      // Ringed in white so it reads on a dark holiday
                      // fill and on a pale unmarked half alike.
                      Positioned(
                        top: 3,
                        right: 3,
                        child: Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: AppColors.primary,
                            shape: BoxShape.circle,
                            border:
                                Border.all(color: Colors.white, width: 1.5),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildDate() {
    // The corner is only worth the cramped type when something else
    // needs the middle. A day with no classes has nothing to show but
    // its number, so it keeps the centre.
    final cornered = _splits || _isHoliday;

    final label = Text(
      '$day',
      style: TextStyle(
        color: cornered
            ? Colors.white
            : (fallbackFill.a > .1 ? fallbackText : AppColors.textPrimary),
        fontWeight: FontWeight.w800,
        fontSize: cornered ? 10.5 : 12,
        height: 1,
        // The split puts the number over a white gap between two
        // coloured halves, where white-on-white would vanish.
        shadows: _splits
            ? const [
                Shadow(color: Colors.black54, blurRadius: 3),
                Shadow(color: Colors.black38, blurRadius: 6),
              ]
            : null,
      ),
    );

    return cornered
        ? Positioned(top: 3, left: 5, child: label)
        : Center(child: label);
  }

  Widget _buildHoliday(bool compact) {
    if (compact) {
      return const Center(
        child: Icon(Icons.beach_access_rounded,
            size: 12, color: Colors.white70),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 16, 4, 4),
      child: Center(
        child: Text(
          holidayName!,
          textAlign: TextAlign.center,
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w700,
            fontSize: 8.5,
            height: 1.15,
          ),
        ),
      ),
    );
  }

  Widget _buildSplit(bool compact) {
    final s = summary!;

    final halves = <Widget>[
      if (s.theoryTotal > 0)
        Expanded(
          child: _Half(
            icon: Icons.menu_book_rounded,
            label: 'Theory',
            attended: s.theoryAttended,
            total: s.theoryTotal,
            marked: s.theoryMarked,
            ratio: s.theoryRatio,
            compact: compact,
          ),
        ),
      if (s.labTotal > 0)
        Expanded(
          child: _Half(
            icon: Icons.science_rounded,
            label: 'Lab',
            attended: s.labAttended,
            total: s.labTotal,
            marked: s.labMarked,
            ratio: s.labRatio,
            compact: compact,
          ),
        ),
    ];

    return Positioned.fill(
      child: Row(
        children: [
          for (var i = 0; i < halves.length; i++) ...[
            if (i > 0)
              const VerticalDivider(
                  width: 1, thickness: 1, color: Colors.white54),
            halves[i],
          ],
        ],
      ),
    );
  }
}

/// One side of a split tile — theory or lab.
class _Half extends StatelessWidget {
  final IconData icon;
  final String label;
  final int attended;
  final int total;
  final int marked;
  final double ratio;
  final bool compact;

  const _Half({
    required this.icon,
    required this.label,
    required this.attended,
    required this.total,
    required this.marked,
    required this.ratio,
    required this.compact,
  });

  @override
  Widget build(BuildContext context) {
    // Nothing registered yet stays white. An unmarked class is not an
    // absence, and colouring it red would invent one every time a
    // lecturer was slow to submit.
    final pending = marked == 0;
    final fill = pending ? Colors.white : attendanceShade(ratio);
    final ink = pending ? AppColors.textSecondary : Colors.white;

    return Container(
      color: fill,
      // Leaves the top strip clear for the date in the corner. Smaller
      // when compact, where the whole tile is barely taller than this.
      padding: EdgeInsets.only(top: compact ? 6 : 12),
      child: FittedBox(
        // The halves get whatever width seven columns leaves them, which
        // on a narrow phone is very little. Scaling down beats an
        // overflow stripe across the calendar.
        fit: BoxFit.scaleDown,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: compact ? 9 : 12, color: ink),
            if (!compact) ...[
              const SizedBox(height: 1),
              Text(
                '$attended/$total',
                maxLines: 1,
                style: TextStyle(
                  color: ink,
                  fontWeight: FontWeight.w800,
                  fontSize: 9.5,
                  height: 1,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
