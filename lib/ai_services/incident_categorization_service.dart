import 'dart:io';
import 'package:google_mlkit_image_labeling/google_mlkit_image_labeling.dart';
import 'package:google_mlkit_object_detection/google_mlkit_object_detection.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'vision_ai_service.dart';

/// Incident Categorization Service
/// Uses Google ML Kit + Cloud Vision API to analyze incident photos
/// and auto-categorize them (weapon, fire, injury, etc.)
/// 
/// This implements the MVP feature:
/// - Google Cloud Vision AI (Best MVP)
/// - Use Case: Analyze incident photos to auto-categorize
/// - Impact: Auto-fill incident type from photo in reports
class IncidentCategorizationService {
  static IncidentCategorizationService? _instance;
  
  // ML Kit detectors
  late final ImageLabeler _imageLabeler;
  late final ObjectDetector _objectDetector;
  
  // Cloud Vision service
  late VisionAIService _visionAI;
  
  // Incident categories with keywords
  static const Map<IncidentCategory, List<String>> categoryKeywords = {
    IncidentCategory.fire: ['fire', 'flame', 'smoke', 'burn', 'firefighter', 'fire truck', 'emergency'],
    IncidentCategory.weapon: ['gun', 'knife', 'weapon', 'firearm', 'blade', 'sword', 'arm', 'ammunition'],
    IncidentCategory.injury: ['injury', 'bleeding', 'wound', 'accident', 'person', 'human', 'victim', 'hurt'],
    IncidentCategory.vehicle: ['car', 'vehicle', 'motorcycle', 'truck', 'accident', 'collision', 'transport'],
    IncidentCategory.theft: ['theft', 'robbery', 'burglary', 'stolen', 'suspicious', 'breaking', 'entry'],
    IncidentCategory.violence: ['fight', 'assault', 'violence', 'attack', 'threat', 'danger', 'crowd'],
    IncidentCategory.naturalDisaster: ['flood', 'earthquake', 'storm', 'disaster', 'tree', 'landslide', 'collapse'],
    IncidentCategory.suspicious: ['suspicious', 'unattended', 'package', 'bomb', 'threat', 'alert', 'warning'],
    IncidentCategory.other: [], // Default category
  };

  IncidentCategorizationService._();

  static Future<IncidentCategorizationService> getInstance() async {
    if (_instance == null) {
      _instance = IncidentCategorizationService._();
      await _instance!._initialize();
    }
    return _instance!;
  }

  Future<void> _initialize() async {
    await dotenv.load(fileName: '.env');
    
    // Initialize ML Kit Image Labeler
    final imageLabelerOptions = ImageLabelerOptions(confidenceThreshold: 0.5);
    _imageLabeler = ImageLabeler(options: imageLabelerOptions);
    
    // Initialize ML Kit Object Detector
    final objectDetectorOptions = ObjectDetectorOptions(
      mode: DetectionMode.single,
      classifyObjects: true,
      multipleObjects: false,
    );
    _objectDetector = ObjectDetector(options: objectDetectorOptions);
    
    // Initialize Cloud Vision AI
    _visionAI = await VisionAIService.getInstance();
  }

  /// Analyze incident image and return category
  /// Uses both ML Kit (on-device) + Cloud Vision API (cloud-based)
  Future<IncidentAnalysisResult> analyzeIncidentImage(File imageFile) async {
    try {
      // 1. On-device ML Kit Analysis (fast, works offline)
      final mlKitResults = await _analyzeWithMLKit(imageFile);
      
      // 2. Cloud Vision API Analysis (more accurate, online)
      final cloudResults = await _analyzeWithCloudVision(imageFile);
      
      // 3. Combine results and determine category
      final allLabels = [...mlKitResults.labels, ...cloudResults.labels];
      final category = _determineCategory(allLabels);
      final confidence = _calculateConfidence(allLabels, category);
      
      // 4. Generate auto-fill suggestion
      final suggestion = _generateSuggestion(category, allLabels);
      
      return IncidentAnalysisResult(
        category: category,
        confidence: confidence,
        detectedLabels: allLabels,
        suggestion: suggestion,
        mlKitLabels: mlKitResults.labels,
        cloudLabels: cloudResults.labels,
        objects: mlKitResults.objects,
        isSafeContent: cloudResults.isSafe,
      );
    } catch (e) {
      return IncidentAnalysisResult(
        category: IncidentCategory.other,
        confidence: 0.0,
        detectedLabels: [],
        suggestion: 'Unable to analyze image. Please select category manually.',
        error: e.toString(),
      );
    }
  }

  /// Analyze with ML Kit (on-device, fast)
  Future<_MLKitResult> _analyzeWithMLKit(File imageFile) async {
    final labels = <String>[];
    final objects = <String>[];
    
    try {
      // Image labeling
      final inputImage = InputImage.fromFile(imageFile);
      final labelResults = await _imageLabeler.processImage(inputImage);
      labels.addAll(labelResults.map((l) => l.label));
      
      // Object detection
      final objectResults = await _objectDetector.processImage(inputImage);
      for (final obj in objectResults) {
        objects.add(obj.labels.map((l) => l.text).join(', '));
      }
    } catch (e) {
      // ML Kit failed, continue with Cloud Vision
    }
    
    return _MLKitResult(labels: labels, objects: objects);
  }

