import 'package:flutter/material.dart';
import 'package:flutter_application_1/report_pages/comment_section/comment_screen.dart';

class ReportDetailScreen extends StatelessWidget {
  final String reportId;
  final String title;
  final String description;
  final String date;
  final String time;
  final String status;
  final String location;
  final String type;
  final String? imageUrl;

  const ReportDetailScreen({
    super.key,
    required this.reportId,
    required this.title,
    required this.description,
    required this.date,
    required this.time,
    required this.status,
    required this.location,
    required this.type,
    this.imageUrl,
  });

  @override
  Widget build(BuildContext context) {
    final isSOS = type.toUpperCase() == 'SOS';
    final isSolved = status == 'Solved';

    return Scaffold(
      appBar: AppBar(
        title: Text('Report $reportId'),
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.comment),
            tooltip: 'Comments',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => CommentScreen(
                    reportId: reportId,
                    title: title,
                  ),
                ),
              );
            },
          ),
        ],
      ),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Photo Section ──
            if (imageUrl != null && imageUrl!.isNotEmpty)
              GestureDetector(
                onTap: () => _showFullImage(context),
                child: Hero(
                  tag: 'report_image_$reportId',
                  child: Image.network(
                    imageUrl!,
                    height: 280,
                    width: double.infinity,
                    fit: BoxFit.cover,
                    loadingBuilder: (context, child, loadingProgress) {
                      if (loadingProgress == null) return child;
                      return Container(
                        height: 280,
                        color: Colors.grey[200],
                        child: const Center(child: CircularProgressIndicator()),
                      );
                    },
                    errorBuilder: (context, error, stackTrace) {
                      return Container(
                        height: 280,
                        color: Colors.grey[200],
                        child: const Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.broken_image, size: 40, color: Colors.grey),
                              SizedBox(height: 8),
                              Text('Failed to load image', style: TextStyle(color: Colors.grey)),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              )
            else
              Container(
                height: 120,
                width: double.infinity,
                color: Colors.grey[100],
                child: const Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.no_photography, size: 40, color: Colors.grey),
                      SizedBox(height: 8),
                      Text('No photo attached', style: TextStyle(color: Colors.grey)),
                    ],
                  ),
                ),
              ),

            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── Status & Type Badges ──
                  Row(
                    children: [
                      _buildBadge(
                        label: status,
                        color: isSolved ? Colors.green : Colors.orange,
                        icon: isSolved ? Icons.check_circle : Icons.pending,
                      ),
                      const SizedBox(width: 8),
                      _buildBadge(
                        label: type,
                        color: isSOS ? Colors.red : Colors.blue,
                        icon: isSOS ? Icons.sos : Icons.category,
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),

                  // ── Report ID ──
                  Text(
                    reportId,
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 16,
                      color: Colors.grey[600],
                    ),
                  ),
                  const SizedBox(height: 20),

                  // ── Description ──
                  const Text(
                    'Description',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 15,
                      color: Colors.black54,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.grey[50],
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.grey.shade200),
                    ),
                    child: Text(
                      description.isNotEmpty ? description : 'No description provided.',
                      style: const TextStyle(fontSize: 15, height: 1.5),
                    ),
                  ),
                  const SizedBox(height: 20),

                  // ── Location ──
                  _buildDetailRow(Icons.location_on, 'Location', location.isNotEmpty ? location : 'Not specified'),
                  const Divider(height: 24),

                  // ── Date & Time ──
                  _buildDetailRow(Icons.calendar_today, 'Date', date),
                  const SizedBox(height: 12),
                  _buildDetailRow(Icons.access_time, 'Time', time),
                  const SizedBox(height: 24),

                  // ── Comment Button ──
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.comment),
                      label: const Text('View / Add Comments'),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => CommentScreen(
                              reportId: reportId,
                              title: title,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBadge({required String label, required Color color, required IconData icon}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailRow(IconData icon, String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 20, color: Colors.grey),
        const SizedBox(width: 12),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
            const SizedBox(height: 2),
            Text(value, style: const TextStyle(fontSize: 15)),
          ],
        ),
      ],
    );
  }

  void _showFullImage(BuildContext context) {
    if (imageUrl == null) return;
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
            child: Hero(
              tag: 'report_image_$reportId',
              child: InteractiveViewer(
                child: Image.network(
                    imageUrl!,
                    fit: BoxFit.contain,
                  ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
