import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_application_1/comp_manager/WriteMng/CommentSubmit.dart';

class CommentScreen extends StatefulWidget {
  final String reportId;
  final String title;

  const CommentScreen({
    super.key,
    required this.reportId,
    required this.title,
  });

  @override
  State<CommentScreen> createState() => _CommentScreenState();
}

class _CommentScreenState extends State<CommentScreen> {
  final TextEditingController commentCtrl = TextEditingController();

  @override
  void dispose() {
    commentCtrl.dispose();
    super.dispose();
  }

  void handleSubmit() {
    final text = commentCtrl.text.trim();
    if (text.isNotEmpty) {
      submitComment(widget.reportId, text);
      commentCtrl.clear();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.title} (${widget.reportId})'),
      ),
      body: Column(
        children: [
          Expanded(
            child: StreamBuilder<DocumentSnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('comments_reports')
                  .doc(widget.reportId)
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (!snapshot.hasData || !snapshot.data!.exists) {
                  return const Center(child: Text('No additional info yet.'));
                }

                final data = snapshot.data!.data() as Map<String, dynamic>? ?? {};
                final comments = List<String>.from(data['Comments'] ?? []);

                if (comments.isEmpty) {
                  return const Center(child: Text('No additional info yet.'));
                }

                return ListView.builder(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: comments.length,
                  itemBuilder: (context, index) {
                    return ListTile(
                      leading: const Icon(
                          Icons.person_pin,
                          size: 45,
                        ),
                      title: Text(
                                comments[index],
                                style: const TextStyle(
                                  fontSize: 18, // increase this for larger text
                                  fontWeight: FontWeight.w500, // optional: make it bolder
                                ),
                              ),

                    );
                  },
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12.0, 12.0, 12.0, 55.0),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: commentCtrl,
                    decoration: const InputDecoration(
                      hintText: 'Write additional information...',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.send),
                  onPressed: handleSubmit,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
 