import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'dart:io';
import 'dart:typed_data';

Future<void> submitComment(String reportId, String commentText, {String? imageUrl}) async {
  final docRef = FirebaseFirestore.instance
      .collection('comments_reports')
      .doc(reportId);

  // Create a map for the comment with text and optional image URL
  final Map<String, dynamic> newComment = {
    'text': commentText,
    'timestamp': DateTime.now().toIso8601String(),
  };

  // Add image URL if provided
  if (imageUrl != null && imageUrl.isNotEmpty) {
    newComment['imageUrl'] = imageUrl;
  }

  await FirebaseFirestore.instance.runTransaction((transaction) async {
    final snapshot = await transaction.get(docRef);

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

/// Upload image to Firebase Storage (for mobile/Flutter)
Future<String?> uploadCommentImage(File imageFile, String reportId) async {
  try {
    // Create a unique filename using timestamp
    final String fileName = '${reportId}_${DateTime.now().millisecondsSinceEpoch}.jpg';
    
    // Reference to Firebase Storage
    final Reference storageRef = FirebaseStorage.instance
        .ref()
        .child('image-Comment-Section')
        .child(fileName);
    
    // Upload the file
    final UploadTask uploadTask = storageRef.putFile(
      imageFile,
      SettableMetadata(contentType: 'image/jpeg'),
    );
    
    // Wait for upload to complete
    final TaskSnapshot snapshot = await uploadTask;
    
    // Get the download URL
    final String downloadUrl = await snapshot.ref.getDownloadURL();
    
    return downloadUrl;
  } catch (e) {
    debugPrint('Error uploading image (mobile): $e');
    return null;
  }
}

/// Upload image to Firebase Storage (for web)
Future<String?> uploadCommentImageWeb(Uint8List imageBytes, String fileName, String reportId) async {
  try {
    // Create a unique filename using timestamp
    final String uniqueFileName = '${reportId}_${DateTime.now().millisecondsSinceEpoch}_$fileName';
    
    // Reference to Firebase Storage
    final Reference storageRef = FirebaseStorage.instance
        .ref()
        .child('image-Comment-Section')
        .child(uniqueFileName);
    
    // Upload the bytes
    final UploadTask uploadTask = storageRef.putData(
      imageBytes,
      SettableMetadata(contentType: 'image/jpeg'),
    );
    
    // Wait for upload to complete
    final TaskSnapshot snapshot = await uploadTask;
    
    // Get the download URL
    final String downloadUrl = await snapshot.ref.getDownloadURL();
    
    return downloadUrl;
  } catch (e) {
    debugPrint('Error uploading image (web): $e');
    return null;
  }
}
