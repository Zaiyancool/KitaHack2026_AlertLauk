import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:image_picker/image_picker.dart';
import 'package:camera/camera.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:flutter_tts/flutter_tts.dart';

/// LiveTriageScreen - Real-time AI Safety Assistant with Voice
/// Uses Google Gemini REST API for image analysis
/// 
/// Features:
/// - Camera preview (mobile)
/// - AI speaks responses (Text-to-Speech)
/// - Voice input via microphone
/// - Auto-analysis every 1 second
class LiveTriageScreen extends StatefulWidget {
  const LiveTriageScreen({super.key});

  @override
  State<LiveTriageScreen> createState() => _LiveTriageScreenState();
}

class _LiveTriageScreenState extends State<LiveTriageScreen> {
  // Mobile camera
  CameraController? _cameraController;
  List<CameraDescription>? _cameras;
  
  // State flags
  bool _isCameraInitialized = false;
  bool _isCameraStarting = false;
  
  // Image picker for web/capture
  final ImagePicker _imagePicker = ImagePicker();
  
  // AI
  GenerativeModel? _model;
  bool _isInitialized = false;
  String? _apiKey;
  
  // Text-to-Speech
  FlutterTts? _tts;
  bool _isSpeaking = false;
  bool _ttsEnabled = true;
  
  // Voice Input (Speech-to-Text)
  stt.SpeechToText? _speech;
  bool _speechInitialized = false;
  bool _isListening = false;
  bool _wantsToListen = false; // stays true until user manually stops
  String _lastWords = '';
  
  // State
  String _statusMessage = 'Tap "Start Camera" to begin';
  String _geminiResponse = '';
  bool _isAnalyzing = false;
  
  // Captured image for display
  Uint8List? _capturedImageBytes;
  
  // Analysis timer - now every 1 second
  Timer? _autoAnalysisTimer;
  
  // Live monitoring state
  bool _isLiveMonitoring = false;
  DateTime? _lastAnalysisTime;
  static const _minAnalysisInterval = Duration(seconds: 2); // Analyze every 2 seconds max

  @override
  void initState() {
    super.initState();
    _initializeAI();
    _initializeTTS();
    _initializeSpeech();
  }

  Future<void> _initializeAI() async {
    await dotenv.load(fileName: '.env');
    _apiKey = dotenv.env['GEMINI_API_KEY'];
    
    if (_apiKey == null || _apiKey!.isEmpty) {
      setState(() {
        _statusMessage = 'Error: GEMINI_API_KEY not found in .env';
      });
      return;
    }
    
    _model = GenerativeModel(
      model: 'gemini-2.5-flash',
      apiKey: _apiKey!,
      generationConfig: GenerationConfig(
        temperature: 0.7,
        maxOutputTokens: 1024,
      ),
    );
    
    setState(() {
      _isInitialized = true;
      _statusMessage = 'AI Ready! Tap "Start Camera" to begin';
    });
  }

