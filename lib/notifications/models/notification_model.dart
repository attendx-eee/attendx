import 'package:cloud_firestore/cloud_firestore.dart';

class AppNotification {
  final String id;
  final String title;
  final String body;
  final String category;
  final String priority;
  final String studentUid;
  final bool read;
  final Timestamp createdAt;
  final String? action;
  final Map<String, dynamic>? data;

  const AppNotification({
    required this.id,
    required this.title,
    required this.body,
    required this.category,
    required this.priority,
    required this.studentUid,
    required this.read,
    required this.createdAt,
    this.action,
    this.data,
  });

  factory AppNotification.fromFirestore(DocumentSnapshot doc) {
    final json = doc.data() as Map<String, dynamic>;

    return AppNotification(
      id: doc.id,
      title: json['title'] ?? '',
      body: json['body'] ?? '',
      category: json['category'] ?? 'general',
      priority: json['priority'] ?? 'normal',
      studentUid: json['studentUid'] ?? '',
      read: json['read'] ?? false,
      createdAt: json['createdAt'] ?? Timestamp.now(),
      action: json['action'],
      data: json['data'] == null
          ? null
          : Map<String, dynamic>.from(json['data']),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'title': title,
      'body': body,
      'category': category,
      'priority': priority,
      'studentUid': studentUid,
      'read': read,
      'createdAt': createdAt,
      'action': action,
      'data': data,
    };
  }
}