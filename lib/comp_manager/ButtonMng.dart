import 'package:flutter/material.dart';

class ButtonMng extends StatelessWidget {

  final Function()? onTap;
  final String text;

  const ButtonMng ({
    super.key,
    required this.onTap,
    required this.text,
  });

  @override
  Widget build(BuildContext context) {

    return  GestureDetector(

      onTap: onTap,

      child: Container(
        
        padding: EdgeInsets.all(25),
        margin: EdgeInsets.symmetric(horizontal: 25),
        decoration: BoxDecoration(
          color: Colors.black45,
          borderRadius: BorderRadius.circular(8)),
      
        child: Center(
          child: Text(
            text,
            style: TextStyle(color: Colors.white),),
        ),
      ),
    );
  }

}