import 'package:flutter/material.dart';

class StatusBanner extends StatelessWidget {

  final String status;

  const StatusBanner({
    super.key,
    required this.status,
  });

  @override
  Widget build(BuildContext context) {

    Color color;

    switch(status){

      case "approved":
        color=Colors.green;
        break;

      case "pending":
        color=Colors.orange;
        break;

      case "rejected":
        color=Colors.red;
        break;

      default:
        color=Colors.blueGrey;

    }

    return Container(

      padding: const EdgeInsets.symmetric(
        horizontal:16,
        vertical:8,
      ),

      decoration: BoxDecoration(

        color: color.withValues(alpha: .15),

        borderRadius: BorderRadius.circular(25),

      ),

      child: Row(

        mainAxisSize: MainAxisSize.min,

        children: [

          Icon(
            Icons.circle,
            size:10,
            color:color,
          ),

          const SizedBox(width:8),

          Text(

            status.toUpperCase(),

            style: TextStyle(
              color:color,
              fontWeight: FontWeight.bold,
            ),

          ),

        ],

      ),

    );
  }

}