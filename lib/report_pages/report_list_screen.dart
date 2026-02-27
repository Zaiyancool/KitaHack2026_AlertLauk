import "package:flutter/material.dart";
import 'package:intl/intl.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_application_1/comp_manager/ReportBlock.dart';

class ReportListScreen extends StatefulWidget {
  const ReportListScreen({super.key});

  @override
  State<ReportListScreen> createState() => _ReportListScreenState();
}

class _ReportListScreenState extends State<ReportListScreen> {
  final reportsRef = FirebaseFirestore.instance.collection('reports');

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Report List'),
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: reportsRef.orderBy('Time', descending: true).snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return const Center(child: Text('No reports found.'));
          }

          // Convert Firestore docs to a list
          final reports = snapshot.data!.docs.map((doc) {
            final data = doc.data() as Map<String, dynamic>;
            return {
              'ID': data['ID'],
              'reportId': doc.id,
              'type': data['Type'] ?? '',
              'description': data['Details'] ?? '',
              'timestamp': data['Time']?.toDate() ?? DateTime.now(),
              'status': data['Status'] ?? 'Pending',
              'location': data['Location'] ?? '',
              'imageUrl': data['ImageURL'] ?? '',
            };
          }).toList();

          // Sort: SOS Pending first, then normal Pending, then Solved — latest first within each group
          reports.sort((a, b) {
            int priorityOf(Map<String, dynamic> r) {
              final isSolved = r['status'].toString().toLowerCase() == 'solved';
              if (isSolved) return 2; // Solved always last
              final isSOS = r['type'].toString().toUpperCase() == 'SOS';
              return isSOS ? 0 : 1; // SOS Pending = 0, Normal Pending = 1
            }

            final pa = priorityOf(a);
            final pb = priorityOf(b);
            if (pa != pb) return pa.compareTo(pb);
            // Within the same priority group, latest first
            return (b['timestamp'] as DateTime).compareTo(a['timestamp'] as DateTime);
          });

          return RefreshIndicator(
            onRefresh: () async {
              // Trigger a rebuild (StreamBuilder auto updates)
              setState(() {});
            },
            child: ListView.builder(
              itemCount: reports.length,
              itemBuilder: (context, index) {
                final report = reports[index];
                return ReportBlock(
                  reportId: report['ID'],
                  title: report['type'],
                  description: report['description'],
                  date: DateFormat('yyyy-MM-dd').format(report['timestamp']),
                  time: DateFormat('HH:mm:ss').format(report['timestamp']),
                  status: report['status'],
                  location: report['location'],
                  type: report['type'],
                  imageUrl: report['imageUrl'],
                );
              },
            ),
          );
        },
      ),
    );
  }
}