  /// Analyze with Cloud Vision API (more accurate)
  Future<_CloudVisionResult> _analyzeWithCloudVision(File imageFile) async {
    final labels = <String>[];
    bool isSafe = true;
    
    try {
      // Get labels
      final labelResults = await _visionAI.detectLabels(imageFile);
      labels.addAll(labelResults.map((l) => l.description));
      
      // Check safe search
      final safeSearch = await _visionAI.detectSafeSearch(imageFile);
      isSafe = safeSearch.isSafe;
    } catch (e) {
      // Cloud Vision failed, continue with ML Kit results
    }
    
    return _CloudVisionResult(labels: labels, isSafe: isSafe);
  }

  /// Determine incident category from detected labels
  IncidentCategory _determineCategory(List<String> labels) {
    final lowerLabels = labels.map((l) => l.toLowerCase()).toList();
    
    // Score each category
    final scores = <IncidentCategory, double>{};
    
    for (final category in IncidentCategory.values) {
      if (category == IncidentCategory.other) continue;
      
      final keywords = categoryKeywords[category]!;
      double score = 0;
      
      for (final keyword in keywords) {
        for (final label in lowerLabels) {
          if (label.contains(keyword)) {
            score += 1;
          }
        }
      }
      
      scores[category] = score;
    }
    
    // Find highest scoring category
    IncidentCategory bestCategory = IncidentCategory.other;
    double bestScore = 0;
    
    scores.forEach((category, score) {
      if (score > bestScore) {
        bestScore = score;
        bestCategory = category;
      }
    });
    
    return bestCategory;
  }

  /// Calculate confidence score
  double _calculateConfidence(List<String> labels, IncidentCategory category) {
    if (labels.isEmpty) return 0.0;
    
    final lowerLabels = labels.map((l) => l.toLowerCase()).toList();
    final keywords = categoryKeywords[category] ?? [];
    
    int matchCount = 0;
    for (final keyword in keywords) {
      for (final label in lowerLabels) {
        if (label.contains(keyword)) {
          matchCount++;
        }
      }
    }
    
    // Return confidence as percentage (0-1)
    return (matchCount / keywords.length).clamp(0.0, 1.0);
  }

  /// Generate suggestion text for auto-fill
  String _generateSuggestion(IncidentCategory category, List<String> labels) {
    final categoryNames = {
      IncidentCategory.fire: 'Fire Incident',
      IncidentCategory.weapon: 'Weapon-related Incident',
      IncidentCategory.injury: 'Injury/Medical Emergency',
      IncidentCategory.vehicle: 'Vehicle Accident',
      IncidentCategory.theft: 'Theft/Robbery',
      IncidentCategory.violence: 'Violence/Assault',
      IncidentCategory.naturalDisaster: 'Natural Disaster',
      IncidentCategory.suspicious: 'Suspicious Activity',
      IncidentCategory.other: 'Other Incident',
    };
    
    final categoryName = categoryNames[category] ?? 'Other Incident';
    final topLabels = labels.take(3).join(', ');
    
    return 'Suggested: $categoryName\nDetected: $topLabels';
  }

  void dispose() {
    _imageLabeler.close();
    _objectDetector.close();
  }
}

// ==================== Data Models ====================

/// Incident categories for classification
enum IncidentCategory {
  fire,
  weapon,
  injury,
  vehicle,
  theft,
  violence,
  naturalDisaster,
  suspicious,
  other,
}

/// Result of incident analysis
class IncidentAnalysisResult {
  final IncidentCategory category;
  final double confidence;
  final List<String> detectedLabels;
  final String suggestion;
  final List<String> mlKitLabels;
  final List<String> cloudLabels;
  final List<String> objects;
  final bool isSafeContent;
  final String? error;

  IncidentAnalysisResult({
    required this.category,
    required this.confidence,
    required this.detectedLabels,
    required this.suggestion,
    this.mlKitLabels = const [],
    this.cloudLabels = const [],
    this.objects = const [],
    this.isSafeContent = true,
    this.error,
  });

  /// Get category display name
  String get categoryName {
    final names = {
      IncidentCategory.fire: '🔥 Fire Incident',
      IncidentCategory.weapon: '🔫 Weapon',
      IncidentCategory.injury: '🏥 Injury/Medical',
      IncidentCategory.vehicle: '🚗 Vehicle Accident',
      IncidentCategory.theft: '🔓 Theft/Robbery',
      IncidentCategory.violence: '⚠️ Violence',
      IncidentCategory.naturalDisaster: '🌪️ Natural Disaster',
      IncidentCategory.suspicious: '❓ Suspicious',
      IncidentCategory.other: '📋 Other',
    };
    return names[category] ?? 'Unknown';
  }

  /// Check if analysis was successful
  bool get isSuccess => error == null;
}

// Helper classes for internal results
class _MLKitResult {
  final List<String> labels;
  final List<String> objects;

  _MLKitResult({required this.labels, required this.objects});
}

class _CloudVisionResult {
  final List<String> labels;
  final bool isSafe;

  _CloudVisionResult({required this.labels, required this.isSafe});
}
