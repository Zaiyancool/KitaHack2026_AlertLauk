import 'package:flutter/material.dart';

import 'package:cloud_firestore/cloud_firestore.dart';

class EditProfileDetails {
  final profileType;
  final editText;
  // final String editUsername;
  // final String editCourse;
  // final String editEmergencyContact;
  //final String editEmail;
  //final String password;

  EditProfileDetails({
    required this.profileType,
    required this.editText,
    // required this.editUsername,
    // required this.editCourse,
    // required this.editEmergencyContact,
   //required this.editEmail, 
   // required this.password,
  });
}

Future<void> updateUserProfile(String userId, EditProfileDetails details) async {
  try {
    final docRef = FirebaseFirestore.instance.collection('users').doc(userId);

    await docRef.update({
      details.profileType: details.editText,
    });

    debugPrint('Profile updated: ${details.profileType} -> ${details.editText}');
  } catch (e) {
    debugPrint('Failed to update profile: $e');
  }
}

