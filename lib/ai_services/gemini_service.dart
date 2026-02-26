import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

class GeminiService {
  late final GenerativeModel _model;
  late final GenerativeModel _visionModel;
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

    // Initialize the model - using gemini-2.5-flash
    _model = GenerativeModel(
      model: 'gemini-2.5-flash',
      apiKey: apiKey,
    );
    
    // Also initialize a vision-capable model for streaming
    _visionModel = GenerativeModel(
      model: 'gemini-2.5-flash',
      apiKey: apiKey,
      generationConfig: GenerationConfig(
        temperature: 0.7,
        maxOutputTokens: 2048,
      ),
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

  /// Stream text responses for real-time feedback
  Stream<String> streamTextMessage(String message) async* {
    try {
      final content = Content.text(message);
      final response = await _model.generateContentStream([content]);
      
      await for (final chunk in response) {
        final text = chunk.text ?? '';
        if (text.isNotEmpty) {
          yield text;
        }
      }
    } catch (e) {
      yield 'Error: ${e.toString()}';
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

  /// Stream response for image analysis - real-time AI feedback
  /// This is the key feature for the live AI assistant
  Stream<String> streamImageAnalysis(String message, Uint8List imageBytes) async* {
    try {
      final imagePart = DataPart('image/jpeg', imageBytes);
      final textPart = TextPart(message);
      
      final content = [
        Content.multi([textPart, imagePart])
      ];
      
      // Use generateContentStream for streaming responses
      final response = await _visionModel.generateContentStream(content);
      
      await for (final chunk in response) {
        final text = chunk.text ?? '';
        if (text.isNotEmpty) {
          yield text;
        }
      }
    } catch (e) {
      yield 'Error analyzing image: ${e.toString()}';
    }
  }

  /// Quick image analysis without streaming (for quick captures)
  Future<String> analyzeImageQuick(String prompt, Uint8List imageBytes) async {
    try {
      final imagePart = DataPart('image/jpeg', imageBytes);
      final textPart = TextPart(prompt);
      
      final content = [
        Content.multi([textPart, imagePart])
      ];
      
      final response = await _visionModel.generateContent(content);
      return response.text ?? 'Could not analyze the image.';
    } catch (e) {
      return 'Error: ${e.toString()}';
    }
  }
}
