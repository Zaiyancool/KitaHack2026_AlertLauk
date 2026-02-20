import 'package:flutter/material.dart';

import 'package:flutter_application_1/auth_pages/loginPage.dart';
import 'package:flutter_application_1/auth_pages/singupPage.dart';
import 'package:flutter_application_1/main.dart';



class LogOrRegScreen extends StatefulWidget {

  const LogOrRegScreen({super.key});

  @override
  State<LogOrRegScreen> createState() => _LogOrRegScreenState();

}

class _LogOrRegScreenState extends State<LogOrRegScreen> {
  
  // to toggle between login and register
  bool showLogin = true;
  
  void toggleScreens(){
    setState(() {
      showLogin = !showLogin;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (showLogin){
      return LoginScreen(
        onTap: toggleScreens
      );
    }
    else{
      return SignupScreen(
        onTap: toggleScreens
      );
    }
  }
}