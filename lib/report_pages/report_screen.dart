import "package:flutter/material.dart";
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:flutter_application_1/comp_manager/TextFileMng.dart';
import 'package:flutter_application_1/comp_manager/ButtonMng.dart';
import 'package:flutter_application_1/comp_manager/FetchMng/FetchLocation.dart';
import 'package:flutter_application_1/comp_manager/WriteMng/TypeReportCounter.dart';

class ReportScreen extends StatefulWidget {

  const ReportScreen({super.key});

  @override
  State<ReportScreen> createState() => _ReportScreenState();
}

class UserInfo {
  final String username;
  final String course;

  UserInfo({
    required this.username, 
    required this.course,
    });
}

class _ReportScreenState extends State<ReportScreen> {

  String category = "Suspicious";

  //final TextEditingController courseCtrl = TextEditingController();
  final TextEditingController detailsCtrl = TextEditingController();
  final TextEditingController idCtrl = TextEditingController();
  final TextEditingController locCtrl = TextEditingController();
  final TextEditingController locDetailsCtrl = TextEditingController();
  //final TextEditingController statusCtrl = TextEditingController();
  final TextEditingController typeCtrl = TextEditingController();
  final String uid = FirebaseAuth.instance.currentUser!.uid;

  bool isLoading = false;

  @override
  void dispose() {
    //courseCtrl.dispose();
    detailsCtrl.dispose();
    idCtrl.dispose();
    locCtrl.dispose();
    locDetailsCtrl.dispose();
    //statusCtrl.dispose();
    typeCtrl.dispose();
    //nameCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Report Incident')),
      body: Padding(
        padding: EdgeInsets.all(24),
        child: Column(
          children: [
            DropdownButton<String>(
              value: category,
              items: ["Suspicious", "Harassment", "Theft", "Other"].map((e) {
                return DropdownMenuItem(value: e, child: Text(e));
              }).toList(),
              onChanged: (val) {
                setState(() {
                  category = val!;
                });
              },
            ),

            SizedBox(height: 16),
            TextFieldMng(
              controller: detailsCtrl,
              obscureText: false,
              hintText: "Describe incident",
            ),

            SizedBox(height: 16),
            TextFieldMng(
              controller: locCtrl,
              obscureText: false,
              hintText: "Location",
            ),

            SizedBox(height: 32),
            ElevatedButton(
              onPressed: () {
                submitReport(uid, category, detailsCtrl.text.trim(), locCtrl.text.trim());
              },

              child: Text('Submit Report'),
            ),

          ],
        ),
      ),
    );
  }

  Future<UserInfo> fetchUserInfo() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        final doc = await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .get();

        if (doc.exists) {
          final data = doc.data();
          return UserInfo(
            username: data?['name'] ?? '',
            course: data?['course'] ?? '',
          );

          }
        }
      }
       catch (e) {
      debugPrint("Error fetching user name: $e");
    }
  return UserInfo(username: '', course: '');

  }


  Future <void> addReport(String userName, String userId, String course, String type, String details, String location, String reportId ) async {
   
   try {
    final locDetails = await getCurrentLocation();
    debugPrint("Location fetched: $locDetails");

    GeoPoint geoPoint = locDetails != null
        ? GeoPoint(locDetails.latitude, locDetails.longitude)
        : GeoPoint(0, 0);

    await FirebaseFirestore.instance.collection("reports").add({
      "Course": course,
      "Details": details,
      "ID": reportId,
      "Location": location,
      "GeoPoint": geoPoint,
      "Status": "Pending",
      "Time": FieldValue.serverTimestamp(),
      "Type": type,
      "Username": userName,
      "UserID": userId,
    });

    debugPrint("Report submitted successfully.");
  } catch (e) {
    debugPrint("Error submitting report: $e");
  } //nanti kene refine lagi
}


    void _showSuccessDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Success'),
        content: Text('Report Submitted!'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context), // go back to login
            child: Text('OK'),
          ),
        ],
      ),
    );
  }

    void submitReport( String userId, String category, String details, String location) async {
      setState(() => isLoading = true);

      
      final userInfo =  await fetchUserInfo();
      final reportId = await generateCustomReportId(category);

      await addReport(
        userInfo.username,
        userId, 
        userInfo.course, 
        category, 
        details, 
        location,
        reportId,
      );
      setState(() => isLoading = false);
      _showSuccessDialog();
    } 


}

