import 'package:flutter/material.dart';

class TextFieldMng extends StatelessWidget {

  final controller;
  final String hintText;
  final bool obscureText;

  const TextFieldMng ({
    super.key,
    required this.controller,
    required this.hintText,
    required this.obscureText,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 25.0),
      child: TextField(

        controller: controller,
        obscureText: obscureText,

        decoration: InputDecoration(
          enabledBorder: OutlineInputBorder(
            borderSide: BorderSide(color:Color.fromARGB(255, 255, 255, 255)),
          ),
          focusedBorder: OutlineInputBorder(
            borderSide: BorderSide(color:Color.fromARGB(255, 0, 0, 0)),
          ),
      
          fillColor: const Color.fromARGB(255, 234, 234, 234),
          filled: true,
          hintText: hintText,
          hintStyle: TextStyle(color: const Color.fromARGB(255, 167, 167, 167))
        ),
      ),
    );
  }
}