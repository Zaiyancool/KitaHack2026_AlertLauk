import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:flutter_application_1/comp_manager/TextFileMng.dart';
import 'package:flutter_application_1/comp_manager/ButtonMng.dart';

class SignupScreen extends StatefulWidget {
  final Function()? onTap;
  const SignupScreen({super.key, required this.onTap});

  @override
  State<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends State<SignupScreen> {
  final TextEditingController nameCtrl = TextEditingController();
  final TextEditingController courseCtrl = TextEditingController();
  final TextEditingController emergencyCtrl = TextEditingController();
  final TextEditingController emailCtrl = TextEditingController();
  final TextEditingController passCtrl = TextEditingController();
  final TextEditingController confirmPassCtrl = TextEditingController();

  bool isLoading = false;

  void regUser() async {
    // Show loading spinner
    setState(() => isLoading = true);

    try {
      if (passCtrl.text != confirmPassCtrl.text) {
        throw FirebaseAuthException(code: 'password-not-matched');
      }

      // ✅ Create user with Firebase Auth
      UserCredential userCredential = await FirebaseAuth.instance
          .createUserWithEmailAndPassword(
        email: emailCtrl.text.trim(),
        password: passCtrl.text.trim(),
      );

      String uid = userCredential.user!.uid;

      // ✅ Save extra details in Firestore
      await FirebaseFirestore.instance.collection("users").doc(uid).set({
        "name": nameCtrl.text.trim(),
        "email": emailCtrl.text.trim(),
        "course": courseCtrl.text.trim(),
        "emergency_contact": emergencyCtrl.text.trim(),
        "createdAt": FieldValue.serverTimestamp(),
      });

      setState(() => isLoading = false);
      _showSuccessDialog();
    } 
    
    on FirebaseAuthException catch (e) {
      setState(() => isLoading = false);
      if (e.code == 'password-not-matched') {
        _showErrorDialog('Passwords do not match');
      } else if (e.code == 'email-already-in-use') {
        _showErrorDialog('Email already in use');
      } else if (e.code == 'invalid-email') {
        _showErrorDialog('Invalid email');
      } else if (e.code == 'weak-password') {
        _showErrorDialog('Password too weak (min 6 characters)');
      } else {
        _showErrorDialog('Registration failed: ${e.code}');
      }
    } catch (e) {
      setState(() => isLoading = false);
      _showErrorDialog('Something went wrong: $e');
    }
  }

  void _showErrorDialog(String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(title: Text('Error'), content: Text(message)),
    );
  }

  void _showSuccessDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Success'),
        content: Text('Account created successfully!'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context), // go back to login
            child: Text('OK'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Sign Up')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            TextFieldMng(controller: nameCtrl, obscureText: false, hintText: 'Full Name'),
            SizedBox(height: 16),
            TextFieldMng(controller: courseCtrl, obscureText: false, hintText: 'Course Studying'),
            SizedBox(height: 16),
            TextFieldMng(controller: emergencyCtrl, obscureText: false, hintText: 'Emergency Contact'),
            SizedBox(height: 16),
            TextFieldMng(controller: emailCtrl, obscureText: false, hintText: 'Email'),
            SizedBox(height: 16),
            TextFieldMng(controller: passCtrl, obscureText: true, hintText: 'Password'),
            SizedBox(height: 16),
            TextFieldMng(controller: confirmPassCtrl, obscureText: true, hintText: 'Confirm Password'),
            SizedBox(height: 25),
            isLoading
                ? CircularProgressIndicator()
                : ButtonMng(onTap: regUser, text: "Sign Up"),
            SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text("Already a member?"),
                SizedBox(width: 4),
                GestureDetector(
                  onTap: widget.onTap,
                  child: Text(
                    "Login now",
                    style: TextStyle(color: Colors.blueAccent, fontWeight: FontWeight.bold),
                  ),
                )
              ],
            )
          ],
        ),
      ),
    );
  }
}