import 'dart:io';
import 'dart:typed_data';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

class GeminiService {
  late final GenerativeModel _model;
  static GeminiService? _instance;

  GeminiService._();

  static Future<GeminiService> getInstance() async {
    if (_instance == null) {
      _instance = GeminiService._();
      await _instance!._initialize();
    }
    return _instance!;
  }

  Future<void> _initialize() async {
    // Load API key from .env file
    await dotenv.load(fileName: '.env');
    
    final apiKey = dotenv.env['GEMINI_API_KEY'];
    
    if (apiKey == null || apiKey.isEmpty) {
      throw Exception('GEMINI_API_KEY not found in .env file');
    }

    // Initialize the model - using gemini-2.5-flash for best multimodal results
    _model = GenerativeModel(
      model: 'gemini-2.5-flash',
      apiKey: apiKey,
    );
  }

  /// Send a text message and get AI response
  Future<String> sendMessage(String message) async {
    try {
      final content = Content.text(message);
      final response = await _model.generateContent([content]);
      return response.text ?? 'Sorry, I could not generate a response.';
    } catch (e) {
      return 'Error: ${e.toString()}';
    }
  }

  /// Send a message with image File for multimodal AI (mobile)
  Future<String> sendMessageWithImage(String message, File imageFile) async {
    try {
      final imageBytes = await imageFile.readAsBytes();
      return await sendMessageWithImageBytes(message, imageBytes);
    } catch (e) {
      return 'Error: ${e.toString()}';
    }
  }

  /// Send a message with image bytes for multimodal AI (works on web + mobile)
  Future<String> sendMessageWithImageBytes(String message, Uint8List imageBytes) async {
    try {
      final imagePart = DataPart('image/jpeg', imageBytes);
      final textPart = TextPart(message);
      
      final content = [
        Content.multi([textPart, imagePart])
      ];
      
      final response = await _model.generateContent(content);
      return response.text ?? 'Sorry, I could not analyze the image.';
    } catch (e) {
      return 'Error: ${e.toString()}';
    }
  }
}
