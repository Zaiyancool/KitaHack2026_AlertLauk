import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:url_launcher/url_launcher.dart';
//import 'dart:js' as js;
import '../comp_manager/FetchMng/FetchLocation.dart';
import '../comp_manager/WriteMng/TypeReportCounter.dart';

class SOSButton extends StatefulWidget {
  const SOSButton({super.key});
  
  @override
  State<SOSButton> createState() => _SOSButtonState();
}

class _SOSButtonState extends State<SOSButton> {
  bool isSending = false;
  String emergencyNumber = '';

  @override
  void initState() {
    super.initState();
    _fetchEmergencyNumber();
  }

  Future<void> _fetchEmergencyNumber() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();

      setState(() {
        emergencyNumber = doc.data()?['emergency_contact'] ?? '';
      });
    } catch (e) {
      print('Error fetching emergency number: $e');
    }
  }

  Future<void> _sendSOS() async {
    if (emergencyNumber.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Emergency number not set!')),
      );
      return;
    }

    setState(() => isSending = true);

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      // Fetch user info
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();

      final username = doc.data()?['name'] ?? '';
      final course = doc.data()?['course'] ?? '';

      // Generate report ID
      final reportId = await generateCustomReportId("SOS");

      // Get current location
      final locDetails = await getCurrentLocation();
      GeoPoint geoPoint = locDetails != null
          ? GeoPoint(locDetails.latitude, locDetails.longitude)
          : GeoPoint(0, 0);

      // Add SOS report
      await FirebaseFirestore.instance.collection("reports").add({
        "Course": course,
        "Details": "SOS triggered!",
        "ID": reportId,
        "Location": "Current Location",
        "GeoPoint": geoPoint,
        "Status": "Pending",
        "Time": FieldValue.serverTimestamp(),
        "Type": "SOS",
        "Username": username,
        "UserID": user.uid,
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('SOS sent successfully!')),
      );

      // Trigger phone call
      _makeCall(emergencyNumber);
    } catch (e) {
      print("Error sending SOS: $e");
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error sending SOS: $e')),
      );
    }

    setState(() => isSending = false);
  }

  Future<void> _makeCall(String number) async {
  final telUrl = 'tel:$number';

  try {
    final uri = Uri.parse(telUrl);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not launch phone app.')),
      );
    }
  } catch (e) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Error calling: $e')),
    );
  }
}

@override
Widget build(BuildContext context) {
  return GestureDetector(
    onTap: isSending ? null : _sendSOS,
    child: Container(
      width: 170,
      height: 170,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: const LinearGradient(
          colors: [Colors.redAccent, Colors.red],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.redAccent.withOpacity(0.6),
            blurRadius: 20,
            spreadRadius: 1,
          ),
        ],
      ),
      alignment: Alignment.center,
      child: isSending
          ? const CircularProgressIndicator(color: Colors.white)
          : const Text(
              'SOS',
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.bold,
                color: Colors.white,
                shadows: [
                  Shadow(
                    offset: Offset(0, 0),
                    blurRadius: 6,
                    color: Colors.redAccent,
                  ),
                ],
              ),
            ),
    ),
  );
}
}