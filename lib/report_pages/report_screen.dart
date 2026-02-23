import "package:flutter/material.dart";
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:io';

import 'package:image_picker/image_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:google_mlkit_image_labeling/google_mlkit_image_labeling.dart';
import 'package:google_mlkit_object_detection/google_mlkit_object_detection.dart';

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
  XFile? _pickedImage;
  final ImagePicker _picker = ImagePicker();

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

            SizedBox(height: 12),
            // Image picker preview
            if (_pickedImage != null)
              Column(
                children: [
                  Image.file(File(_pickedImage!.path), height: 150),
                  SizedBox(height: 8),
                ],
              ),
            Row(
              children: [
                ElevatedButton.icon(
                  icon: Icon(Icons.photo_camera),
                  label: Text('Take Photo'),
                  onPressed: () => _pickImage(ImageSource.camera),
                ),
                SizedBox(width: 12),
                ElevatedButton.icon(
                  icon: Icon(Icons.photo_library),
                  label: Text('Choose'),
                  onPressed: () => _pickImage(ImageSource.gallery),
                ),
              ],
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
      "ImageURL": null,
      "ImagePath": null,
      "ImageLabels": [],
      "ImageObjects": [],
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

  Future<void> _pickImage(ImageSource source) async {
    try {
      final picked = await _picker.pickImage(source: source, maxWidth: 1280, maxHeight: 720, imageQuality: 80);
      if (picked != null) {
        setState(() {
          _pickedImage = picked;
        });
      }
    } catch (e) {
      debugPrint('Image pick error: $e');
    }
  }

  Future<String?> _uploadImageIfAny(String reportId) async {
    if (_pickedImage == null) return null;
    try {
      final path = 'reports/$reportId.jpg';
      final ref = FirebaseStorage.instance.ref().child(path);
      final file = File(_pickedImage!.path);
      final uploadTask = await ref.putFile(file);
      final url = await ref.getDownloadURL();
      return url;
    } catch (e) {
      debugPrint('Upload error: $e');
      return null;
    }
  }

  String _suggestTypeFromLabels(List<String> labels) {
    final keywords = labels.join(' ');
    if (keywords.contains('weapon') || keywords.contains('gun') || keywords.contains('knife')) return 'Suspicious';
    if (keywords.contains('fight') || keywords.contains('assault') || keywords.contains('punch')) return 'Harassment';
    if (keywords.contains('phone') || keywords.contains('wallet') || keywords.contains('theft')) return 'Theft';
    if (keywords.contains('fire') || keywords.contains('smoke')) return 'Other';
    return category; // fallback to current selection
  }

    void submitReport( String userId, String category, String details, String location) async {
      setState(() => isLoading = true);

      final userInfo =  await fetchUserInfo();
      final reportId = await generateCustomReportId(category);

      // upload image (if any)
      final imageUrl = await _uploadImageIfAny(reportId);

      // analyze on device (if image exists)
      String suggestedType = category;
      List<Map<String, dynamic>> labelResults = [];
      List<Map<String, dynamic>> objectResults = [];
      if (imageUrl != null && _pickedImage != null) {
        try {
          final file = File(_pickedImage!.path);
          final analysis = await _analyzeImageOnDevice(file);
          labelResults = analysis['labels'] ?? [];
          objectResults = analysis['objects'] ?? [];
          final labelStrings = labelResults.map((l) => (l['description'] as String).toLowerCase()).toList();
          final objectStrings = objectResults.map((o) => (o['name'] as String).toLowerCase()).toList();
          suggestedType = _suggestTypeFromLabels(labelStrings + objectStrings);
          setState(() { category = suggestedType; });
        } catch (e) {
          debugPrint('On-device analysis failed: $e');
        }
      }

      // create report using suggested type and include analysis
      await addReport(
        userInfo.username,
        userId,
        userInfo.course,
        suggestedType,
        details,
        location,
        reportId,
      );

      // If image uploaded, update report doc with image URL and analysis
      if (imageUrl != null) {
        try {
          final q = await FirebaseFirestore.instance.collection('reports').where('ID', isEqualTo: reportId).limit(1).get();
          if (q.docs.isNotEmpty) {
            final docRef = q.docs.first.reference;
            await docRef.update({
              'ImageURL': imageUrl,
              'ImagePath': 'reports/$reportId.jpg',
              'ImageLabels': labelResults,
              'ImageObjects': objectResults,
            });
          }
        } catch (e) {
          debugPrint('Error updating report with image: $e');
        }
      }

      setState(() => isLoading = false);
      _showSuccessDialog();
    }


}

