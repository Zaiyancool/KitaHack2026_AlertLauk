import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';

/// Google Cloud Vision AI Service
/// Provides image analysis features: label detection, OCR, face detection, etc.
/// 
/// Free tier: 1,000 units/month
/// Pricing after free tier: $1.50 per 1,000 units
class VisionAIService {
  static VisionAIService? _instance;
  late String _apiKey;

  VisionAIService._();

  static Future<VisionAIService> getInstance() async {
    if (_instance == null) {
      _instance = VisionAIService._();
      await _instance!._initialize();
    }
    return _instance!;
  }

  Future<void> _initialize() async {
    await dotenv.load(fileName: '.env');
    _apiKey = dotenv.env['VISION_API_KEY'] ?? '';
    
    if (_apiKey.isEmpty) {
      throw Exception('VISION_API_KEY not found in .env file');
    }
  }

  /// Base URL for Google Cloud Vision API
  String get _baseUrl => 'https://vision.googleapis.com/v1/images:annotate';

  /// Send image to Google Cloud Vision API for analysis
  Future<Map<String, dynamic>> _annotateImage(
    File imageFile,
    List<String> featureTypes,
  ) async {
    try {
      // Read image as base64
      final imageBytes = await imageFile.readAsBytes();
      final base64Image = base64Encode(imageBytes);

      // Build features list
      final features = featureTypes.map((type) => {
        'type': type,
        'maxResults': 10,
      }).toList();

      // Build request body
      final requestBody = jsonEncode({
        'requests': [
          {
            'image': {
              'content': base64Image,
            },
            'features': features,
          }
        ]
      });

      // Send request
      final response = await http.post(
        Uri.parse('$_baseUrl?key=$_apiKey'),
        headers: {
          'Content-Type': 'application/json',
        },
        body: requestBody,
      );

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        throw Exception('Vision API Error: ${response.statusCode} - ${response.body}');
      }
    } catch (e) {
      throw Exception('Error calling Vision API: $e');
    }
  }

  /// Label Detection - Identify objects, locations, activities, etc.
  Future<List<LabelAnnotation>> detectLabels(File imageFile) async {
    final response = await _annotateImage(imageFile, ['LABEL_DETECTION']);
    
    final labels = response['responses']?[0]?['labelAnnotations'] as List? ?? [];
    return labels.map((label) => LabelAnnotation.fromJson(label)).toList();
  }

  /// Text Detection (OCR) - Extract text from images
  Future<List<TextAnnotation>> detectText(File imageFile) async {
    final response = await _annotateImage(imageFile, ['TEXT_DETECTION']);
    
    final texts = response['responses']?[0]?['textAnnotations'] as List? ?? [];
    return texts.map((text) => TextAnnotation.fromJson(text)).toList();
  }

  /// Face Detection - Detect faces with emotions and attributes
  Future<List<FaceAnnotation>> detectFaces(File imageFile) async {
    final response = await _annotateImage(imageFile, ['FACE_DETECTION']);
    
    final faces = response['responses']?[0]?['faceAnnotations'] as List? ?? [];
    return faces.map((face) => FaceAnnotation.fromJson(face)).toList();
  }

  /// Landmark Detection - Identify famous places/landmarks
  Future<List<LandmarkAnnotation>> detectLandmarks(File imageFile) async {
    final response = await _annotateImage(imageFile, ['LANDMARK_DETECTION']);
    
    final landmarks = response['responses']?[0]?['landmarkAnnotations'] as List? ?? [];
    return landmarks.map((landmark) => LandmarkAnnotation.fromJson(landmark)).toList();
  }

  /// Logo Detection - Identify brand logos
  Future<List<LogoAnnotation>> detectLogos(File imageFile) async {
    final response = await _annotateImage(imageFile, ['LOGO_DETECTION']);
    
    final logos = response['responses']?[0]?['logoAnnotations'] as List? ?? [];
    return logos.map((logo) => LogoAnnotation.fromJson(logo)).toList();
  }

  /// Safe Search Detection - Detect explicit content
  Future<SafeSearchAnnotation> detectSafeSearch(File imageFile) async {
    final response = await _annotateImage(imageFile, ['SAFE_SEARCH_DETECTION']);
    
    final safeSearch = response['responses']?[0]?['safeSearchAnnotation'];
    return SafeSearchAnnotation.fromJson(safeSearch ?? {});
  }

  /// Object Localization - Detect and localize objects
  Future<List<ObjectAnnotation>> detectObjects(File imageFile) async {
    final response = await _annotateImage(imageFile, ['OBJECT_LOCALIZATION']);
    
    final objects = response['responses']?[0]?['localizedObjectAnnotations'] as List? ?? [];
    return objects.map((obj) => ObjectAnnotation.fromJson(obj)).toList();
  }

  /// Web Detection - Find similar images on the web
  Future<WebDetection> detectWeb(File imageFile) async {
    final response = await _annotateImage(imageFile, ['WEB_DETECTION']);
    
    final web = response['responses']?[0]?['webDetection'];
    return WebDetection.fromJson(web ?? {});
  }

  /// Combined analysis - Get multiple features at once
  Future<ImageAnalysisResult> analyzeImage(File imageFile) async {
    final features = [
      'LABEL_DETECTION',
      'TEXT_DETECTION',
      'FACE_DETECTION',
      'LANDMARK_DETECTION',
      'LOGO_DETECTION',
      'SAFE_SEARCH_DETECTION',
      'OBJECT_LOCALIZATION',
    ];

    final response = await _annotateImage(imageFile, features);
    return ImageAnalysisResult.fromJson(response['responses']?[0] ?? {});
  }
}

