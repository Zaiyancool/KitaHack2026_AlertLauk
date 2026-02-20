import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

Future<void> submitComment(String reportId, String commentText) async {
final docRef = FirebaseFirestore.instance
    .collection('comments_reports')
    .doc(reportId);

await FirebaseFirestore.instance.runTransaction((transaction) async {
  final snapshot = await transaction.get(docRef);

  final newComment = commentText; // Just a string

  if (snapshot.exists) {
    transaction.update(docRef, {
      'Comments': FieldValue.arrayUnion([newComment]),
    });
  } else {
    transaction.set(docRef, {
      'Comments': [newComment],
    });
  }
});
}