  Future<void> _initializeTTS() async {
    try {
      _tts = FlutterTts();
      
      // Try to get available voices
      try {
        dynamic voices = await _tts!.getVoices;
        debugPrint('Available voices: $voices');
        // Try to select a voice named "Orus" if present
        try {
          if (voices is List) {
            for (var v in voices) {
              String name = '';
              String locale = '';
              if (v is Map) {
                name = (v['name'] ?? v['voice'] ?? '').toString();
                locale = (v['locale'] ?? v['language'] ?? '').toString();
              } else {
                name = v.toString();
              }
              if (name.toLowerCase().contains('orus')) {
                try {
                  await _tts!.setVoice({'name': name, 'locale': locale});
                  debugPrint('Selected voice: $name ($locale)');
                } catch (e) {
                  debugPrint('Failed to set voice $name: $e');
                }
                break;
              }
            }
          }
        } catch (e) {
          debugPrint('Voice selection error: $e');
        }
      } catch (e) {
        debugPrint('Could not get voices: $e');
      }
      
      // Set language
      try {
        await _tts!.setLanguage("en-US");
      } catch (e) {
        debugPrint('Could not set language: $e');
      }
      
      // Set voice parameters for male voice effect
      try {
        await _tts!.setSpeechRate(0.5); // Slightly slower for clarity
        await _tts!.setVolume(1.0);
        await _tts!.setPitch(0.8); // Lower pitch for male voice effect
      } catch (e) {
        debugPrint('Could not set voice parameters: $e');
      }
      
      _tts!.setStartHandler(() {
        setState(() {
          _isSpeaking = true;
        });
      });
      
      _tts!.setCompletionHandler(() {
        setState(() {
          _isSpeaking = false;
        });
      });
      
      _tts!.setErrorHandler((msg) {
        debugPrint('TTS Error: $msg');
        setState(() {
          _isSpeaking = false;
        });
      });
    } catch (e) {
      debugPrint('TTS Initialization Error: $e');
      // Continue without TTS - app should still work
      _ttsEnabled = false;
      setState(() {
        _statusMessage = 'Note: Text-to-speech unavailable on this device';
      });
    }
  }

  Future<void> _initializeSpeech() async {
    _speech = stt.SpeechToText();
    try {
      final available = await _speech!.initialize(
        onError: (error) {
          // Do not aggressively restart; show status so user can retry
          setState(() {
            _isListening = false;
            _statusMessage = 'Speech error: ${error.errorMsg}';
          });
          debugPrint('Speech init onError: ${error.errorMsg}');
        },
        onStatus: (status) {
          // Status 'notListening' or 'done' means the plugin stopped listening.
          // We don't immediately restart to avoid rapid start/stop which causes
          // mic flicker on Android. The user can tap Speak to resume.
          if (status == 'done' || status == 'notListening') {
            setState(() {
              _isListening = false;
            });
          }
        },
      );

      setState(() {
        _speechInitialized = available;
      });
    } catch (e) {
      debugPrint('Speech init error: $e');
    }
  }

  /// Speak the given text using TTS
  Future<void> _speak(String text) async {
    if (!_ttsEnabled || _tts == null) {
      debugPrint('TTS disabled or not initialized');
      return;
    }
    
    try {
      // Stop any current speech
      await _tts!.stop();
      
      setState(() {
        _isSpeaking = true;
      });
      
      await _tts!.speak(text);
    } catch (e) {
      debugPrint('Error speaking: $e');
      setState(() {
        _isSpeaking = false;
      });
    }
  }

  /// Stop speaking
  Future<void> _stopSpeaking() async {
    try {
      if (_tts != null) {
        await _tts!.stop();
        setState(() {
          _isSpeaking = false;
        });
      }
    } catch (e) {
      debugPrint('Error stopping speech: $e');
      setState(() {
        _isSpeaking = false;
      });
    }
  }

  /// Start listening to voice (stays active until manually stopped)
  Future<void> _startListening() async {
    if (!_speechInitialized || _speech == null) {
      setState(() {
        _statusMessage = 'Voice recognition not available';
      });
      return;
    }
    // Keep microphone open for a long duration to avoid frequent stop/start
    // which causes the mic indicator to flicker on Android.
    _wantsToListen = true;
    setState(() {
      _isListening = true;
      _statusMessage = 'Listening... (tap again to stop)';
    });

    await _speech!.listen(
      onResult: (result) {
        setState(() {
          _lastWords = result.recognizedWords;
          if (result.finalResult && _lastWords.isNotEmpty) {
            _statusMessage = 'Heard: $_lastWords';
            _handleVoiceInput(_lastWords);
          }
        });
      },
      localeId: 'en_MY', // Malaysian English
      listenFor: const Duration(minutes: 30),
      pauseFor: const Duration(seconds: 30),
      partialResults: true,
    );
  }

