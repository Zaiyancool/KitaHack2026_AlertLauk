import "package:flutter/material.dart";
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';

import 'package:flutter_application_1/comp_manager/TextFileMng.dart';
import 'package:flutter_application_1/comp_manager/FetchMng/FetchLocation.dart';
import 'package:flutter_application_1/comp_manager/WriteMng/TypeReportCounter.dart';
import 'package:flutter_application_1/ai_services/incident_categorization_service.dart';
import 'package:flutter_application_1/ai_services/gemini_service.dart';
import 'package:flutter_application_1/ai_services/speech_to_text_service.dart';


class ReportScreen extends StatefulWidget {
  const ReportScreen({super.key});

  @override
  State<ReportScreen> createState() => _ReportScreenState();
}

class UserInfo {
  final String username;
  final String course;

  UserInfo({
    required this.username,
    required this.course,
  });
}

class _ReportScreenState extends State<ReportScreen> {
  // Fixed categories + "Other" for custom
  static const List<String> _fixedCategories = [
    "Suspicious",
    "Harassment",
    "Theft",
    "Fire",
    "Injury",
    "Violence",
    "Vehicle Accident",
    "Other",
  ];

  String category = "Suspicious";
  final TextEditingController _customTypeCtrl = TextEditingController();

  // Speech-to-Text state - DEFAULT TO MALAY for Malaysian users
  bool _isListening = false;
  String _speechText = '';
  SpeechToTextService? _speechService;
  String _selectedLanguage = 'ms_MY'; // Default to Malay (Malaysia)

  final TextEditingController detailsCtrl = TextEditingController();
  final TextEditingController locCtrl = TextEditingController();
  final TextEditingController locDetailsCtrl = TextEditingController();
  final TextEditingController typeCtrl = TextEditingController();
  final TextEditingController idCtrl = TextEditingController();
  final String uid = FirebaseAuth.instance.currentUser!.uid;
  XFile? _pickedImage;
  Uint8List? _pickedImageBytes; // for web support
  final ImagePicker _picker = ImagePicker();

  bool isLoading = false;
  bool _isAnalyzing = false;
  bool _locationFetching = false;

  // Upload progress tracking (0.0 to 1.0)
  double _uploadProgress = 0.0;
  String _submitStatusText = '';

  // AI analysis results
  String? _aiSuggestion;
  String? _aiCategory;
  double? _aiConfidence;
  List<String> _detectedLabels = [];
  List<Map<String, dynamic>> _labelResults = [];
  List<Map<String, dynamic>> _objectResults = [];

  @override
  void initState() {
    super.initState();
    // Initialize speech service
    _speechService = SpeechToTextService.getInstance();
    _speechService?.initialize();
  }

