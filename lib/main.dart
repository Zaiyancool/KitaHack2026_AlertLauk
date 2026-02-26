import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'firebase_options.dart';

import 'package:flutter_application_1/auth_pages/loginPage.dart';
import 'package:flutter_application_1/auth_pages/singupPage.dart';
import 'package:flutter_application_1/auth_pages/authPage.dart';
import 'package:flutter_application_1/user_profiles/user_profiles_screen.dart';


import 'package:flutter_application_1/comp_manager/TextFileMng.dart';
import 'package:flutter_application_1/comp_manager/ButtonMng.dart';

import 'report_pages/report_screen.dart';
import 'report_pages/report_list_screen.dart';

import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_application_1/heatmap/heatmap_screen.dart';

import 'sos_button/sos_button.dart';
import 'chat_page.dart';
import 'notification_service.dart';
import 'ai_live_assistant/ai_live_assistant_screen.dart';
import 'ai_live_assistant/live_triage_screen.dart';
import 'ai_live_assistant/gemini_live_screen.dart';
import 'ai_live_assistant/ai_live_assistant_realtime.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Load environment variables from .env file
  await dotenv.load(fileName: '.env');
  
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  
  // Initialize FCM notifications
  await NotificationService().initialize();
  
  runApp(CampusSafetyApp());
}

class CampusSafetyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Campus Safety',
      theme: ThemeData(
        primarySwatch: Colors.red,
      ),
      home: AuthPage(), // Changed to authPage in auth_pages folder to handle auth state
      debugShowCheckedModeBanner: false,
    );
  }
}

// ================= Sign out =================

void signOut() {
  FirebaseAuth.instance.signOut();
}

// ================= Home Screen =================
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  String userName = '';
  List<LatLng> userPoints = []; // Declaration of missing userPoints

  @override
  void initState() {
    super.initState();
    fetchUserName();
  }

  Future<void> fetchUserName() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        final doc = await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .get();

        if (doc.exists) {
          setState(() {
            userName = doc.data()?['name'] ?? '';
          });
        }
      }
    } catch (e) {
      debugPrint("Error fetching user name: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
  title: Row(
    children: [
      // Username on the left
      Row(
        children: [
          IconButton(
            onPressed: () {
              debugPrint("UserProfile button pressed");
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => UserProfilesScreen()),
              );
            },
            icon: Icon(Icons.account_circle_sharp, size: 30),
          ),
          const SizedBox(width: 8),
 
          Container(
            constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.4,
            ),
            child: StreamBuilder<DocumentSnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('users')
                  .doc(FirebaseAuth.instance.currentUser!.uid)
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Text(
                    'Hello, ...',
                    style: TextStyle(fontSize: 14),
                    overflow: TextOverflow.ellipsis,
                  );
                }
                if (!snapshot.hasData || !snapshot.data!.exists) {
                  return const Text(
                    'Hello, User',
                    style: TextStyle(fontSize: 14),
                    overflow: TextOverflow.ellipsis,
                  );
                }
                final userData = snapshot.data!.data() as Map<String, dynamic>;
                final username = userData['name'] ?? 'User';
                return Text(
                  'Hello, $username',
                  style: const TextStyle(fontSize: 14),
                  overflow: TextOverflow.ellipsis,
                );
              },
            ),
          ),
        ],
      ),
      const Spacer(), // pushes the title to center
      const Text(
        'Alert Lauk',
        style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
      ),
      const Spacer(flex: 2), // keeps the title centered with space for logout button
    ],
  ),
  actions: [
    IconButton(
      icon: const Icon(Icons.logout),
      onPressed: () async {
        final shouldLogout = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text("Sign Out"),
            content: const Text("Are you sure you want to sign out?"),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text("Cancel")),
              ElevatedButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text("Sign Out")),
            ],
          ),
        );

              if (shouldLogout == true) {
                await FirebaseAuth.instance.signOut();
                ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Signed out successfully')));
                Navigator.pushReplacement(
                    context, MaterialPageRoute(builder: (_) => AuthPage()));
              }
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // 🔥 Heatmap from other file
          Expanded(
  flex: 1,
  child: HeatmapScreen(),
),
          // Bottom Half: Buttons
Expanded(
  flex: 1,
  child: Center(
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        // Buttons: AI Live (left of SOS), SOS, Chat
        // Report Incident and Report List below
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // AI Live Assistant button (left of SOS) - Opens Gemini Live API
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.deepPurple,
                padding: const EdgeInsets.all(15),
                shape: const CircleBorder(),
              ),
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const AILiveAssistantRealtime()),
                );
              },
              child: const Icon(Icons.psychology, color: Colors.white, size: 25),
            ),

            const SizedBox(width: 20),

            // SOS button (center)
            const SOSButton(),

            const SizedBox(width: 20),

            // Right Chat button
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                padding: const EdgeInsets.all(15),
                shape: const CircleBorder(),
              ),
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const ChatPage()),
                );
              },
              child: const Icon(Icons.chat, color: Colors.blue, size: 25),
            )
          ],
        ),

        const SizedBox(height: 20),

        // Report Incident button (below SOS)
        ElevatedButton.icon(
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
          ),
          onPressed: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => ReportScreen()),
            );
          },
          icon: const Icon(Icons.report),
          label: const Text('Report Incident'),
        ),

        const SizedBox(height: 15),

        // Report List button (below Report Incident)
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.white,
            padding: const EdgeInsets.all(15),
            shape: const CircleBorder(),
          ),
          onPressed: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => ReportListScreen()),
            );
          },
          child: const Icon(Icons.article, color: Colors.deepPurple, size: 25),
        ),
      ],
    ),
  ),
),
        ],
      ),
    );
  }
}
// ================= Report Screen =================


// class ReportScreen extends StatelessWidget {
//   final TextEditingController reportCtrl = TextEditingController();
//   String category = "Suspicious";

//   @override
//   Widget build(BuildContext context) {
//     return Scaffold(
//       appBar: AppBar(title: Text('Report Incident')),
//       body: Padding(
//         padding: EdgeInsets.all(24),
//         child: Column(
//           children: [
//             DropdownButton<String>(
//               value: category,
//               items: ["Suspicious", "Harassment", "Theft"].map((e) {
//                 return DropdownMenuItem(value: e, child: Text(e));
//               }).toList(),
//               onChanged: (val) {},
//             ),
//             SizedBox(height: 16),
//             TextField(
//               controller: reportCtrl,
//               decoration: InputDecoration(labelText: "Describe incident"),
//             ),
//             SizedBox(height: 32),
//             ElevatedButton(
//               onPressed: () {
//                 ScaffoldMessenger.of(context).showSnackBar(
//                   SnackBar(content: Text('Report submitted: ${reportCtrl.text}')),
//                 );
//                 Navigator.pop(context); // go back to HomeScreen after submit
//               },
//               child: Text('Submit Report'),
//             ),
//           ],
//         ),
//       ),
//     );
//   }
// }