  /// Restart listening silently (called by auto-restart logic)
  Future<void> _restartListening() async {
    // Keep for backward compatibility but avoid automatic restarts.
    if (!_speechInitialized || _speech == null || !_wantsToListen) return;
    try {
      await _speech!.listen(
        onResult: (result) {
          setState(() {
            _lastWords = result.recognizedWords;
            if (result.finalResult && _lastWords.isNotEmpty) {
              _statusMessage = 'Heard: $_lastWords';
              _handleVoiceInput(_lastWords);
            }
          });
        },
        localeId: 'en_MY',
        listenFor: const Duration(minutes: 30),
        pauseFor: const Duration(seconds: 30),
        partialResults: true,
      );
      setState(() {
        _isListening = true;
      });
    } catch (e) {
      debugPrint('Restart listening error: $e');
    }
  }

  /// Stop listening (user manually toggled off)
  Future<void> _stopListening() async {
    _wantsToListen = false;
    await _speech?.stop();
    setState(() {
      _isListening = false;
      _statusMessage = 'Voice input stopped';
    });
  }

  /// Handle voice input - either analyze image or ask question
  Future<void> _handleVoiceInput(String input) async {
    if (input.isEmpty) return;
    
    final lowerInput = input.toLowerCase();
    
    // Check for simple commands
    if (lowerInput.contains('analyze') || lowerInput.contains('look')) {
      // Capture and analyze current view
      await _captureAndAnalyze();
    } else if (lowerInput.contains('stop') || lowerInput.contains('quiet')) {
      await _stopSpeaking();
      setState(() {
        _statusMessage = 'AI stopped speaking';
      });
    } else if (lowerInput.contains('speak') || lowerInput.contains('talk')) {
      // Repeat last response
      if (_geminiResponse.isNotEmpty) {
        await _speak(_geminiResponse);
      }
    } else {
      // Treat as a question - analyze image + question
      await _askQuestion(input);
    }
  }

  /// Ask a question about the current image
  Future<void> _askQuestion(String question) async {
    if (_capturedImageBytes == null && !_isCameraInitialized) {
      setState(() {
        _statusMessage = 'Start camera first to ask about surroundings';
      });
      return;
    }
    
    if (_model == null) {
      setState(() {
        _statusMessage = 'Error: AI not initialized';
      });
      return;
    }
    
    setState(() {
      _statusMessage = 'Thinking about your question...';
    });
    
    try {
      // Capture current frame if camera is active
      Uint8List? imageBytes = _capturedImageBytes;
      if (imageBytes == null && _isCameraInitialized && _cameraController != null) {
        final XFile image = await _cameraController!.takePicture();
        imageBytes = await image.readAsBytes();
      }
      
      String prompt;
      if (imageBytes != null) {
        prompt = '''You are "Alert.AI", a friendly campus safety assistant. Talk naturally like a real person.
For casual questions, reply in 1-2 sentences. For dangerous/urgent situations, give the essential safety steps but keep it concise (3-5 sentences max). Always complete your thought. No bullet points or markdown.
        
User's question: "$question"

Look at the image and respond based on what you see.''';
        
        final imagePart = DataPart('image/jpeg', imageBytes);
        final textPart = TextPart(prompt);
        
        final content = [Content.multi([textPart, imagePart])];
        final response = await _model!.generateContent(content);
        
        setState(() {
          _geminiResponse = response.text ?? 'I\'m not sure how to answer that.';
          _statusMessage = 'Alert.AI is responding...';
        });
      } else {
        prompt = '''You are "Alert.AI", a friendly campus safety assistant. Talk naturally like a real person.
For casual questions, reply in 1-2 sentences. For dangerous/urgent situations, give the essential safety steps but keep it concise (3-5 sentences max). Always complete your thought. No bullet points or markdown.
        
User's question: "$question"

Respond naturally and directly.''';
        
        final content = [Content.text(prompt)];
        final response = await _model!.generateContent(content);
        
        setState(() {
          _geminiResponse = response.text ?? 'I\'m not sure how to answer that.';
          _statusMessage = 'Alert.AI is responding...';
        });
      }
      
      // Speak the response
      await _speak(_geminiResponse);
      
    } catch (e) {
      setState(() {
        _statusMessage = 'Error: $e';
      });
    }
  }

