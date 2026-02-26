import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:flutter/foundation.dart';

/// Helper class to send push notifications via Cloud Functions
class NotificationHelper {
  static final NotificationHelper _instance = NotificationHelper._internal();
  factory NotificationHelper() => _instance;
  NotificationHelper._internal();

  // Cloud Functions base URL - update this to your deployed function URL
  static const String _cloudFunctionBaseUrl = 'https://us-central1-alert-lauk.cloudfunctions.net';

  /// Send SOS alert notification to all admins
  /// Called when user triggers SOS button
  Future<bool> sendSOSAlert({
    required String userName,
    required String location,
    String? reportId,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$_cloudFunctionBaseUrl/sendSOSNotification'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'userName': userName,
          'location': location,
          'reportId': reportId,
          'timestamp': DateTime.now().toIso8601String(),
        }),
      ).timeout(const Duration(seconds: 30));

      if (kDebugMode) {
        print('SOS Notification response: ${response.statusCode}');
      }

      return response.statusCode == 200;
    } catch (e) {
      if (kDebugMode) {
        print('Error sending SOS notification: $e');
      }
      return false;
    }
  }

  /// Notify admins when a new report is submitted
  /// Called when user submits a new incident report
  Future<bool> notifyAdminsOfNewReport({
    required String reportId,
    required String reportType,
    required String description,
    required String location,
    required String userName,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$_cloudFunctionBaseUrl/notifyAdminsOfNewReport'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'reportId': reportId,
          'reportType': reportType,
          'description': description,
          'location': location,
          'userName': userName,
          'timestamp': DateTime.now().toIso8601String(),
        }),
      ).timeout(const Duration(seconds: 30));

      if (kDebugMode) {
        print('New Report Notification response: ${response.statusCode}');
      }

      return response.statusCode == 200;
    } catch (e) {
      if (kDebugMode) {
        print('Error sending new report notification: $e');
      }
      return false;
    }
  }

  /// Notify user when their report status is updated
  /// Called when admin updates report status
  Future<bool> notifyUserOfStatusUpdate({
    required String reportId,
    required String userId,
    required String newStatus,
    required String reportType,
    String? adminNote,
  }) async {
    try {
      // Get user's FCM token
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .get();

      final userToken = userDoc.data()?['fcmToken'];
      if (userToken == null) {
        if (kDebugMode) {
          print('User FCM token not found');
        }
        return false;
      }

      final response = await http.post(
        Uri.parse('$_cloudFunctionBaseUrl/notifyUserOfStatusUpdate'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'userToken': userToken,
          'reportId': reportId,
          'newStatus': newStatus,
          'reportType': reportType,
          'adminNote': adminNote ?? '',
        }),
      ).timeout(const Duration(seconds: 30));

      if (kDebugMode) {
        print('Status Update Notification response: ${response.statusCode}');
      }

      return response.statusCode == 200;
    } catch (e) {
      if (kDebugMode) {
        print('Error sending status update notification: $e');
      }
      return false;
    }
  }

  /// Send emergency broadcast to all users (admin only)
  /// Called by admin to broadcast emergency message
  Future<bool> sendEmergencyBroadcast({
    required String title,
    required String message,
    required String adminId,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$_cloudFunctionBaseUrl/sendEmergencyBroadcast'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'title': title,
          'message': message,
          'adminId': adminId,
          'timestamp': DateTime.now().toIso8601String(),
        }),
      ).timeout(const Duration(seconds: 30));

      if (kDebugMode) {
        print('Emergency Broadcast response: ${response.statusCode}');
      }

      return response.statusCode == 200;
    } catch (e) {
      if (kDebugMode) {
        print('Error sending emergency broadcast: $e');
      }
      return false;
    }
  }

  /// Get admin FCM tokens for targeted notifications
  Future<List<String>> getAdminTokens() async {
    try {
      final adminsSnapshot = await FirebaseFirestore.instance
          .collection('users')
          .where('role', isEqualTo: 'admin')
          .get();

      List<String> tokens = [];
      for (var doc in adminsSnapshot.docs) {
        final token = doc.data()['fcmToken'];
        if (token != null && token.isNotEmpty) {
          tokens.add(token);
        }
      }
      return tokens;
    } catch (e) {
      if (kDebugMode) {
        print('Error getting admin tokens: $e');
      }
      return [];
    }
  }
}
