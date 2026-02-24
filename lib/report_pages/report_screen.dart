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
  void dispose() {
    detailsCtrl.dispose();
    idCtrl.dispose();
    locCtrl.dispose();
    locDetailsCtrl.dispose();
    typeCtrl.dispose();
    _customTypeCtrl.dispose();
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

                // Custom type input when "Other" is selected (or AI suggests a new type)
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
                TextFieldMng(
                  controller: detailsCtrl,
                  obscureText: false,
                  hintText: "Describe the incident (AI will auto-fill from photo)",
                ),

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

  /// Build the photo capture / preview section
  Widget _buildPhotoSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Evidence Photo', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
        const SizedBox(height: 8),
        if (_pickedImage != null) ...[
          // Photo preview with remove button
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
              // Remove button
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
          // Re-take buttons
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
          // No photo yet — show pick buttons
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

  /// Save report to Firestore with the image download URL from Storage.
  /// This is the ONLY place a report document is created.
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

      // Only include ML Kit results when they have data (mobile-only)
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
              Navigator.pop(context); // close dialog
              Navigator.pop(context); // go back to previous screen
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
        // Read bytes for web support
        final bytes = await picked.readAsBytes();
        setState(() {
          _pickedImage = picked;
          _pickedImageBytes = bytes;
          // Reset previous analysis
          _aiSuggestion = null;
          _aiCategory = null;
          _aiConfidence = null;
          _detectedLabels = [];
        });

        // Auto-fetch location immediately
        _autoFillLocation();

        // Analyze the image (NO upload here — upload happens on submit)
        if (kIsWeb) {
          // On web: skip ML Kit, use Gemini directly with bytes
          _analyzeWithGeminiOnly(bytes);
        } else {
          _analyzePickedImage(File(picked.path));
        }
      }
    } catch (e) {
      debugPrint('Image pick error: $e');
    }
  }

  /// Upload image to Firebase Storage and return {url, path}.
  /// Simplified and optimized for web - no stream subscription that can hang.
  Future<Map<String, String>?> _uploadImageToStorage(String reportId) async {
    if (_pickedImage == null) return null;

    try {
      // Upload into the dedicated incident-images folder in the configured bucket
      final path = 'incident-images/$reportId.jpg';
      final ref = FirebaseStorage.instance.ref().child(path);

      // Prepare bytes (already cached from pick)
      final bytes = _pickedImageBytes ?? await _pickedImage!.readAsBytes();
      debugPrint('Uploading image: ${bytes.length} bytes');

      // Set initial progress
      setState(() => _uploadProgress = 0.1);

      // Start upload task
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

      // Wait for upload to complete - use try with timeout
      final taskSnapshot = await uploadTask.timeout(
        const Duration(seconds: 30),
        onTimeout: () {
          throw TimeoutException('Upload timed out after 30 seconds');
        },
      );

      // Update progress to completion
      setState(() => _uploadProgress = 1.0);
      debugPrint('Upload state: ${taskSnapshot.state}');

      // Get the public download URL
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
      rethrow; // Re-throw so the UI can handle the error
    }
  }

  /// Auto-fill location from GPS + reverse geocoding
  Future<void> _autoFillLocation() async {
    if (locCtrl.text.trim().isNotEmpty) return; // don't overwrite user input

    setState(() => _locationFetching = true);
    try {
      final position = await getCurrentLocation();
      if (position != null) {
        // Reverse geocode to get address
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
          // Fallback to raw coords
          setState(() => locCtrl.text = '${position.latitude.toStringAsFixed(5)}, ${position.longitude.toStringAsFixed(5)}');
        }
      }
    } catch (e) {
      debugPrint('Auto-location error: $e');
    }
    setState(() => _locationFetching = false);
  }

  /// Analyze picked image immediately using ML Kit + Gemini (mobile)
  Future<void> _analyzePickedImage(File imageFile) async {
    setState(() => _isAnalyzing = true);

    try {
      // Step 1: On-device ML Kit analysis for labels & category
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

      // Step 2: Use Gemini multimodal to generate description + suggest type
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

  /// Web-only: analyze using Gemini multimodal directly (no ML Kit)
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

  /// Core Gemini analysis — works for both mobile (File) and web (bytes)
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
        // For web, use Gemini multimodal with raw bytes
        aiResponse = await gemini.sendMessageWithImageBytes(prompt, imageBytes);
      }

      // Parse JSON response
      String aiDescription = '';
      String aiType = '';
      List<String> aiLabels = [];

      try {
        // Strip markdown code fences if present
        String cleaned = aiResponse.trim();
        if (cleaned.startsWith('```')) {
          cleaned = cleaned.replaceAll(RegExp(r'^```\w*\n?'), '').replaceAll(RegExp(r'\n?```$'), '').trim();
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

        // Auto-fill incident type from Gemini
        if (aiType.isNotEmpty) {
          _aiCategory = aiType;
          if (_fixedCategories.contains(aiType)) {
            category = aiType;
          } else {
            // Custom type from AI — set to "Other" and fill custom field
            category = "Other";
            _customTypeCtrl.text = aiType;
          }
        }

        // Merge Gemini labels with ML Kit labels
        if (aiLabels.isNotEmpty) {
          final allLabels = {..._detectedLabels, ...aiLabels};
          _detectedLabels = allLabels.take(6).toList();
        }

        // Auto-fill description
        if (detailsCtrl.text.trim().isEmpty && aiDescription.isNotEmpty) {
          detailsCtrl.text = aiDescription;
        }
      });
    } catch (e) {
      debugPrint('Gemini analysis error: $e');
      setState(() {
        _isAnalyzing = false;
        // Fallback: use ML Kit results if Gemini fails
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

  /// ── SUBMIT FLOW (clean linear) ──
  /// 1. Validate input
  /// 2. Generate report ID
  /// 3. Upload image to Firebase Storage → get download URL
  /// 4. Save report + image URL to Firestore
  /// 5. Show success
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
      // Resolve final type: if "Other", use custom text
      String finalType = category;
      if (category == "Other" && _customTypeCtrl.text.trim().isNotEmpty) {
        finalType = _customTypeCtrl.text.trim();
      }

      // Step 1: Fetch user info + generate report ID (parallel)
      setState(() => _submitStatusText = 'Generating report ID...');
      final results = await Future.wait([
        fetchUserInfo(),
        generateCustomReportId(finalType),
      ]);
      final userInfo = results[0] as UserInfo;
      final reportId = results[1] as String;

      // Step 2: Upload image to Firebase Storage (if photo attached)
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

      // Step 3: Save report + image URL to Firestore
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
