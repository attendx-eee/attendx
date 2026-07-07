import 'package:flutter/material.dart';

import '../controllers/timetable_controller.dart';
import '../widgets/day_selector.dart';
import '../widgets/period_card.dart';
import '../widgets/status_banner.dart';

class TimetableHome extends StatefulWidget {
  final String year;
  final String semester;
  final String section;

  const TimetableHome({
    super.key,
    required this.year,
    required this.semester,
    required this.section,
  });

  @override
  State<TimetableHome> createState() => _TimetableHomeState();
}

class _TimetableHomeState extends State<TimetableHome> {
  final controller = TimetableController();

  @override
  void initState() {
    super.initState();
    _loadTimetable();
    controller.addListener(update);
  }

  // CRITICAL FIX: Listen for parameter changes from the parent widget
  @override
  void didUpdateWidget(covariant TimetableHome oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.year != widget.year ||
        oldWidget.semester != widget.semester ||
        oldWidget.section != widget.section) {
      _loadTimetable();
    }
  }

  void _loadTimetable() {
    controller.load(
      year: widget.year,
      semester: widget.semester,
      section: widget.section,
    );
  }

  void update() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    controller.removeListener(update);
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("${widget.year} Year  ${widget.section}"),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadTimetable, // Simplified tear-off assignment
          ),
        ],
      ),
      body: _buildBody(context), // Pass context explicitly for best practices
    );
  }

  Widget _buildBody(BuildContext context) {
    if (controller.loading) {
      return const Center(
        child: CircularProgressIndicator(),
      );
    }

    if (controller.timetable == null) {
      return const Center(
        child: Text("No timetable available"),
      );
    }

    final periodsForDay = controller.timetable!.periods[controller.selectedDay] ?? [];

    return Column(
      children: [
        const SizedBox(height: 16),
        DaySelector(
          selectedDay: controller.selectedDay,
          onChanged: controller.changeDay,
        ),
        const SizedBox(height: 16),
        StatusBanner(
          status: controller.timetable!.status,
        ),
        const SizedBox(height: 20),
        Expanded(
          child: periodsForDay.isEmpty
              ? const Center(child: Text("No classes for this day"))
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: periodsForDay.length,
                  itemBuilder: (context, index) {
                    final period = periodsForDay[index];
                    return PeriodCard(
                      period: period,
                      onTap: () {
                        // opens period editor
                      },
                    );
                  },
                ),
        ),
      ],
    );
  }
}