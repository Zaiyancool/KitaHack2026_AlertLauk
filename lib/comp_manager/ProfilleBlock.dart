import 'package:flutter/material.dart';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_application_1/comp_manager/FetchMng/FetchProfile.dart';
import 'package:flutter_application_1/comp_manager/WriteMng/EditProfile.dart';

class ProfileBlock extends StatelessWidget {
  final String text;
  final String detailsText;
  final String typeDetails;
  final bool isEditable;

  const ProfileBlock({
    super.key,
    required this.text,
    required this.detailsText,
    required this.typeDetails,
    required this.isEditable,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 20),
          color: Colors.grey[200],
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10,20,10,10),
            child: Text(
              '$text: $detailsText',
              style: const TextStyle(fontSize: 20),
            ),
          ),
        ),

        if (isEditable) ... {
            IconButton(
              
              icon: const Icon(Icons.edit),
              // onPressed: () {
              //   // Handle edit action
                
              //   debugPrint("Edit button pressed for $text details: $typeDetails");
              //   EditProfileDetails(profileType: typeDetails, editText: detailsText);  
              // },


              onPressed: () {
                
                debugPrint("Edit button pressed for $text details: $typeDetails");

                showDialog(
                  context: context,
                  builder: (context) {
                    TextEditingController controller = TextEditingController(text: detailsText);
                    final String uid = FirebaseAuth.instance.currentUser!.uid;
                    
                    return AlertDialog(
                      title: Text('Edit $text'),
                      content: TextField(
                        controller: controller,
                        decoration: InputDecoration(hintText: 'Enter new $text'),
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text('Cancel'),
                        ),
                        TextButton(
                          onPressed: () async {
                            final newText = controller.text.trim();
                            if (newText.isNotEmpty) {
                              final editDetails = EditProfileDetails(
                                profileType: typeDetails,
                                editText: newText,
                              );

                              // Update Firestore
                              await updateUserProfile(uid, editDetails);

                                // Show confirmation
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text('$text updated successfully!'),
                                    duration: const Duration(seconds: 2),
                                  ),
                                );


                              Navigator.pop(context); // Close the AlertDialog

                              // Navigate back to main menu
                              Navigator.of(context).pop(); // assumes main menu is underneath in stack
                              // OR if you want to force open main menu directly:
                              // Navigator.of(context).pushReplacement(
                              //   MaterialPageRoute(builder: (_) => MainMenuScreen())
                              // );
                            }
                          },
                          child: const Text('Save'),
                        ),
                      ],
                    );
                  },
                );
              }

              
            ),
        },

      ],
    );
  }
}