  @override
  void dispose() {
    _stopCamera();
    _autoAnalysisTimer?.cancel();
    _tts?.stop();
    _speech?.cancel();
    super.dispose();
  }

  /// Request necessary permissions
  Future<bool> _requestPermissions() async {
    var cameraStatus = await Permission.camera.request();
    if (!cameraStatus.isGranted) {
      setState(() {
        _statusMessage = 'Camera permission denied';
      });
      return false;
    }
    
    var micStatus = await Permission.microphone.request();
    if (!micStatus.isGranted) {
      debugPrint('Microphone permission denied (optional)');
    }
    
    return true;
  }

  /// Initialize camera
  Future<void> _startCamera() async {
    if (_isCameraStarting || _isCameraInitialized) return;
    
    setState(() {
      _isCameraStarting = true;
      _statusMessage = 'Starting camera...';
    });
    
    try {
      // Request permissions first
      final hasPermissions = await _requestPermissions();
      if (!hasPermissions) {
        setState(() {
          _isCameraStarting = false;
        });
        return;
      }
      
      // Get available cameras
      _cameras = await availableCameras();
      if (_cameras == null || _cameras!.isEmpty) {
        setState(() {
          _statusMessage = 'No cameras available';
          _isCameraStarting = false;
        });
        return;
      }
      
      // Use back camera
      final backCamera = _cameras!.firstWhere(
        (camera) => camera.lensDirection == CameraLensDirection.back,
        orElse: () => _cameras!.first,
      );
      
      _cameraController = CameraController(
        backCamera,
        ResolutionPreset.medium,
        enableAudio: false,
      );
      
      await _cameraController!.initialize();
      
      setState(() {
        _isCameraInitialized = true;
        _isCameraStarting = false;
        _statusMessage = 'Camera active! Tap mic to speak, or use auto-mode';
      });
    } catch (e) {
      setState(() {
        _statusMessage = 'Camera error: $e';
        _isCameraStarting = false;
      });
    }
  }

  /// Stop camera
  void _stopCamera() {
    _stopAutoAnalysis();
    _cameraController?.dispose();
    _cameraController = null;
    
    setState(() {
      _isCameraInitialized = false;
      _capturedImageBytes = null;
      _statusMessage = 'Camera stopped. Tap "Start Camera" to begin again.';
    });
  }

  /// Capture and analyze
  Future<void> _captureAndAnalyze() async {
    if (_isAnalyzing) return;
    
    setState(() {
      _isAnalyzing = true;
      _statusMessage = 'Analyzing surroundings...';
    });
    
    try {
      // Try to capture from live camera first
      if (_isCameraInitialized && _cameraController != null) {
        final XFile image = await _cameraController!.takePicture();
        _capturedImageBytes = await image.readAsBytes();
      } else {
        // Fallback to image_picker
        final XFile? image = await _imagePicker.pickImage(
          source: ImageSource.camera,
          imageQuality: 80,
          maxWidth: 1024,
          maxHeight: 1024,
        );
        
        if (image == null) {
          setState(() {
            _isAnalyzing = false;
            _statusMessage = 'No image captured';
          });
          return;
        }
        
        _capturedImageBytes = await image.readAsBytes();
      }
      
      // Analyze
      await _analyzeImage(_capturedImageBytes!);
      
    } catch (e) {
      setState(() {
        _statusMessage = 'Capture error: $e';
        _isAnalyzing = false;
      });
    }
  }

