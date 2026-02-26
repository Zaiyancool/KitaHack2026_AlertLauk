import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';

class SpeechToTextService {
  static SpeechToTextService? _instance;
  late stt.SpeechToText _speech;
  bool _isInitialized = false;
  bool _isListening = false;
  String? _lastError;
  
  // Track if we've already processed final result to avoid duplicates
  bool _hasProcessedFinalResult = false;

  // Store the last recognized words to detect changes
  String _lastRecognizedWords = '';

  // Supported languages for Malaysian context
  static const Map<String, String> supportedLanguages = {
    'en_US': 'English (US)',
    'en_MY': 'English (Malaysia)',
    'ms_MY': 'Malay (Malaysia)',
    'zh_CN': 'Mandarin (China)',
    'zh_MY': 'Mandarin (Malaysia)',
    'zh_SG': 'Mandarin (Singapore)',
  };

  // Callbacks
  Function(String)? onResult;
  Function()? onListeningStarted;
  Function()? onListeningStopped;
  Function(String)? onError;

  SpeechToTextService._();

  static SpeechToTextService getInstance() {
    _instance ??= SpeechToTextService._();
    return _instance!;
  }

  Future<bool> initialize() async {
    if (_isInitialized) return true;

    _speech = stt.SpeechToText();
    
    try {
      // First check if we have permission
      var status = await Permission.microphone.status;
      if (!status.isGranted) {
        // Request microphone permission
        status = await Permission.microphone.request();
        if (!status.isGranted) {
          _lastError = 'Microphone permission denied';
          debugPrint('Microphone permission denied');
          return false;
        }
      }
      
      // Check if speech recognition is available on the device
      final isAvailable = await _speech.initialize(
        onError: (error) {
          debugPrint('Speech error: $error');
          _isListening = false;
          _hasProcessedFinalResult = false;
          _lastError = error.errorMsg;
          onError?.call(error.errorMsg);
        },
        onStatus: (status) {
          debugPrint('Speech status: $status');
          if (status == 'done' || status == 'notListening') {
            _isListening = false;
            // Only call onListeningStopped if we haven't processed final result
            if (!_hasProcessedFinalResult) {
              onListeningStopped?.call();
            }
          }
        },
      );
      
      _isInitialized = isAvailable;
      
      if (_isInitialized) {
        debugPrint('Speech-to-Text initialized successfully');
      } else {
        _lastError = 'Speech recognition not available on this device';
        debugPrint('Speech recognition not available');
      }
      
      return _isInitialized;
    } catch (e) {
      debugPrint('Speech initialization error: $e');
      _lastError = e.toString();
      _isInitialized = false;
      return false;
    }
  }

  String? get lastError => _lastError;
  bool get isInitialized => _isInitialized;
  bool get isListening => _isListening;

  /// Get available locales for speech recognition
  Future<List<stt.LocaleName>> getLocales() async {
    if (!_isInitialized) {
      await initialize();
    }
    return _speech.locales();
  }

  /// Get the list of supported languages
  static List<MapEntry<String, String>> getSupportedLanguages() {
    return supportedLanguages.entries.toList();
  }

  /// Get default locale for Malaysian context
  String getDefaultLocale() {
    // Default to Malay (Malaysia) for better local recognition
    return 'ms_MY';
  }

  Future<void> startListening({
    String? localeId, // Allow passing custom locale
    Function(String)? onResult,
    Function()? onListeningStarted,
    Function()? onListeningStopped,
    Function(String)? onError,
  }) async {
    if (!_isInitialized) {
      final initialized = await initialize();
      if (!initialized) {
        onError?.call(_lastError ?? 'Speech recognition not available');
        return;
      }
    }

    // Use the provided locale or default to Malay (Malaysia) for better local recognition
    final selectedLocale = localeId ?? getDefaultLocale();
    debugPrint('Starting speech recognition with locale: $selectedLocale');

    // Reset all tracking flags
    _hasProcessedFinalResult = false;
    _lastRecognizedWords = '';

    // Set callbacks
    this.onResult = onResult;
    this.onListeningStarted = onListeningStarted;
    this.onListeningStopped = onListeningStopped;
    this.onError = onError;

    _isListening = true;
    onListeningStarted?.call();

    // Start listening - only process final results to avoid duplicates
    await _speech.listen(
      onResult: (SpeechRecognitionResult result) {
        debugPrint('Speech result: final=${result.finalResult}, words="${result.recognizedWords}"');
        
        // Only process FINAL results, ignore partial results during listening
        if (result.finalResult && !_hasProcessedFinalResult) {
          _hasProcessedFinalResult = true;
          _isListening = false;
          
          // Only call callbacks once
          onResult?.call(result.recognizedWords);
          onListeningStopped?.call();
        }
        // Ignore partial results - they cause duplication issues
      },
      listenFor: const Duration(seconds: 60),
      pauseFor: const Duration(seconds: 8),
      localeId: selectedLocale,
      cancelOnError: true,
      partialResults: false, // Disable partial results to avoid duplication
    );
  }

  Future<void> stopListening() async {
    if (_isListening) {
      await _speech.stop();
      _isListening = false;
      _hasProcessedFinalResult = false;
      onListeningStopped?.call();
    }
  }

  Future<void> cancelListening() async {
    if (_isListening) {
      await _speech.cancel();
      _isListening = false;
      _hasProcessedFinalResult = false;
      onListeningStopped?.call();
    }
  }

  void dispose() {
    _speech.cancel();
    _isListening = false;
    _hasProcessedFinalResult = false;
  }
}