  @override
  void dispose() {
    detailsCtrl.dispose();
    idCtrl.dispose();
    locCtrl.dispose();
    locDetailsCtrl.dispose();
    typeCtrl.dispose();
    _customTypeCtrl.dispose();
    _speechService?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Report Incident'),
        elevation: 0,
      ),
      body: Stack(
        children: [
          SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Photo Section ──
                _buildPhotoSection(),
                const SizedBox(height: 16),

                // ── AI Analysis Banner ──
                if (_aiSuggestion != null) _buildAIAnalysisBanner(),
                if (_isAnalyzing) _buildAnalyzingIndicator(),

                // ── Category Dropdown ──
                const Text('Incident Type', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey.shade400),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: _fixedCategories.contains(category) ? category : "Other",
                      isExpanded: true,
                      items: _fixedCategories.map((e) {
                        return DropdownMenuItem(value: e, child: Text(e));
                      }).toList(),
                      onChanged: (val) {
                        setState(() {
                          category = val!;
                          if (val != "Other") _customTypeCtrl.clear();
                        });
                      },
                    ),
                  ),
                ),

                // Custom type input when "Other" is selected
                if (category == "Other" || !_fixedCategories.contains(category)) ...[
                  const SizedBox(height: 8),
                  TextField(
                    controller: _customTypeCtrl,
                    decoration: InputDecoration(
                      hintText: 'Specify incident type (e.g. Flooding, Animal, etc.)',
                      hintStyle: TextStyle(color: Colors.grey[400], fontSize: 14),
                      filled: true,
                      fillColor: const Color.fromARGB(255, 234, 234, 234),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: Colors.white),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: Colors.black),
                      ),
                      prefixIcon: const Icon(Icons.edit, size: 18),
                    ),
                  ),
                ],

                const SizedBox(height: 16),

                // ── Description ──
                const Text('Description', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
                const SizedBox(height: 8),
                // Custom TextField with microphone button (WhatsApp-like voice input)
                _buildDescriptionField(),

                const SizedBox(height: 16),

                // ── Location ──
                Row(
                  children: [
                    const Text('Location', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
                    const SizedBox(width: 8),
                    if (_locationFetching)
                      const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    if (!_locationFetching && locCtrl.text.isNotEmpty)
                      const Icon(Icons.check_circle, size: 16, color: Colors.green),
                  ],
                ),
                const SizedBox(height: 8),
                TextFieldMng(
                  controller: locCtrl,
                  obscureText: false,
                  hintText: "Auto-detected from GPS or type manually",
                ),

                const SizedBox(height: 32),

                // ── Submit Button ──
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton.icon(
                    icon: isLoading
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Icon(Icons.send_rounded),
                    label: Text(isLoading ? 'Submitting...' : 'Submit Report', style: const TextStyle(fontSize: 16)),
                    style: ElevatedButton.styleFrom(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    onPressed: isLoading
                        ? null
                        : () {
                            submitReport(uid, category, detailsCtrl.text.trim(), locCtrl.text.trim());
                          },
                  ),
                ),
                const SizedBox(height: 24),
              ],
            ),
          ),

          // Loading overlay with upload progress
          if (isLoading)
            Container(
              color: Colors.black38,
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const CircularProgressIndicator(color: Colors.white),
                    const SizedBox(height: 16),
                    Text(
                      _submitStatusText.isNotEmpty ? _submitStatusText : 'Submitting report...',
                      style: const TextStyle(color: Colors.white, fontSize: 16),
                    ),
                    if (_uploadProgress > 0 && _uploadProgress < 1.0) ...[
                      const SizedBox(height: 12),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 60),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: LinearProgressIndicator(
                            value: _uploadProgress,
                            minHeight: 6,
                            backgroundColor: Colors.white24,
                            valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '${(_uploadProgress * 100).toStringAsFixed(0)}%',
                        style: const TextStyle(color: Colors.white70, fontSize: 13),
                      ),
                    ],
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// Build description TextField with microphone button (WhatsApp-like voice input)
  Widget _buildDescriptionField() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Main text field with mic button
          TextField(
            controller: detailsCtrl,
            obscureText: false,
            maxLines: 3,
            minLines: 1,
            decoration: InputDecoration(
              enabledBorder: OutlineInputBorder(
                borderSide: BorderSide(color: Colors.white),
                borderRadius: BorderRadius.circular(12),
              ),
              focusedBorder: OutlineInputBorder(
                borderSide: BorderSide(color: Colors.black),
                borderRadius: BorderRadius.circular(12),
              ),
              fillColor: const Color.fromARGB(255, 234, 234, 234),
              filled: true,
              hintText: "Describe the incident (AI will auto-fill from photo)",
              hintStyle: TextStyle(color: const Color.fromARGB(255, 167, 167, 167)),
              prefixIcon: IconButton(
                icon: Icon(
                  _isListening ? Icons.mic : Icons.mic_none,
                  color: _isListening ? Colors.red : Colors.grey[600],
                ),
                onPressed: _isListening ? _stopListening : _startListening,
                tooltip: _isListening ? 'Tap to stop recording' : 'Tap to record voice',
              ),
              suffixIcon: _isListening
                  ? _buildListeningIndicator()
                  : (detailsCtrl.text.isNotEmpty
                      ? IconButton(
                          icon: Icon(Icons.clear, color: Colors.grey[600]),
                          onPressed: () {
                            detailsCtrl.clear();
                            _speechText = '';
                          },
                          tooltip: 'Clear text',
                        )
                      : null),
            ),
            onChanged: (value) {
              setState(() {}); // Update suffix icon
            },
          ),
          
          // Show language indicator when listening
          if (_isListening) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.language, size: 16, color: Colors.blue.shade700),
                  const SizedBox(width: 6),
                  Text(
                    'Language: Malay (ms_MY)',
                    style: TextStyle(fontSize: 12, color: Colors.blue.shade700),
                  ),
                ],
              ),
            ),
          ],
          
          // Show speech text preview when listening
          if (_isListening && _speechText.isNotEmpty) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.red.shade200),
              ),
              child: Row(
                children: [
                  Icon(Icons.hearing, color: Colors.red.shade400, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _speechText,
                      style: TextStyle(
                        color: Colors.red.shade700,
                        fontSize: 13,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ],
          
          // Show discard option when there's speech text but not listening
          if (!_isListening && _speechText.isNotEmpty && detailsCtrl.text.isNotEmpty) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                TextButton.icon(
                  icon: const Icon(Icons.check_circle, size: 16, color: Colors.green),
                  label: const Text('Text applied', style: TextStyle(fontSize: 12)),
                  onPressed: () {
                    // Text is already in the field
                  },
                ),
                TextButton.icon(
                  icon: const Icon(Icons.refresh, size: 16, color: Colors.orange),
                  label: const Text('Discard', style: TextStyle(fontSize: 12)),
                  onPressed: _discardSpeech,
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  /// Animated listening indicator (WhatsApp-like)
  Widget _buildListeningIndicator() {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation<Color>(Colors.red.shade400),
            ),
          ),
          const SizedBox(width: 4),
          GestureDetector(
            onTap: _stopListening,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.red,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Text(
                'Tap to stop',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Start speech recognition with MALAY (ms_MY) as default for Malaysian users
  Future<void> _startListening() async {
    if (_speechService == null) {
      _speechService = SpeechToTextService.getInstance();
      await _speechService?.initialize();
    }

    if (_speechService == null || !_speechService!.isInitialized) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Speech recognition not available. Please check microphone permissions.')),
        );
      }
      return;
    }

    setState(() {
      _isListening = true;
      _speechText = '';
    });

    // Show listening feedback
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Row(
            children: [
              Icon(Icons.mic, color: Colors.white),
              SizedBox(width: 8),
              Text('Listening... Speak now (Bahasa Melayu)'),
            ],
          ),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 2),
        ),
      );
    }

    // Use ms_MY (Malay Malaysia) for better local recognition of place names like "Taman Pinji Perdana"
    await _speechService!.startListening(
      localeId: 'ms_MY', // Default to Malay (Malaysia) - BEST for local Malaysian place names
      onResult: (String text) {
        setState(() {
          _speechText = text;
        });
      },
      onListeningStarted: () {
        setState(() {
          _isListening = true;
        });
      },
      onListeningStopped: () {
        setState(() {
          _isListening = false;
        });
        
        if (_speechText.isNotEmpty) {
          setState(() {
            if (detailsCtrl.text.trim().isNotEmpty) {
              detailsCtrl.text = '${detailsCtrl.text.trim()} $_speechText';
            } else {
              detailsCtrl.text = _speechText;
            }
          });
          _showSpeechResultDialog();
        }
      },
      onError: (String error) {
        setState(() {
          _isListening = false;
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Speech error: $error')),
          );
        }
      },
    );
  }

  /// Stop speech recognition
  Future<void> _stopListening() async {
    await _speechService?.stopListening();
    setState(() {
      _isListening = false;
    });
  }

  /// Discard speech result
  void _discardSpeech() {
    setState(() {
      _speechText = '';
      detailsCtrl.clear();
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Voice input discarded')),
    );
  }

  /// Show dialog to confirm or re-record speech
  void _showSpeechResultDialog() {
    if (_speechText.isEmpty || !mounted) return;
    
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.record_voice_over, color: Colors.green),
            SizedBox(width: 8),
            Text('Voice Input'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Recognized text:', style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                detailsCtrl.text,
                style: const TextStyle(fontSize: 14),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(dialogContext).pop();
            },
            child: const Text('Edit Text'),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(dialogContext).pop();
              _discardSpeech();
            },
            child: const Text('Discard', style: TextStyle(color: Colors.red)),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.of(dialogContext).pop();
            },
            child: const Text('Use Text'),
          ),
        ],
      ),
    );
  }

  /// Build the photo capture / preview section
  Widget _buildPhotoSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Evidence Photo', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
        const SizedBox(height: 8),
        if (_pickedImage != null) ...[
          Stack(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: kIsWeb
                    ? (_pickedImageBytes != null
                        ? Image.memory(
                            _pickedImageBytes!,
                            height: 220,
                            width: double.infinity,
                            fit: BoxFit.cover,
                          )
                        : Container(
                            height: 220,
                            width: double.infinity,
                            color: Colors.grey[200],
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.image, size: 48, color: Colors.grey[400]),
                                const SizedBox(height: 8),
                                Text('Image selected', style: TextStyle(color: Colors.grey[600])),
                              ],
                            ),
                          ))
                    : Image.file(
                        File(_pickedImage!.path),
                        height: 220,
                        width: double.infinity,
                        fit: BoxFit.cover,
                      ),
              ),
              Positioned(
                top: 8,
                right: 8,
                child: GestureDetector(
                  onTap: () {
                    setState(() {
                      _pickedImage = null;
                      _pickedImageBytes = null;
                      _aiSuggestion = null;
                      _aiCategory = null;
                      _aiConfidence = null;
                      _detectedLabels = [];
                      _labelResults = [];
                      _objectResults = [];
                      detailsCtrl.clear();
                      _customTypeCtrl.clear();
                      category = "Suspicious";
                    });
                  },
                  child: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: const BoxDecoration(
                      color: Colors.black54,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.close, color: Colors.white, size: 18),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.photo_camera, size: 18),
                  label: const Text('Retake'),
                  onPressed: _isAnalyzing ? null : () => _pickImage(ImageSource.camera),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.photo_library, size: 18),
                  label: const Text('Choose again'),
                  onPressed: _isAnalyzing ? null : () => _pickImage(ImageSource.gallery),
                ),
              ),
            ],
          ),
        ] else ...[
          Container(
            height: 160,
            width: double.infinity,
            decoration: BoxDecoration(
              color: Colors.grey[100],
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey.shade300, width: 1.5),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.add_a_photo, size: 40, color: Colors.grey[400]),
                const SizedBox(height: 8),
                Text(
                  'Add a photo for AI-powered analysis',
                  style: TextStyle(color: Colors.grey[600], fontSize: 14),
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    ElevatedButton.icon(
                      icon: const Icon(Icons.photo_camera, size: 18),
                      label: const Text('Camera'),
                      onPressed: () => _pickImage(ImageSource.camera),
                    ),
                    const SizedBox(width: 12),
                    ElevatedButton.icon(
                      icon: const Icon(Icons.photo_library, size: 18),
                      label: const Text('Gallery'),
                      onPressed: () => _pickImage(ImageSource.gallery),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  /// Shows a banner with AI analysis results
  Widget _buildAIAnalysisBanner() {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.blue.shade50, Colors.purple.shade50],
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.blue.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.auto_awesome, color: Colors.deepPurple, size: 20),
              const SizedBox(width: 8),
              const Text(
                'Google AI Analysis',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.deepPurple),
              ),
              const Spacer(),
              if (_aiConfidence != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.deepPurple.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '${(_aiConfidence! * 100).toStringAsFixed(0)}% confident',
                    style: const TextStyle(fontSize: 11, color: Colors.deepPurple),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          if (_aiCategory != null)
            Row(
              children: [
                const Icon(Icons.category, size: 16, color: Colors.black54),
                const SizedBox(width: 6),
                Text(
                  'AI suggested type: $_aiCategory',
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                ),
              ],
            ),
          if (_detectedLabels.isNotEmpty) ...[
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: _detectedLabels.take(6).map((label) {
                return Chip(
                  label: Text(label, style: const TextStyle(fontSize: 11)),
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  padding: EdgeInsets.zero,
                  visualDensity: const VisualDensity(horizontal: -4, vertical: -4),
                  backgroundColor: Colors.white,
                );
              }).toList(),
            ),
          ],
          const SizedBox(height: 8),
          Text(
            'Description and type have been auto-filled. You can edit them before submitting.',
            style: TextStyle(fontSize: 12, color: Colors.grey[600], fontStyle: FontStyle.italic),
          ),
        ],
      ),
    );
  }

  /// Analyzing indicator
  Widget _buildAnalyzingIndicator() {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.blue.shade50,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          const SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Analyzing photo with Google AI...',
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                ),
                Text(
                  'Using ML Kit + Gemini to detect incident details',
                  style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<UserInfo> fetchUserInfo() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        final doc = await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .get();

        if (doc.exists) {
          final data = doc.data();
          return UserInfo(
            username: data?['name'] ?? '',
            course: data?['course'] ?? '',
          );
        }
      }
    } catch (e) {
      debugPrint("Error fetching user name: $e");
    }
    return UserInfo(username: '', course: '');
  }

  Future<void> addReport({
    required String userName,
    required String userId,
    required String course,
    required String type,
    required String details,
    required String location,
    required String reportId,
    String? imageUrl,
    String? imagePath,
    List<Map<String, dynamic>>? imageLabels,
    List<Map<String, dynamic>>? imageObjects,
  }) async {
    try {
      final locDetails = await getCurrentLocation();
      debugPrint("Location fetched: $locDetails");

      GeoPoint geoPoint = locDetails != null
          ? GeoPoint(locDetails.latitude, locDetails.longitude)
          : GeoPoint(0, 0);

      final Map<String, dynamic> reportData = {
        "Course": course,
        "Details": details,
        "ID": reportId,
        "ImageURL": imageUrl ?? '',
        "ImagePath": imagePath ?? '',
        "Location": location,
        "GeoPoint": geoPoint,
        "Status": "Pending",
        "Time": FieldValue.serverTimestamp(),
        "Type": type,
        "Username": userName,
        "UserID": userId,
      };

      if (imageLabels != null && imageLabels.isNotEmpty) {
        reportData["ImageLabels"] = imageLabels;
      }
      if (imageObjects != null && imageObjects.isNotEmpty) {
        reportData["ImageObjects"] = imageObjects;
      }

      await FirebaseFirestore.instance.collection("reports").add(reportData);

      debugPrint("Report submitted successfully with imageUrl: $imageUrl");
    } catch (e) {
      debugPrint("Error submitting report: $e");
    }
  }

  void _showSuccessDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.check_circle, color: Colors.green),
            SizedBox(width: 8),
            Text('Success'),
          ],
        ),
        content: const Text('Your report has been submitted and will be reviewed shortly.'),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              Navigator.pop(context);
            },
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  Future<void> _pickImage(ImageSource source) async {
    try {
      final picked = await _picker.pickImage(
          source: source, maxWidth: 1280, maxHeight: 720, imageQuality: 80);
      if (picked != null) {
        final bytes = await picked.readAsBytes();
        setState(() {
          _pickedImage = picked;
          _pickedImageBytes = bytes;
          _aiSuggestion = null;
          _aiCategory = null;
          _aiConfidence = null;
          _detectedLabels = [];
        });

        _autoFillLocation();

        if (kIsWeb) {
          _analyzeWithGeminiOnly(bytes);
        } else {
          _analyzePickedImage(File(picked.path));
        }
      }
    } catch (e) {
      debugPrint('Image pick error: $e');
    }
  }

  Future<Map<String, String>?> _uploadImageToStorage(String reportId) async {
    if (_pickedImage == null) return null;

    try {
      final path = 'incident-images/$reportId.jpg';
      final ref = FirebaseStorage.instance.ref().child(path);

      final bytes = _pickedImageBytes ?? await _pickedImage!.readAsBytes();
      debugPrint('Uploading image: ${bytes.length} bytes');

      setState(() => _uploadProgress = 0.1);

      late UploadTask uploadTask;
      final metadata = SettableMetadata(
        contentType: 'image/jpeg',
        cacheControl: 'public,max-age=31536000',
      );

      if (kIsWeb) {
        uploadTask = ref.putData(bytes, metadata);
      } else {
        uploadTask = ref.putFile(File(_pickedImage!.path), metadata);
      }

      final taskSnapshot = await uploadTask.timeout(
        const Duration(seconds: 30),
        onTimeout: () {
          throw TimeoutException('Upload timed out after 30 seconds');
        },
      );

      setState(() => _uploadProgress = 1.0);
      debugPrint('Upload state: ${taskSnapshot.state}');

      String downloadUrl;
      try {
        downloadUrl = await ref.getDownloadURL();
      } catch (e) {
        debugPrint('Failed to get download URL: $e');
        rethrow;
      }
      debugPrint('Upload complete. URL: $downloadUrl');

      return {'url': downloadUrl, 'path': path};
    } on TimeoutException catch (e) {
      debugPrint('Upload timeout: $e');
      rethrow;
    } catch (e) {
      debugPrint('Storage upload error: $e');
      rethrow;
    }
  }

  Future<void> _autoFillLocation() async {
    if (locCtrl.text.trim().isNotEmpty) return;

    setState(() => _locationFetching = true);
    try {
      final position = await getCurrentLocation();
      if (position != null) {
        try {
          final placemarks = await placemarkFromCoordinates(
            position.latitude,
            position.longitude,
          );
          if (placemarks.isNotEmpty) {
            final p = placemarks.first;
            final parts = <String>[
              if (p.name != null && p.name!.isNotEmpty) p.name!,
              if (p.street != null && p.street!.isNotEmpty && p.street != p.name) p.street!,
              if (p.subLocality != null && p.subLocality!.isNotEmpty) p.subLocality!,
              if (p.locality != null && p.locality!.isNotEmpty) p.locality!,
            ];
            final address = parts.take(3).join(', ');
            if (address.isNotEmpty) {
              setState(() => locCtrl.text = address);
            } else {
              setState(() => locCtrl.text = '${position.latitude.toStringAsFixed(5)}, ${position.longitude.toStringAsFixed(5)}');
            }
          }
        } catch (e) {
          setState(() => locCtrl.text = '${position.latitude.toStringAsFixed(5)}, ${position.longitude.toStringAsFixed(5)}');
        }
      }
    } catch (e) {
      debugPrint('Auto-location error: $e');
    }
    setState(() => _locationFetching = false);
  }

  Future<void> _analyzePickedImage(File imageFile) async {
    setState(() => _isAnalyzing = true);

    try {
      List<String> labelStrings = [];
      List<String> objectStrings = [];
      String mlKitCategory = '';
      double confidence = 0.0;

      try {
        final incidentService = await IncidentCategorizationService.getInstance();
        final result = await incidentService.analyzeIncidentImage(imageFile);

        _labelResults = result.mlKitLabels.map((l) => {'description': l}).toList();
        _objectResults = result.objects.map((o) => {'name': o}).toList();

        labelStrings = result.mlKitLabels.map((l) => l.toLowerCase()).toList();
        objectStrings = result.objects.map((o) => o.toLowerCase()).toList();
        _detectedLabels = [...labelStrings.take(4), ...objectStrings.take(2)];
        mlKitCategory = result.categoryName;
        confidence = result.confidence;
      } catch (e) {
        debugPrint('ML Kit analysis error: $e');
      }

      await _geminiAnalyze(
        imageFile: imageFile,
        labelStrings: labelStrings,
        objectStrings: objectStrings,
        mlKitCategory: mlKitCategory,
        confidence: confidence,
      );
    } catch (e) {
      debugPrint('Image analysis error: $e');
      setState(() => _isAnalyzing = false);
    }
  }

  Future<void> _analyzeWithGeminiOnly(Uint8List imageBytes) async {
    setState(() => _isAnalyzing = true);
    try {
      await _geminiAnalyze(
        imageBytes: imageBytes,
        labelStrings: [],
        objectStrings: [],
        mlKitCategory: '',
        confidence: 0.0,
      );
    } catch (e) {
      debugPrint('Gemini web analysis error: $e');
      setState(() => _isAnalyzing = false);
    }
  }

  Future<void> _geminiAnalyze({
    File? imageFile,
    Uint8List? imageBytes,
    required List<String> labelStrings,
    required List<String> objectStrings,
    required String mlKitCategory,
    required double confidence,
  }) async {
    try {
      final gemini = await GeminiService.getInstance();

      final validTypes = _fixedCategories.where((c) => c != "Other").join(', ');
      final mlKitContext = labelStrings.isNotEmpty
          ? 'On-device ML Kit detected labels: ${labelStrings.join(", ")}\n'
            'Detected objects: ${objectStrings.join(", ")}\n'
            'ML Kit suggested category: $mlKitCategory\n\n'
          : '';

      final prompt =
          'You are a campus safety AI assistant. Analyze this photo of a reported incident.\n'
          '$mlKitContext'
          'TASK: Return ONLY a valid JSON object with these fields:\n'
          '1. "type": one of [$validTypes] OR a custom short type name if none fit\n'
          '2. "description": a factual 2-3 sentence incident description for a campus safety report\n'
          '3. "labels": array of up to 5 relevant keywords detected\n\n'
          'Return ONLY the JSON, no markdown, no backticks, no extra text.\n'
          'Example: {"type":"Fire","description":"Incident reported: A small fire...","labels":["fire","smoke"]}';

      String aiResponse = '';
      if (imageFile != null) {
        aiResponse = await gemini.sendMessageWithImage(prompt, imageFile);
      } else if (imageBytes != null) {
        aiResponse = await gemini.sendMessageWithImageBytes(prompt, imageBytes);
      }

      String aiDescription = '';
      String aiType = '';
      List<String> aiLabels = [];

      try {
        String cleaned = aiResponse.trim();
        int firstBrace = cleaned.indexOf('{');
        int lastBrace = cleaned.lastIndexOf('}');
        if (firstBrace >= 0 && lastBrace > firstBrace) {
          cleaned = cleaned.substring(firstBrace, lastBrace + 1);
        }
        final parsed = jsonDecode(cleaned);
        aiType = parsed['type']?.toString() ?? '';
        aiDescription = parsed['description']?.toString() ?? '';
        aiLabels = (parsed['labels'] as List?)?.map((e) => e.toString()).toList() ?? [];
      } catch (e) {
        debugPrint('JSON parse error, using raw response: $e');
        aiDescription = aiResponse;
      }

      setState(() {
        _isAnalyzing = false;
        _aiSuggestion = aiDescription;
        _aiConfidence = confidence > 0 ? confidence : 0.7;

        if (aiType.isNotEmpty) {
          _aiCategory = aiType;
          if (_fixedCategories.contains(aiType)) {
            category = aiType;
          } else {
            category = "Other";
            _customTypeCtrl.text = aiType;
          }
        }

        if (aiLabels.isNotEmpty) {
          final allLabels = {..._detectedLabels, ...aiLabels};
          _detectedLabels = allLabels.take(6).toList();
        }

        if (detailsCtrl.text.trim().isEmpty && aiDescription.isNotEmpty) {
          detailsCtrl.text = aiDescription;
        }
      });
    } catch (e) {
      debugPrint('Gemini analysis error: $e');
      setState(() {
        _isAnalyzing = false;
        if (labelStrings.isNotEmpty) {
          _aiCategory = _suggestTypeFromLabels(labelStrings + objectStrings);
          category = _aiCategory!;
          _aiSuggestion = 'Detected: ${labelStrings.take(4).join(", ")}';
          if (detailsCtrl.text.trim().isEmpty) {
            detailsCtrl.text = 'Incident detected with: ${labelStrings.take(4).join(", ")}';
          }
        }
      });
    }
  }

  String _suggestTypeFromLabels(List<String> labels) {
    final keywords = labels.join(' ');
    if (keywords.contains('weapon') || keywords.contains('gun') || keywords.contains('knife')) return 'Suspicious';
    if (keywords.contains('fight') || keywords.contains('assault') || keywords.contains('punch')) return 'Harassment';
    if (keywords.contains('phone') || keywords.contains('wallet') || keywords.contains('theft') || keywords.contains('steal')) return 'Theft';
    if (keywords.contains('fire') || keywords.contains('smoke') || keywords.contains('flood')) return 'Other';
    return category;
  }

  void submitReport(String userId, String category, String details, String location) async {
    if (details.isEmpty && _pickedImage == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please add a description or photo')),
      );
      return;
    }

    setState(() {
      isLoading = true;
      _uploadProgress = 0.0;
      _submitStatusText = 'Preparing report...';
    });

    try {
      String finalType = category;
      if (category == "Other" && _customTypeCtrl.text.trim().isNotEmpty) {
        finalType = _customTypeCtrl.text.trim();
      }

      setState(() => _submitStatusText = 'Generating report ID...');
      final results = await Future.wait([
        fetchUserInfo(),
        generateCustomReportId(finalType),
      ]);
      final userInfo = results[0] as UserInfo;
      final reportId = results[1] as String;

      String? imageUrl;
      String? imagePath;

      if (_pickedImage != null) {
        setState(() => _submitStatusText = 'Uploading photo...');
        final uploadResult = await _uploadImageToStorage(reportId);
        if (uploadResult != null) {
          imageUrl = uploadResult['url'];
          imagePath = uploadResult['path'];
        }
      }

      setState(() => _submitStatusText = 'Saving report...');
      await addReport(
        userName: userInfo.username,
        userId: userId,
        course: userInfo.course,
        type: finalType,
        details: details,
        location: location,
        reportId: reportId,
        imageUrl: imageUrl,
        imagePath: imagePath,
        imageLabels: _labelResults,
        imageObjects: _objectResults,
      );

      setState(() {
        isLoading = false;
        _uploadProgress = 0.0;
        _submitStatusText = '';
      });
      _showSuccessDialog();
    } catch (e) {
      debugPrint('Submit error: $e');
      setState(() {
        isLoading = false;
        _uploadProgress = 0.0;
        _submitStatusText = '';
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error submitting report: $e')),
        );
      }
    }
  }
}