  /// Analyze the captured image
  Future<void> _analyzeImage(Uint8List imageBytes) async {
    if (_model == null) {
      setState(() {
        _statusMessage = 'Error: AI not initialized';
        _isAnalyzing = false;
      });
      return;
    }
    
    setState(() {
      _statusMessage = 'Alert.AI is analyzing...';
    });
    
    try {
      // Create prompt for safety analysis
      final prompt = '''You are "Alert.AI", a friendly campus safety assistant. Analyze this image for safety.

Check for flooding, storms, blocked paths, danger, or people in distress.

Give a practical safety assessment. If safe, say so in 1 sentence. If dangerous, explain what you see and what to do in 3-5 sentences. Talk naturally, no bullet points or markdown.''';
      
      // Send to Gemini
      final imagePart = DataPart('image/jpeg', imageBytes);
      final textPart = TextPart(prompt);
      
      final content = [Content.multi([textPart, imagePart])];
      final response = await _model!.generateContent(content);
      
      setState(() {
        _geminiResponse = response.text ?? 'Could not analyze the image.';
        _statusMessage = 'Analysis complete!';
        _isAnalyzing = false;
      });
      
      // Speak the response
      await _speak(_geminiResponse);
      
    } catch (e) {
      setState(() {
        _statusMessage = 'Analysis error: $e';
        _isAnalyzing = false;
      });
    }
  }

  /// Start auto-analysis mode - now every 1 second
  void _startAutoAnalysis() {
    _autoAnalysisTimer?.cancel();
    _autoAnalysisTimer = Timer.periodic(const Duration(seconds: 1), (Timer t) {
      if (!_isAnalyzing && _isCameraInitialized) {
        _captureAndAnalyze();
      }
    });
    
    setState(() {
      _statusMessage = 'Auto-mode ON! AI analyzes every second';
    });
  }

  /// Stop auto-analysis
  void _stopAutoAnalysis() {
    _autoAnalysisTimer?.cancel();
    _autoAnalysisTimer = null;
    
    setState(() {
      _statusMessage = 'Auto-mode OFF';
    });
  }

  /// Start Live Monitoring - continuous AI vision analysis
  /// This is the main feature that lets AI "see what you're doing"
  void _startLiveMonitoring() {
    if (!_isCameraInitialized || _model == null) {
      setState(() {
        _statusMessage = 'Start camera first to enable live monitoring';
      });
      return;
    }
    
    setState(() {
      _isLiveMonitoring = true;
      _lastAnalysisTime = DateTime.now();
    });
    
    // Start the continuous analysis timer
    _autoAnalysisTimer?.cancel();
    _autoAnalysisTimer = Timer.periodic(const Duration(seconds: 3), (Timer t) async {
      if (!_isLiveMonitoring || _isAnalyzing || !mounted) {
        return;
      }
      
      // Rate limiting - don't analyze too frequently
      final now = DateTime.now();
      if (_lastAnalysisTime != null && 
          now.difference(_lastAnalysisTime!) < _minAnalysisInterval) {
        return;
      }
      
      _lastAnalysisTime = now;
      await _performLiveAnalysis();
    });
    
    setState(() {
      _statusMessage = '🔴 LIVE MONITORING! AI is watching for dangers...';
    });
  }

  /// Stop Live Monitoring
  void _stopLiveMonitoring() {
    _autoAnalysisTimer?.cancel();
    _autoAnalysisTimer = null;
    
    setState(() {
      _isLiveMonitoring = false;
      _statusMessage = 'Live monitoring stopped';
    });
  }

