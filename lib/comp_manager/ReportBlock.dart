import 'package:flutter/material.dart';
import 'package:flutter_application_1/report_pages/comment_section/comment_screen.dart';

class ReportBlock extends StatelessWidget {
  final String title;
  final String reportId;
  final String description;
  final String date;
  final String status;
  final String location;
  final String time;
  final String type; // added type field

  final commentCtrl = TextEditingController();

  ReportBlock({
    required this.title,
    required this.reportId,
    required this.description,
    required this.date,
    required this.status,
    required this.location,
    required this.time,
    required this.type, // pass type here
  });

  @override
  Widget build(BuildContext context) {
    // Determine card color
    Color cardColor;
    if (status == 'Solved') {
      cardColor = Colors.green.shade50;
    } else if (status == 'Pending' && type == 'SOS') {
      cardColor = Colors.red.shade100;
    } else {
      cardColor = Colors.yellow.shade100;
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      child: Container(
        decoration: BoxDecoration(
          color: cardColor, // dynamic color
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black12,
              blurRadius: 6,
              offset: Offset(0, 3),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(12.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Title and Status
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      "$reportId  ($title)",
                      style: const TextStyle(
                        fontSize: 18.0,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Text(
                    "STATUS: $status",
                    style: const TextStyle(
                      fontSize: 14.0,
                      color: Colors.grey,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              // Description
              Container(
                constraints: BoxConstraints(maxHeight: 140),
                child: SingleChildScrollView(
                  child: Text(
                    description,
                    style: const TextStyle(fontSize: 16.0, color: Colors.black87),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              // Location and Date/Time
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    location,
                    style: const TextStyle(fontSize: 14.0, color: Colors.grey),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        date,
                        style: const TextStyle(fontSize: 14.0, color: Colors.grey),
                      ),
                      Text(
                        time,
                        style: const TextStyle(fontSize: 14.0, color: Colors.grey),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 8),
              // Buttons Row
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  IconButton(
                    icon: const Icon(Icons.add_comment, color: Colors.blueAccent),
                    tooltip: 'View Comments',
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
                  // Resolve button can be added here later
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}