// ==================== Data Models ====================

class LabelAnnotation {
  final String description;
  final double score;
  final String mid;

  LabelAnnotation({
    required this.description,
    required this.score,
    required this.mid,
  });

  factory LabelAnnotation.fromJson(Map<String, dynamic> json) {
    return LabelAnnotation(
      description: json['description'] ?? '',
      score: (json['score'] ?? 0).toDouble(),
      mid: json['mid'] ?? '',
    );
  }
}

class TextAnnotation {
  final String description;
  final BoundingPoly? boundingPoly;
  final double score;

  TextAnnotation({
    required this.description,
    this.boundingPoly,
    required this.score,
  });

  factory TextAnnotation.fromJson(Map<String, dynamic> json) {
    return TextAnnotation(
      description: json['description'] ?? '',
      boundingPoly: json['boundingPoly'] != null 
          ? BoundingPoly.fromJson(json['boundingPoly']) 
          : null,
      score: (json['score'] ?? 0).toDouble(),
    );
  }
}

class BoundingPoly {
  final List<Vertex> vertices;

  BoundingPoly({required this.vertices});

  factory BoundingPoly.fromJson(Map<String, dynamic> json) {
    final verticesList = json['vertices'] as List? ?? [];
    return BoundingPoly(
      vertices: verticesList.map((v) => Vertex.fromJson(v)).toList(),
    );
  }
}

class Vertex {
  final int? x;
  final int? y;

  Vertex({this.x, this.y});

  factory Vertex.fromJson(Map<String, dynamic> json) {
    return Vertex(
      x: json['x'],
      y: json['y'],
    );
  }
}

class FaceAnnotation {
  final double joy;
  final double sorrow;
  final double anger;
  final double surprise;
  final double confidence;
  final BoundingPoly? boundingPoly;

  FaceAnnotation({
    required this.joy,
    required this.sorrow,
    required this.anger,
    required this.surprise,
    required this.confidence,
    this.boundingPoly,
  });

  factory FaceAnnotation.fromJson(Map<String, dynamic> json) {
    return FaceAnnotation(
      joy: (json['joyLikelihood'] ?? 0).toDouble(),
      sorrow: (json['sorrowLikelihood'] ?? 0).toDouble(),
      anger: (json['angerLikelihood'] ?? 0).toDouble(),
      surprise: (json['surpriseLikelihood'] ?? 0).toDouble(),
      confidence: (json['detectionConfidence'] ?? 0).toDouble(),
      boundingPoly: json['boundingPoly'] != null 
          ? BoundingPoly.fromJson(json['boundingPoly']) 
          : null,
    );
  }

  String get dominantEmotion {
    final emotions = {'Joy': joy, 'Sorrow': sorrow, 'Anger': anger, 'Surprise': surprise};
    return emotions.entries.reduce((a, b) => a.value > b.value ? a : b).key;
  }
}

class LandmarkAnnotation {
  final String description;
  final double score;
  final String mid;
  final BoundingPoly? boundingPoly;
  final String? location;

  LandmarkAnnotation({
    required this.description,
    required this.score,
    required this.mid,
    this.boundingPoly,
    this.location,
  });

  factory LandmarkAnnotation.fromJson(Map<String, dynamic> json) {
    return LandmarkAnnotation(
      description: json['description'] ?? '',
      score: (json['score'] ?? 0).toDouble(),
      mid: json['mid'] ?? '',
      boundingPoly: json['boundingPoly'] != null 
          ? BoundingPoly.fromJson(json['boundingPoly']) 
          : null,
      location: json['locations']?[0]?.['latLng']?.toString(),
    );
  }
}

class LogoAnnotation {
  final String description;
  final double score;
  final BoundingPoly? boundingPoly;

  LogoAnnotation({
    required this.description,
    required this.score,
    this.boundingPoly,
  });

  factory LogoAnnotation.fromJson(Map<String, dynamic> json) {
    return LogoAnnotation(
      description: json['description'] ?? '',
      score: (json['score'] ?? 0).toDouble(),
      boundingPoly: json['boundingPoly'] != null 
          ? BoundingPoly.fromJson(json['boundingPoly']) 
          : null,
    );
  }
}

class SafeSearchAnnotation {
  final String adult;
  final String violence;
  final String racy;

  SafeSearchAnnotation({
    required this.adult,
    required this.violence,
    required this.racy,
  });

