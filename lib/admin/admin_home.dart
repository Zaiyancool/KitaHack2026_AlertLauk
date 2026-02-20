import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:url_launcher/url_launcher.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
//import 'dart:js' as js;

class AdminHomePage extends StatefulWidget {
  const AdminHomePage({super.key});

  @override
  State<AdminHomePage> createState() => _AdminHomePageState();
}

class _AdminHomePageState extends State<AdminHomePage> {
  final reportsRef = FirebaseFirestore.instance.collection('reports');
  final commentsRef = FirebaseFirestore.instance.collection('comments_reports');

  Future<void> openMap(GeoPoint point) async {
  final url =
      'https://www.google.com/maps/search/?api=1&query=${point.latitude},${point.longitude}';
  try {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open map.')),
      );
    }
  } catch (e) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Error opening map: $e')),
    );
  }
}

  Future<void> signOut() async {
    await FirebaseAuth.instance.signOut();
  }

  void showComments(String reportId) {
    showDialog(
      context: context,
      builder: (context) {
        return StreamBuilder<DocumentSnapshot>(
          stream: commentsRef.doc(reportId).snapshots(),
          builder: (context, snapshot) {
            if (!snapshot.hasData || !snapshot.data!.exists) {
              return AlertDialog(
                title: const Text("Comments"),
                content: const Text("No comments yet."),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text("Close"),
                  ),
                ],
              );
            }

            final commentData =
                snapshot.data!.data() as Map<String, dynamic>?;

            final comments =
                List<String>.from(commentData?['Comments'] ?? []);

            return AlertDialog(
              title: const Text("Comments"),
              content: SizedBox(
                width: double.maxFinite,
                child: comments.isEmpty
                    ? const Text("No comments yet.")
                    : ListView.builder(
                        shrinkWrap: true,
                        itemCount: comments.length,
                        itemBuilder: (context, index) {
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 2),
                            child: Text("- ${comments[index]}"),
                          );
                        },
                      ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text("Close"),
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Admin Reports"),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: "Sign Out",
            onPressed: () async {
              await signOut();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Signed out successfully')),
              );
            },
          ),
        ],
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: reportsRef.orderBy('Time', descending: true).snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          List<QueryDocumentSnapshot> reports = snapshot.data!.docs;

          if (reports.isEmpty) {
            return const Center(child: Text("No reports found"));
          }

          // Sort: Pending SOS first, then other Pending, then Solved
          reports.sort((a, b) {
            final statusA = a['Status'] as String;
            final statusB = b['Status'] as String;
            final typeA = a['Type'] ?? '';
            final typeB = b['Type'] ?? '';

            if (statusA == 'Pending' && typeA == 'SOS') return -1;
            if (statusB == 'Pending' && typeB == 'SOS') return 1;

            if (statusA == statusB) return 0;
            return statusA == 'Pending' ? -1 : 1;
          });

          return ListView.builder(
            itemCount: reports.length,
            itemBuilder: (context, index) {
              final report = reports[index];
              final id = report['ID'] ?? report.id;
              final geoPoint = report['GeoPoint'] as GeoPoint?;
              final status = report['Status'] as String;
              final type = report['Type'] ?? '';
              final details = report['Details'] ?? '';
              final username = report['Username'] ?? '';
              final location = report['Location'] ?? '';

              Color cardColor;
              if (status == 'Pending' && type == 'SOS') {
                cardColor = Colors.redAccent.shade100;
              } else if (status == 'Pending') {
                cardColor = Colors.red.shade50;
              } else {
                cardColor = Colors.green.shade50;
              }

              final statusColor =
                  status == 'Pending' ? Colors.red : Colors.green;

              return Card(
                color: cardColor,
                margin:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Padding(
                  padding: const EdgeInsets.all(12.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Report Info
                      Text(
                        "ID: $id",
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text("Details: $details"),
                      Text("Type: $type"),
                      Row(
                        children: [
                          const Text("Location: "),
                          geoPoint != null
                              ? GestureDetector(
                                  onTap: () => openMap(geoPoint),
                                  child: Text(
                                    "$location",
                                    style: const TextStyle(
                                      color: Colors.blue,
                                      decoration: TextDecoration.underline,
                                    ),
                                  ),
                                )
                              : Text("$location"),
                        ],
                      ),
                      Text(
                        "Status: $status",
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: statusColor,
                        ),
                      ),
                      Text("User: $username"),
                      const SizedBox(height: 8),

                      // Responsive Buttons
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          ElevatedButton.icon(
                            onPressed: () => showComments(id),
                            icon: const Icon(Icons.comment,
                                color: Colors.white),
                            label: const Text('View Comments'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.blue,
                              foregroundColor: Colors.white,
                            ),
                          ),
                          if (status == 'Pending')
                            ElevatedButton.icon(
                              onPressed: () async {
                                try {
                                  await reportsRef
                                      .doc(report.id)
                                      .update({'Status': 'Solved'});
                                  ScaffoldMessenger.of(context)
                                      .showSnackBar(
                                    const SnackBar(
                                        content:
                                            Text('Marked as Resolved')),
                                  );
                                } catch (e) {
                                  ScaffoldMessenger.of(context)
                                      .showSnackBar(
                                    SnackBar(content: Text('Error: $e')),
                                  );
                                }
                              },
                              icon: const Icon(Icons.check,
                                  color: Colors.white),
                              label: const Text('Mark as Resolved'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.green,
                                foregroundColor: Colors.white,
                              ),
                            ),
                          if (status == 'Solved')
                            ElevatedButton.icon(
                              onPressed: () async {
                                try {
                                  await reportsRef
                                      .doc(report.id)
                                      .update({'Status': 'Pending'});
                                  ScaffoldMessenger.of(context)
                                      .showSnackBar(
                                    const SnackBar(
                                        content:
                                            Text('Marked as Unresolved')),
                                  );
                                } catch (e) {
                                  ScaffoldMessenger.of(context)
                                      .showSnackBar(
                                    SnackBar(content: Text('Error: $e')),
                                  );
                                }
                              },
                              icon: const Icon(Icons.undo,
                                  color: Colors.white),
                              label: const Text('Mark as Unresolved'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.red,
                                foregroundColor: Colors.white,
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}