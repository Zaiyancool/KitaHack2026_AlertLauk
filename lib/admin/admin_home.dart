import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:url_launcher/url_launcher.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'admin_chat_page.dart';
import 'admin_dashboard.dart';

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
    final parentContext = context;
    showDialog(
      context: parentContext,
      builder: (dialogContext) {
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

            final rawComments = commentData?['Comments'] ?? [];

            if (rawComments.isEmpty) {
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

            // Parse comments into structured data
            final parsedComments = <Map<String, dynamic>>[];
            for (var comment in rawComments) {
              if (comment is Map) {
                parsedComments.add(Map<String, dynamic>.from(comment));
              } else {
                parsedComments.add({
                  'text': comment.toString(),
                  'timestamp': '',
                  'imageUrl': null,
                });
              }
            }

            // Sort by timestamp (newest first)
            parsedComments.sort((a, b) {
              final aTime = a['timestamp']?.toString() ?? '';
              final bTime = b['timestamp']?.toString() ?? '';
              if (aTime.isEmpty && bTime.isEmpty) return 0;
              if (aTime.isEmpty) return 1;
              if (bTime.isEmpty) return -1;
              return bTime.compareTo(aTime);
            });

            return AlertDialog(
              title: const Text("Comments"),
              content: SizedBox(
                width: double.maxFinite,
                height: 400,
                child: ListView.builder(
                        shrinkWrap: false,
                        itemCount: parsedComments.length,
                        itemBuilder: (context, index) {
                          final comment = parsedComments[index];
                          final text = comment['text']?.toString() ?? '';
                          final imgUrl = comment['imageUrl'];
                          final imageUrl = (imgUrl != null && imgUrl.toString() != 'null') 
                              ? imgUrl.toString() 
                              : null;
                          final timestamp = comment['timestamp']?.toString() ?? '';

                          return Card(
                            key: ValueKey('comment_${index}_${imageUrl ?? ''}'),
                            margin: const EdgeInsets.symmetric(vertical: 4),
                            child: Padding(
                              padding: const EdgeInsets.all(10),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  if (timestamp.isNotEmpty)
                                    Padding(
                                      padding: const EdgeInsets.only(bottom: 4),
                                      child: Text(
                                        _formatTimestamp(timestamp),
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: Colors.grey.shade600,
                                        ),
                                      ),
                                    ),
                                  if (text.isNotEmpty)
                                    Text(
                                      text,
                                      style: const TextStyle(fontSize: 14),
                                    ),
                                  if (imageUrl != null && imageUrl.isNotEmpty) ...[
                                    const SizedBox(height: 8),
                                    GestureDetector(
                                      onTap: () => _showCommentFullImage(parentContext, imageUrl),
                                      child: ClipRRect(
                                        borderRadius: BorderRadius.circular(8),
                                        child: Image.network(
                                          imageUrl,
                                          key: ValueKey('img_${imageUrl}_$index'),
                                          width: double.infinity,
                                          height: 180,
                                          fit: BoxFit.cover,
                                          loadingBuilder: (context, child, loadingProgress) {
                                            if (loadingProgress == null) return child;
                                            return Container(
                                              height: 180,
                                              color: Colors.grey.shade200,
                                              child: const Center(
                                                child: CircularProgressIndicator(strokeWidth: 2),
                                              ),
                                            );
                                          },
                                          errorBuilder: (context, error, stackTrace) {
                                            return Container(
                                              height: 80,
                                              color: Colors.grey.shade200,
                                              child: const Center(
                                                child: Icon(Icons.broken_image, color: Colors.grey),
                                              ),
                                            );
                                          },
                                        ),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          );
                        },
                      ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
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
            icon: const Icon(Icons.dashboard),
            tooltip: "AI Dashboard",
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const AdminDashboard()),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.analytics),
            tooltip: "AI Assistant",
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const AdminChatPage()),
              );
            },
          ),
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
              final data = report.data() as Map<String, dynamic>;
              final id = data['ID'] ?? report.id;
              final geoPoint = data['GeoPoint'] as GeoPoint?;
              final status = data['Status'] as String? ?? 'Pending';
              final type = data['Type'] ?? '';
              final details = data['Details'] ?? '';
              final username = data['Username'] ?? '';
              final location = data['Location'] ?? '';
              final imageUrl = data.containsKey('ImageURL') ? (data['ImageURL'] ?? '') : '';

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
                clipBehavior: Clip.antiAlias,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Report Photo
                    if (imageUrl != null && imageUrl.toString().isNotEmpty)
                      GestureDetector(
                        onTap: () => _showFullImage(context, imageUrl.toString(), id.toString()),
                        child: Image.network(
                          imageUrl.toString(),
                          height: 180,
                          width: double.infinity,
                          fit: BoxFit.cover,
                          loadingBuilder: (context, child, loadingProgress) {
                            if (loadingProgress == null) return child;
                            return Container(
                              height: 180,
                              color: Colors.grey[200],
                              child: const Center(child: CircularProgressIndicator(strokeWidth: 2)),
                            );
                          },
                          errorBuilder: (context, error, stackTrace) {
                            return Container(
                              height: 80,
                              color: Colors.grey[200],
                              child: const Center(
                                child: Icon(Icons.broken_image, color: Colors.grey),
                              ),
                            );
                          },
                        ),
                      ),
                    Padding(
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
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }

  void _showFullImage(BuildContext context, String imageUrl, String reportId) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => Scaffold(
          backgroundColor: Colors.black,
          appBar: AppBar(
            backgroundColor: Colors.black,
            foregroundColor: Colors.white,
            title: Text('Report $reportId'),
          ),
          body: Center(
            child: InteractiveViewer(
              child: Image.network(
                imageUrl,
                fit: BoxFit.contain,
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _showCommentFullImage(BuildContext parentContext, String imageUrl) {
    showDialog(
      context: parentContext,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.black,
        insetPadding: const EdgeInsets.all(0),
        child: Stack(
          children: [
            Center(
              child: InteractiveViewer(
                child: Image.network(
                  imageUrl,
                  fit: BoxFit.contain,
                  errorBuilder: (context, error, stackTrace) {
                    return const Center(
                      child: Icon(Icons.broken_image, color: Colors.white, size: 48),
                    );
                  },
                ),
              ),
            ),
            Positioned(
              top: 16,
              right: 16,
              child: IconButton(
                icon: const Icon(Icons.close, color: Colors.white, size: 30),
                onPressed: () => Navigator.pop(ctx),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatTimestamp(String timestamp) {
    if (timestamp.isEmpty) return '';
    try {
      final DateTime dt = DateTime.parse(timestamp);
      final now = DateTime.now();
      final difference = now.difference(dt);
      if (difference.inMinutes < 1) {
        return 'Just now';
      } else if (difference.inHours < 1) {
        return '${difference.inMinutes}m ago';
      } else if (difference.inDays < 1) {
        return '${difference.inHours}h ago';
      } else if (difference.inDays < 7) {
        return '${difference.inDays}d ago';
      } else {
        return '${dt.day}/${dt.month}/${dt.year}';
      }
    } catch (e) {
      return timestamp;
    }
  }
}
