import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

Future<String> generateCustomReportId(String category) async {
  final counterRef = FirebaseFirestore.instance
      .collection('reports_counters')
      .doc("Counter");
  try {
      return await FirebaseFirestore.instance.runTransaction((transaction) async {
        final snapshot = await transaction.get(counterRef);

        int currentCount = snapshot.exists ? (snapshot.data()?[category] ?? 0) : 0;
        int newCount = currentCount + 1;

      if (snapshot.exists) {
        transaction.update(counterRef, {category: newCount});
      } else {
        transaction.set(counterRef, {category: newCount},  SetOptions(merge: true) );
      }

        String prefix = category.substring(0, 3).toUpperCase(); // e.g., SUS
        String formattedId = "$prefix${newCount.toString().padLeft(4, '0')}";

        return formattedId;
      });
} 

catch (e) {
  debugPrint("Transaction failed: $e");
  throw Exception("Failed to generate report ID");
}

}
