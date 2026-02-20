import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_application_1/auth_pages/singupPage.dart';
import 'package:flutter_application_1/main.dart';
import 'package:flutter_application_1/auth_pages/loginPage.dart';
import 'package:flutter_application_1/auth_pages/LoginRegisterPage.dart';
import 'package:flutter_application_1/admin/admin_home.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class AuthPage extends StatelessWidget {
  const AuthPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: StreamBuilder<User?>(
        stream: FirebaseAuth.instance.authStateChanges(),
        builder: (context, snapshot) {
          if (snapshot.hasData) {
            final user = snapshot.data!;
            return FutureBuilder<DocumentSnapshot>(
              future: FirebaseFirestore.instance
                  .collection('users')
                  .doc(user.uid)
                  .get(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (!snapshot.hasData || !snapshot.data!.exists) {
                  return const Center(child: Text("User data not found"));
                }

                final data = snapshot.data!.data() as Map<String, dynamic>;
                final role = data['role'] ?? 'user';

                if (role == 'admin') {
                  return AdminHomePage();
                } else {
                  return HomeScreen();
                }
              },
            );
          } else {
            return const LogOrRegScreen();
          }
        },
      ),
    );
  }
}