import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';


class UserProfileDetails {
  final String username;
  final String course;
  final String emergencyContact;
  final String email;
  //final String password;
  final String timeCreated;

  UserProfileDetails({
    required this.username,
    required this.course,
    required this.emergencyContact,
    required this.email, 
   // required this.password,
    required this.timeCreated,
  });
}

 Future<UserProfileDetails> fetchUserInfo(String uid) async {
  try {
    debugPrint("Fetching user info for UID: $uid");
    final doc = await FirebaseFirestore.instance
        .collection('users')
        .doc(uid) // ✅ use the passed uid
        .get();

    if (doc.exists) {
      final data = doc.data();
      return UserProfileDetails(
        username: data?['name'] ?? '',
        course: data?['course'] ?? '',
        emergencyContact: data?['emergency_contact'] ?? '',
        email: data?['email'] ?? '',
      //  password: data?['password'] ?? '',
        timeCreated: (data?['createdAt'] as Timestamp?)?.toDate().toString() ?? '',
      );
    }
  } catch (e) {
    debugPrint("Error fetching user name: $e");
  }
  return UserProfileDetails(username: '', course: '', emergencyContact: '', email: '', timeCreated: '');
}