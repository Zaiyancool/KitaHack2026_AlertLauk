import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/scheduler.dart';

import 'package:flutter_application_1/comp_manager/FetchMng/FetchProfile.dart';
import 'package:flutter_application_1/comp_manager/ProfilleBlock.dart';

class UserProfilesScreen extends StatefulWidget {
  const UserProfilesScreen({super.key});

  @override
  State<UserProfilesScreen> createState() => _UserProfilesScreenState();
}

class _UserProfilesScreenState extends State<UserProfilesScreen> {
  final TextEditingController detailsCtrl = TextEditingController();
  final TextEditingController idCtrl = TextEditingController();
  final TextEditingController locCtrl = TextEditingController();
  final TextEditingController locDetailsCtrl = TextEditingController();
  final TextEditingController typeCtrl = TextEditingController();
  final String uid = FirebaseAuth.instance.currentUser!.uid;

  bool isLoading = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('User Profile'),
      ),
      body: Center(
        child: FutureBuilder<UserProfileDetails>(
          future: fetchUserInfo(uid),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const CircularProgressIndicator();
            } else if (snapshot.hasError) {
              return Text('Error: ${snapshot.error}');
            } else if (!snapshot.hasData) {
              return const Text('No user data found');
            } else {
              final userInfo = snapshot.data!;
              final date = DateTime.tryParse(userInfo.timeCreated);
              final formattedDate = date != null ? '${date.day}/${date.month}/${date.year}' : 'Unknown';
              final time = DateTime.tryParse(userInfo.timeCreated);
              final formattedTime = time != null ? '${time.hour}:${time.minute}:${time.second}' : 'Unknown';

              return Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton(
                    onPressed: () {
                      debugPrint("UserProfile button pressed");
                      // Navigator.push(
                      //   context,
                      //   MaterialPageRoute(builder: (_) => UserProfilesScreen()),
                      // );
                    },
                    icon: const Icon(Icons.account_circle, size: 100),
                  ),
                  Spacer(),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20.0),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        ProfileBlock(text: 'Username', detailsText: '${userInfo.username}', typeDetails: 'name', isEditable: true),
                        ProfileBlock(text: "Course", detailsText: '${userInfo.course}', typeDetails: 'course', isEditable: true),
                        ProfileBlock(text: "Emergency Contact", detailsText: '${userInfo.emergencyContact}', typeDetails: 'emergency_contact', isEditable: true),
                        ProfileBlock(text: "Email", detailsText: '${userInfo.email}', typeDetails: 'email', isEditable: false),
                        //ProfileBlock(text: "Password", detailsText: userInfo.password, typeDetails: '', isEditable: false),
                        ProfileBlock(text: "Account Created On", detailsText: '$formattedDate at $formattedTime', typeDetails: 'createdAt', isEditable: false),
                        const SizedBox(height: 20),
                        // Add more ProfileBlock widgets as needed
                      ],
                    ),
                  ),
                  Spacer(),
                  ElevatedButton(
                    onPressed: () {
                      FirebaseAuth.instance.signOut();
                      Navigator.of(context).popUntil((route) => route.isFirst);
                    },
                    child: const Text('Logout'),
                  ),
                ],
              );
            }
          },
        ),
      ),
    );
  }
}
