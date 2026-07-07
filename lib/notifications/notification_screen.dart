import 'package:flutter/material.dart';

import '../../core/responsive/responsive.dart';
import '../../core/theme/app_spacing.dart';
import 'models/notification_model.dart';
import 'services/notification_service.dart';
import 'widgets/empty_notification.dart';
import 'widgets/notification_card.dart';
import 'widgets/notification_filter_bar.dart';

class NotificationScreen extends StatefulWidget {
  const NotificationScreen({super.key});

  @override
  State<NotificationScreen> createState() => _NotificationScreenState();
}

class _NotificationScreenState extends State<NotificationScreen> {

  final NotificationService service =
      NotificationService.instance;

  String selectedFilter = "All";

  List<AppNotification> _applyFilter(
      List<AppNotification> list) {

    if (selectedFilter == "All") {
      return list;
    }

    if (selectedFilter == "Unread") {
      return list.where((e) => !e.read).toList();
    }

    return list.where(
      (e) =>
          e.category.toLowerCase() ==
          selectedFilter.toLowerCase(),
    ).toList();
  }

  @override
  Widget build(BuildContext context) {

    return Scaffold(

      backgroundColor: Colors.grey.shade100,

      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.white,
        centerTitle: false,
        title: Text(
          "Notifications",
          style: TextStyle(
            color: Colors.black87,
            fontSize: Responsive.sp(20),
            fontWeight: FontWeight.bold,
          ),
        ),
        actions: [

          TextButton.icon(
            onPressed: () {
              service.markAllAsRead();
            },
            icon: const Icon(Icons.done_all),
            label: const Text("Read All"),
          ),

          SizedBox(width: Responsive.w(10)),
        ],
      ),

      body: Column(
        children: [

          Padding(
            padding: Responsive.all(AppSpacing.md),
            child: NotificationFilterBar(
              selected: selectedFilter,
              onChanged: (value) {
                setState(() {
                  selectedFilter = value;
                });
              },
            ),
          ),

          Expanded(
            child: StreamBuilder<List<AppNotification>>(

              stream: service.notifications(),

              builder: (context, snapshot) {

                if (snapshot.connectionState ==
                    ConnectionState.waiting) {
                  return const Center(
                    child: CircularProgressIndicator(),
                  );
                }

                if (snapshot.hasError) {
                  return Center(
                    child: Text(
                      "Unable to load notifications",
                      style: TextStyle(
                        fontSize: Responsive.sp(15),
                      ),
                    ),
                  );
                }

                final notifications =
                    _applyFilter(snapshot.data ?? []);

                if (notifications.isEmpty) {
                  return const EmptyNotification();
                }

                return RefreshIndicator(

                  onRefresh: () async {},

                  child: ListView.builder(

                    physics:
                        const AlwaysScrollableScrollPhysics(),

                    padding:
                        Responsive.all(AppSpacing.md),

                    itemCount: notifications.length,

                    itemBuilder: (context, index) {

                      final item = notifications[index];

                      return NotificationCard(

                        notification: item,

                        onTap: () async {

                          if (!item.read) {
                            await service.markAsRead(item.id);
                          }

                          _handleAction(item);
                        },

                        onDelete: () {
                          service.deleteNotification(item.id);
                        },
                      );
                    },
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  void _handleAction(AppNotification notification) {

    switch (notification.action) {

      case "attendance":

        // open attendance screen

        break;

      case "leave":

        // open leave screen

        break;

      case "profile":

        // open profile

        break;

      case "exam":

        // open exams

        break;

      case "security":

        // open security page

        break;

      case "announcement":

        // announcement details

        break;

      default:

        break;
    }
  }
}