  factory SafeSearchAnnotation.fromJson(Map<String, dynamic> json) {
    return SafeSearchAnnotation(
      adult: json['adult'] ?? 'UNKNOWN',
      violence: json['violence'] ?? 'UNKNOWN',
      racy: json['racy'] ?? 'UNKNOWN',
    );
  }

  bool get isSafe => adult == 'VERY_UNLIKELY' && violence == 'VERY_UNLIKELY';
}

class ObjectAnnotation {
  final String name;
  final double score;
  final BoundingPoly? boundingPoly;

  ObjectAnnotation({
    required this.name,
    required this.score,
    this.boundingPoly,
  });

  factory ObjectAnnotation.fromJson(Map<String, dynamic> json) {
    return ObjectAnnotation(
      name: json['name'] ?? '',
      score: (json['score'] ?? 0).toDouble(),
      boundingPoly: json['boundingPoly'] != null 
          ? BoundingPoly.fromJson(json['boundingPoly']) 
          : null,
    );
  }
}

class WebDetection {
  final List<String> pagesWithMatchingImages;
  final List<String> similarImages;
  final List<WebLabel> webLabels;

  WebDetection({
    required this.pagesWithMatchingImages,
    required this.similarImages,
    required this.webLabels,
  });

  factory WebDetection.fromJson(Map<String, dynamic> json) {
    final pagesList = json['pagesWithMatchingImages'] as List? ?? [];
    final similarList = json['similarImages'] as List? ?? [];
    final labelsList = json['webLabels'] as List? ?? [];
    
    return WebDetection(
      pagesWithMatchingImages: pagesList.map((e) => (e['url'] ?? '').toString()).toList().cast<String>(),
      similarImages: similarList.map((e) => (e['url'] ?? '').toString()).toList().cast<String>(),
      webLabels: labelsList.map((e) => WebLabel.fromJson(e as Map<String, dynamic>)).toList(),
    );
  }
}

class WebLabel {
  final String label;
  final double score;

  WebLabel({required this.label, required this.score});

  factory WebLabel.fromJson(Map<String, dynamic> json) {
    return WebLabel(
      label: json['label'] ?? '',
      score: (json['score'] ?? 0).toDouble(),
    );
  }
}

/// Combined result for comprehensive image analysis
class ImageAnalysisResult {
  final List<LabelAnnotation> labels;
  final List<TextAnnotation> texts;
  final List<FaceAnnotation> faces;
  final List<LandmarkAnnotation> landmarks;
  final List<LogoAnnotation> logos;
  final SafeSearchAnnotation? safeSearch;
  final List<ObjectAnnotation> objects;

  ImageAnalysisResult({
    required this.labels,
    required this.texts,
    required this.faces,
    required this.landmarks,
    required this.logos,
    this.safeSearch,
    required this.objects,
  });

  factory ImageAnalysisResult.fromJson(Map<String, dynamic> json) {
    return ImageAnalysisResult(
      labels: (json['labelAnnotations'] as List? ?? [])
          .map((e) => LabelAnnotation.fromJson(e)).toList(),
      texts: (json['textAnnotations'] as List? ?? [])
          .map((e) => TextAnnotation.fromJson(e)).toList(),
      faces: (json['faceAnnotations'] as List? ?? [])
          .map((e) => FaceAnnotation.fromJson(e)).toList(),
      landmarks: (json['landmarkAnnotations'] as List? ?? [])
          .map((e) => LandmarkAnnotation.fromJson(e)).toList(),
      logos: (json['logoAnnotations'] as List? ?? [])
          .map((e) => LogoAnnotation.fromJson(e)).toList(),
      safeSearch: json['safeSearchAnnotation'] != null 
          ? SafeSearchAnnotation.fromJson(json['safeSearchAnnotation']) 
          : null,
      objects: (json['localizedObjectAnnotations'] as List? ?? [])
          .map((e) => ObjectAnnotation.fromJson(e)).toList(),
    );
  }

  /// Generate a summary string of all detections
  String get summary {
    final parts = <String>[];

    if (labels.isNotEmpty) {
      parts.add('Labels: ${labels.take(3).map((l) => l.description).join(", ")}');
    }
    if (texts.isNotEmpty) {
      parts.add('Text found: ${texts.first.description.substring(0, texts.first.description.length.clamp(0, 50))}...');
    }
    if (faces.isNotEmpty) {
      parts.add('Faces detected: ${faces.length}');
    }
    if (landmarks.isNotEmpty) {
      parts.add('Landmark: ${landmarks.first.description}');
    }
    if (logos.isNotEmpty) {
      parts.add('Logo: ${logos.first.description}');
    }
    if (objects.isNotEmpty) {
      parts.add('Objects: ${objects.take(3).map((o) => o.name).join(", ")}');
    }
    if (safeSearch != null) {
      parts.add('Safe search: ${safeSearch!.isSafe ? "Safe ✅" : "Needs review ⚠️"}');
    }

    return parts.isEmpty ? 'No objects detected' : parts.join('\n');
  }
}
