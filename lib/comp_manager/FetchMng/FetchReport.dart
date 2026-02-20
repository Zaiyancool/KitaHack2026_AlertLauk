import 'package:flutter/material.dart';

import 'package:cloud_firestore/cloud_firestore.dart';

class ReportDetails {
  final String reportId;
  final String description;
  final String location;
  final String status;
  final String type;
  final DateTime timestamp;

  ReportDetails({
    required this.reportId,
    required this.description,
    required this.location,
    required this.status,
    required this.type,
    required this.timestamp,
  });

  factory ReportDetails.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return ReportDetails(
      reportId: data['ID'] ?? '',
      description: data['Details'] ?? '',
      location: data['Location'] ?? '',
      status: data['Status'] ?? '',
      type: data['Type'] ?? '',
      timestamp: (data['time'] as Timestamp).toDate(),
    );
  }
  
}

Future<List<ReportDetails>> fetchReports() async {
  List<ReportDetails> reports = [];

  try {
    final snapshot = await FirebaseFirestore.instance
        .collection('reports')
        .orderBy('Time', descending: true)
        .get();

      debugPrint("Fetched ${snapshot.docs.length} reports");

    for (var doc in snapshot.docs) {
      debugPrint("Raw Firestore data: ${doc.data()}");

      final data = doc.data();

      reports.add(ReportDetails(
        reportId: data['ID'] ?? '',
        description: data['Details'] ?? '',
        location: data['Location'] ?? '',
        status: data['Status'] ?? '',
        type: data['Type'] ?? '',
        timestamp: (data['time'] as Timestamp?)?.toDate() ?? DateTime.now(),
      ));
    }
  } catch (e) {
    debugPrint("Error fetching reports: $e");
  }

  return reports;
}
