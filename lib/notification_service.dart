import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FirebaseMessaging _firebaseMessaging = FirebaseMessaging.instance;
  
  /// Initialize FCM - request permissions and get token
  Future<void> initialize() async {
    try {
      // Request notification permissions
      NotificationSettings settings = await _firebaseMessaging.requestPermission(
        alert: true,
        announcement: false,
        badge: true,
        carPlay: false,
        criticalAlert: false,
        provisional: false,
        sound: true,
      );

      if (kDebugMode) {
        print('Notification permission status: ${settings.authorizationStatus}');
      }

      // Get the FCM token
      final String? token = await _firebaseMessaging.getToken();
      if (token != null) {
        await _saveTokenToFirestore(token);
        if (kDebugMode) {
          print('FCM Token: $token');
        }
      }

      // Handle foreground messages
      FirebaseMessaging.onMessage.listen(_handleForegroundMessage);

      // Handle when app is opened from notification
      FirebaseMessaging.onMessageOpenedApp.listen(_handleMessageOpenedApp);

      // Check if app was opened from terminated state
      final RemoteMessage? initialMessage = await _firebaseMessaging.getInitialMessage();
      if (initialMessage != null) {
        _handleInitialMessage(initialMessage);
      }

    } catch (e) {
      if (kDebugMode) {
        print('Error initializing notifications: $e');
      }
    }
  }

  /// Save FCM token to Firestore for targeted notifications
  Future<void> _saveTokenToFirestore(String token) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .update({
              'fcmToken': token,
              'tokenUpdatedAt': FieldValue.serverTimestamp(),
            });
      }
    } catch (e) {
      // If document doesn't exist, create it
      try {
        final user = FirebaseAuth.instance.currentUser;
        if (user != null) {
          await FirebaseFirestore.instance
              .collection('users')
              .doc(user.uid)
              .set({
                'fcmToken': token,
                'tokenUpdatedAt': FieldValue.serverTimestamp(),
              }, SetOptions(merge: true));
        }
      } catch (e) {
        if (kDebugMode) {
          print('Error saving FCM token: $e');
        }
      }
    }
  }

  /// Handle foreground messages
  void _handleForegroundMessage(RemoteMessage message) {
    if (kDebugMode) {
      print('Received foreground message: ${message.notification?.title}');
    }
    
    // You can show a local notification here if needed
    // For now, we'll handle it via the UI
  }

  /// Handle when user taps on notification to open app
  void _handleMessageOpenedApp(RemoteMessage message) {
    if (kDebugMode) {
      print('App opened from notification: ${message.notification?.title}');
    }
    _handleNotificationTap(message);
  }

  /// Handle initial message (app launched from notification)
  void _handleInitialMessage(RemoteMessage message) {
    if (kDebugMode) {
      print('App launched from notification: ${message.notification?.title}');
    }
    _handleNotificationTap(message);
  }

  /// Handle notification tap - navigate to appropriate screen
  void _handleNotificationTap(RemoteMessage message) {
    final data = message.data;
    final notificationType = data['type'] ?? '';
    
    if (kDebugMode) {
      print('Notification type: $notificationType, data: $data');
    }
    
    // Navigation will be handled in the app based on this data
    // You can use a global key or state management to navigate
  }

  /// Subscribe to topic for receiving broadcast notifications
  Future<void> subscribeToTopic(String topic) async {
    try {
      await _firebaseMessaging.subscribeToTopic(topic);
      if (kDebugMode) {
        print('Subscribed to topic: $topic');
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error subscribing to topic: $e');
      }
    }
  }

  /// Unsubscribe from topic
  Future<void> unsubscribeFromTopic(String topic) async {
    try {
      await _firebaseMessaging.unsubscribeFromTopic(topic);
      if (kDebugMode) {
        print('Unsubscribed from topic: $topic');
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error unsubscribing from topic: $e');
      }
    }
  }

  /// Get the current FCM token
  Future<String?> getToken() async {
    try {
      return await _firebaseMessaging.getToken();
    } catch (e) {
      if (kDebugMode) {
        print('Error getting token: $e');
      }
      return null;
    }
  }

  /// Delete the current token (for logout)
  Future<void> deleteToken() async {
    try {
      await _firebaseMessaging.deleteToken();
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .update({
              'fcmToken': FieldValue.delete(),
            });
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error deleting token: $e');
      }
    }
  }
}
