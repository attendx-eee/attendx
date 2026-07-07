import 'package:flutter/material.dart';
import '../../core/responsive/responsive.dart';

class DaySelector extends StatelessWidget {

  final String selectedDay;

  final Function(String) onChanged;

  const DaySelector({

    super.key,

    required this.selectedDay,

    required this.onChanged,

  });

  static const days=[

    "Monday",
    "Tuesday",
    "Wednesday",
    "Thursday",
    "Friday",
    "Saturday",

  ];

  @override
  Widget build(BuildContext context) {

    return SizedBox(

      height: Responsive.h(45),

      child: ListView.builder(

        scrollDirection: Axis.horizontal,

        itemCount: days.length,

        itemBuilder:(context,index){

          final day=days[index];

          final selected=day==selectedDay;

          return Padding(

            padding: EdgeInsets.only(
              right: Responsive.w(10),
            ),

            child: ChoiceChip(

              label: Text(
                day.substring(0,3),
              ),

              selected:selected,

              onSelected:(_){

                onChanged(day);

              },

            ),

          );

        },

      ),

    );

  }

}