  /// Perform live analysis for the monitoring mode
  /// This captures the current frame and analyzes it for safety
  Future<void> _performLiveAnalysis() async {
    if (_isAnalyzing || !_isCameraInitialized || _cameraController == null) return;
    
    setState(() {
      _isAnalyzing = true;
      _statusMessage = '🔴 AI is analyzing your surroundings...';
    });
    
    try {
      // Capture current frame
      final XFile image = await _cameraController!.takePicture();
      final imageBytes = await image.readAsBytes();
      
      // Store for display
      _capturedImageBytes = imageBytes;
      
      // Analyze with AI
      if (_model == null) {
        setState(() {
          _isAnalyzing = false;
        });
        return;
      }
      
      final prompt = '''You are "Alert.AI", a safety monitoring assistant.
If everything looks safe, say so in 1 sentence. If there is danger, explain the threat and what to do in 2-3 sentences. Always complete your thought. No markdown.''';
      
      final imagePart = DataPart('image/jpeg', imageBytes);
      final textPart = TextPart(prompt);
      
      final content = [Content.multi([textPart, imagePart])];
      final response = await _model!.generateContent(content);
      
      if (!_isLiveMonitoring || !mounted) return;
      
      setState(() {
        _geminiResponse = response.text ?? 'Monitoring active...';
        _statusMessage = '🔴 LIVE: $_geminiResponse';
        _isAnalyzing = false;
      });
      
      // Speak the alert if TTS is enabled and we detected something significant
      if (_ttsEnabled && _tts != null && _geminiResponse.isNotEmpty) {
        // Only speak if it contains safety-related keywords
        final responseLower = _geminiResponse.toLowerCase();
        if (responseLower.contains('danger') || 
            responseLower.contains('warning') || 
            responseLower.contains('flood') ||
            responseLower.contains('unsafe') ||
            responseLower.contains('caution')) {
          await _speak(_geminiResponse);
        }
      }
      
    } catch (e) {
      debugPrint('Live analysis error: $e');
      if (mounted && _isLiveMonitoring) {
        setState(() {
          _isAnalyzing = false;
          _statusMessage = '🔴 Monitoring active...';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('AI Live Assistant'),
        backgroundColor: Colors.deepPurple,
        foregroundColor: Colors.white,
        actions: [
          // TTS toggle
          IconButton(
            icon: Icon(_ttsEnabled ? Icons.volume_up : Icons.volume_off),
            onPressed: () {
              setState(() {
                _ttsEnabled = !_ttsEnabled;
                if (!_ttsEnabled) {
                  _stopSpeaking();
                }
              });
            },
            tooltip: _ttsEnabled ? 'Mute AI voice' : 'Unmute AI voice',
          ),
          // Status indicator
          if (_isCameraInitialized)
            Container(
              margin: const EdgeInsets.only(right: 16),
              child: Row(
                children: [
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: Colors.green,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    'LIVE',
                    style: TextStyle(
                      color: Colors.green,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
      body: Column(
        children: [
          // Camera/Image preview
          _buildCameraPreview(),
          
          // Status
          _buildStatusCard(),
          
          // Response area
          Expanded(
            child: _buildResponseArea(),
          ),
          
          // Control buttons
          _buildControlButtons(),
        ],
      ),
    );
  }

  Widget _buildCameraPreview() {
    return Container(
      height: 220,
      width: double.infinity,
      margin: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.grey.shade900,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: _isCameraInitialized || _capturedImageBytes != null 
              ? Colors.green 
              : Colors.grey.shade700,
          width: 2,
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: _isCameraStarting
            ? const Center(child: CircularProgressIndicator(color: Colors.white))
            : _isCameraInitialized
                ? _buildLiveCameraPreview()
                : _capturedImageBytes != null
                    ? _buildCapturedImagePreview()
                    : _buildInactivePreview(),
      ),
    );
  }

  Widget _buildLiveCameraPreview() {
    return Stack(
      fit: StackFit.expand,
      children: [
        Center(
          child: AspectRatio(
            aspectRatio: _cameraController!.value.aspectRatio,
            child: CameraPreview(_cameraController!),
          ),
        ),
        // Analysis indicator
        if (_isAnalyzing)
          Positioned(
            top: 8,
            right: 8,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.orange,
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 12,
                    height: 12,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  ),
                  SizedBox(width: 4),
                  Text(
                    'Analyzing',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          ),
        // Speaking indicator
        if (_isSpeaking)
          Positioned(
            top: 8,
            left: 8,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.blue,
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.volume_up, color: Colors.white, size: 14),
                  SizedBox(width: 4),
                  Text(
                    'Speaking',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildCapturedImagePreview() {
    return Stack(
      fit: StackFit.expand,
      children: [
        Image.memory(
          _capturedImageBytes!,
          fit: BoxFit.cover,
        ),
        if (_isAnalyzing)
          Container(
            color: Colors.black54,
            child: const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(color: Colors.white),
                  SizedBox(height: 8),
                  Text(
                    'Analyzing image...',
                    style: TextStyle(color: Colors.white),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildInactivePreview() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.videocam_off,
            size: 48,
            color: Colors.grey.shade600,
          ),
          const SizedBox(height: 8),
          Text(
            _isInitialized ? 'Camera not active' : 'Initializing AI...',
            style: TextStyle(color: Colors.grey.shade500),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusCard() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _isListening ? Colors.blue.shade100 : Colors.deepPurple.shade100,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(
            _isListening ? Icons.mic : (_isAnalyzing ? Icons.hourglass_empty : Icons.info_outline),
            color: _isListening ? Colors.blue : Colors.deepPurple,
            size: 20,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _statusMessage,
              style: TextStyle(
                color: _isListening ? Colors.blue.shade800 : Colors.deepPurple.shade800,
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildResponseArea() {
    return Container(
      margin: const EdgeInsets.all(8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.deepPurple,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  _isSpeaking ? Icons.volume_up : Icons.psychology,
                  color: Colors.white,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Text(
                _isSpeaking ? 'Alert.AI is speaking...' : 'Alert.AI Says:',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.deepPurple,
                ),
              ),
            ],
          ),
          
          const SizedBox(height: 16),
          
          // Response content
          Expanded(
            child: _geminiResponse.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.visibility,
                          size: 48,
                          color: Colors.grey.shade400,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Take a photo or start camera\nand tap mic to speak',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.grey.shade600,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  )
                : SingleChildScrollView(
                    child: Text(
                      _geminiResponse,
                      style: const TextStyle(
                        fontSize: 16,
                        color: Colors.black87,
                        height: 1.5,
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildControlButtons() {
    return Container(
      padding: const EdgeInsets.all(12),
      color: Colors.white,
      child: SafeArea(
        child: Column(
          children: [
            // Row 1: Speak (toggle) + Auto Analyze (instant)
            Row(
              children: [
                // Speak button - toggle, stays active until tapped again
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: ElevatedButton.icon(
                      onPressed: _isListening ? _stopListening : _startListening,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _isListening ? Colors.red : Colors.blue,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      icon: Icon(_isListening ? Icons.mic : Icons.mic_none),
                      label: Text(_isListening ? 'Listening...' : 'Speak'),
                    ),
                  ),
                ),
                
                // Auto Analyze button - instant capture + AI answer
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: ElevatedButton.icon(
                      onPressed: !_isAnalyzing ? _captureAndAnalyze : null,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.deepPurple,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      icon: Icon(_isAnalyzing ? Icons.hourglass_top : Icons.auto_awesome),
                      label: Text(_isAnalyzing ? 'Analyzing...' : 'Auto Analyze'),
                    ),
                  ),
                ),
              ],
            ),
            
            const SizedBox(height: 8),
            
            // Row 2: Camera toggle + Live Monitor
            Row(
              children: [
                // Camera toggle button
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: ElevatedButton.icon(
                      onPressed: _isCameraStarting
                          ? null
                          : (_isCameraInitialized ? _stopCamera : _startCamera),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _isCameraInitialized ? Colors.red.shade700 : Colors.green,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      icon: Icon(_isCameraInitialized ? Icons.videocam_off : Icons.videocam),
                      label: Text(_isCameraInitialized ? 'Stop Camera' : 'Start Camera'),
                    ),
                  ),
                ),
                
                // LIVE MONITOR button - The main feature for continuous AI vision
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: ElevatedButton.icon(
                      onPressed: (_isCameraInitialized && !_isAnalyzing)
                          ? (_isLiveMonitoring ? _stopLiveMonitoring : _startLiveMonitoring)
                          : null,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _isLiveMonitoring ? Colors.orange : Colors.teal,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      icon: Icon(_isLiveMonitoring ? Icons.stop_circle : Icons.visibility),
                      label: Text(_isLiveMonitoring ? 'Stop Monitor' : 'Live Monitor'),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
