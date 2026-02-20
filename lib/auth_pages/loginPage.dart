import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
//import 'package:test_auth/Manager/TextFieldMng.dart';
//import 'package:test_auth/Manager/ButtonMng.dart';
import 'package:flutter_application_1/main.dart';
import 'package:flutter_application_1/auth_pages/singupPage.dart';
import 'package:flutter_application_1/auth_pages/authPage.dart';
import 'package:flutter_application_1/auth_pages/LoginRegisterPage.dart';

import 'package:flutter_application_1/comp_manager/TextFileMng.dart';
import 'package:flutter_application_1/comp_manager/ButtonMng.dart';

class LoginScreen extends StatefulWidget {
  
  final Function()? onTap;
  const LoginScreen({super.key, required this.onTap});
  
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final TextEditingController emailCtrl = TextEditingController();

  final TextEditingController passCtrl = TextEditingController();

  final TextEditingController usernameCtrl = TextEditingController();

  Future<void> SignUser() async {
  // Show loading indicator
  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (context) => const Center(child: CircularProgressIndicator()),
  );

  try {
    await FirebaseAuth.instance.signInWithEmailAndPassword(
      email: emailCtrl.text,
      password: passCtrl.text,
    );

    if (mounted) Navigator.pop(context); // Close loading dialog
  } on FirebaseAuthException catch (e) {
    if (mounted) Navigator.pop(context); // Close loading dialog

    if (e.code == 'user-not-found') {
      wrongEmailMessage();
    } else if (e.code == 'wrong-password') {
      wrongPassMessage();
    } else {
      wrongCredentialMessage();
    }

    if (mounted) Navigator.pop(context); // Close loading dialog
  }
}


  // void SignUser() async{

  //   //LOading circle
  //   showDialog(
  //     context: context,
  //     builder: (context){
  //       return const Center(child: CircularProgressIndicator(),);
  //     }
  //   );

  //   //try sign in
  //   try{
  //     await FirebaseAuth.instance.signInWithEmailAndPassword(
  //       email: emailCtrl.text,
  //       password: passCtrl.text,
  //     );

  //     //pop the loading circle
  //     Navigator.pop(context);
  //   }
  //   on FirebaseAuthException catch (e){
      
  //     //pop the loading circle
  //     Navigator.pop(context);

  //     //wrong email (old)
  //     if (e.code == 'user-not-found' ){
  //       wrongEmailMessage();

  //     }

  //     //wrong password (old)
  //     else if (e.code == 'wrong-password'){
  //       wrongPassMessage();

  //     } 
  //     //other errors
  //     else{
  //       wrongCredentialMessage();
  //     }
  //   }

  // }

void wrongCredentialMessage(){
    showDialog(
      context: context, 
      barrierDismissible: true,
      builder: (context){
        return const AlertDialog(

          title: Text('Incorrect Credentials'),
        );
      }
    );
  }

void wrongEmailMessage(){
    showDialog(
      context: context, 
      barrierDismissible: true,
      builder: (context){
        return const AlertDialog(

          title: Text('Incorrect Email'),
        );
      }
    );
  }

void wrongPassMessage(){
    showDialog(
      context: context,
      barrierDismissible: true, 
      builder: (context){
        return const AlertDialog(
          title: Text('Incorrect Password'),
        );
      }
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Padding(
        padding: EdgeInsets.symmetric(horizontal: 25.0),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            
            children: [
              Text(
                'Alert Lauk',
                style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold),
              ),
              SizedBox(height: 40),

              TextFieldMng(
                controller: emailCtrl,
                hintText: 'Email',
                obscureText: false,
              ),

              SizedBox(height: 16),

              TextFieldMng(
                controller: passCtrl,
                hintText: 'Password',
                obscureText: true,
              ),
              SizedBox(height: 16),

              ButtonMng(
                onTap: SignUser,
                text: "Sign In",
              ),
              // TextField(
              //   controller: emailCtrl,
              //   decoration: InputDecoration(labelText: 'Email'),
              // ),
          
              // SizedBox(height: 16),
              // TextField(
              //   controller: passCtrl,
              //   obscureText: true,
              //   decoration: InputDecoration(labelText: 'Password'),
              // ),
          
              // SizedBox(height: 32),
              // ElevatedButton(
              //   onPressed: () {
              //     Navigator.pushReplacement(
              //       context,
              //       MaterialPageRoute(builder: (_) => HomeScreen()),
              //     );
              //   },
              //   child: Text('Login'),
              // ),
              SizedBox(height: 16),

              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text("Not a member?"),
                  const SizedBox(width: 4,),
                  GestureDetector(
                    onTap: widget.onTap,

                    child: Text(
                      "Register now",
                      style: TextStyle(color: Colors.blueAccent, fontWeight: FontWeight.bold),
                    ),
                  )
                ],
              )

              // TextButton(
              //   onPressed: () {
              //     Navigator.push(
              //       context,
              //       MaterialPageRoute(builder: (_) => SignupScreen()),
              //     );
              //   },
              //   child: Text('Sign Up'),
              // ),
            ],
          ),
        ),
      ),
    );
  }
}
