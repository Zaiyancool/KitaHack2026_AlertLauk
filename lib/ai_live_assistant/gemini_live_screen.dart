import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:camera/camera.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:flutter_tts/flutter_tts.dart';

/// GeminiLiveScreen - Fixed version with manual voice control and longer responses
class GeminiLiveScreen extends StatefulWidget {
  const GeminiLiveScreen({super.key});

  @override
  State<GeminiLiveScreen> createState() => _GeminiLiveScreenState();
}

class _GeminiLiveScreenState extends State<GeminiLiveScreen> {
  // Camera
  CameraController? _cameraController;
  List<CameraDescription>? _cameras;
  bool _isCameraInitialized = false;

  // AI Model
  GenerativeModel? _model;
  bool _isInitialized = false;
  String? _apiKey;

  // Voice Input (Speech-to-Text)
  stt.SpeechToText? _speech;
  bool _speechInitialized = false;
  bool _isListening = false;
  String _lastWords = '';
  bool _speechHasResult = false;

  // Text-to-Speech
  FlutterTts? _tts;
  bool _isSpeaking = false;
  bool _ttsEnabled = true;

  // State
  String _statusMessage = 'Initializing...';
  String _aiResponse = '';
  bool _isProcessing = false;

  @override
  void initState() {
    super.initState();
    _initializeAll();
  }

  Future<void> _initializeAll() async {
    await _initializeAI();
    await _initializeCamera();
    await _initializeSpeech();
    await _initializeTTS();
  }

  Future<void> _initializeAI() async {
    try {
      await dotenv.load(fileName: '.env');
      _apiKey = dotenv.env['GEMINI_API_KEY'];
      
      if (_apiKey == null || _apiKey!.isEmpty) {
        setState(() => _statusMessage = 'Error: GEMINI_API_KEY not found');
        return;
      }
      
      _model = GenerativeModel(
        model: 'gemini-2.5-flash',
        apiKey: _apiKey!,
        generationConfig: GenerationConfig(
          temperature: 0.7,
          maxOutputTokens: 2048, // Increased for longer responses
        ),
      );
      
      setState(() {
        _isInitialized = true;
        _statusMessage = 'Ready! Tap mic to speak';
      });
    } catch (e) {
      setState(() => _statusMessage = 'AI init error: $e');
    }
  }

  Future<void> _initializeCamera() async {
    try {
      var cameraStatus = await Permission.camera.request();
      if (!cameraStatus.isGranted) return;
      
      _cameras = await availableCameras();
      if (_cameras == null || _cameras!.isEmpty) return;
      
      final frontCamera = _cameras!.firstWhere(
        (camera) => camera.lensDirection == CameraLensDirection.front,
        orElse: () => _cameras!.first,
      );
      
      _cameraController = CameraController(
        frontCamera,
        ResolutionPreset.medium,
        enableAudio: false,
      );
      
      await _cameraController!.initialize();
      
      if (mounted) setState(() => _isCameraInitialized = true);
    } catch (e) {
      debugPrint('Camera error: $e');
    }
  }

  Future<void> _initializeSpeech() async {
    try {
      _speech = stt.SpeechToText();
      final available = await _speech!.initialize(
        onError: (error) {
          debugPrint('Speech error: ${error.errorMsg}');
          if (mounted) {
            setState(() {
              _isListening = false;
              _statusMessage = 'Speech error - tap mic to try again';
            });
          }
        },
        onStatus: (status) {
          debugPrint('Speech status: $status');
        },
      );

      if (mounted) setState(() => _speechInitialized = available);
    } catch (e) {
      debugPrint('Speech init error: $e');
    }
  }

  Future<void> _initializeTTS() async {
    try {
      _tts = FlutterTts();
      
      await _tts!.setLanguage("en-US");
      await _tts!.setSpeechRate(0.5);
      await _tts!.setVolume(1.0);
      await _tts!.setPitch(0.9);
      
      _tts!.setStartHandler(() {
        if (mounted) setState(() => _isSpeaking = true);
      });
      
      _tts!.setCompletionHandler(() {
        if (mounted) setState(() => _isSpeaking = false);
      });
      
      _tts!.setErrorHandler((msg) {
        debugPrint('TTS Error: $msg');
        if (mounted) setState(() => _isSpeaking = false);
      });
    } catch (e) {
      debugPrint('TTS init error: $e');
      if (mounted) setState(() => _ttsEnabled = false);
    }
  }

  Future<void> _toggleListening() async {
    if (_isProcessing || _isSpeaking) {
      _statusMessage = 'Please wait...';
      return;
    }
    
    if (_isListening) {
      await _stopListening();
    } else {
      await _startListening();
    }
  }

  Future<void> _startListening() async {
    if (!_speechInitialized || _speech == null) {
      setState(() => _statusMessage = 'Speech not available');
      return;
    }
    
    setState(() {
      _isListening = true;
      _statusMessage = 'Listening...';
      _lastWords = '';
      _speechHasResult = false;
    });

    try {
      await _speech!.listen(
        onResult: (result) {
          if (!mounted) return;
          
          setState(() {
            _lastWords = result.recognizedWords;
          });
          
          if (result.finalResult && _lastWords.isNotEmpty) {
            _speechHasResult = true;
            _statusMessage = 'Heard: $_lastWords';
            _handleUserInput(_lastWords);
          }
        },
        listenFor: const Duration(seconds: 30),
        pauseFor: const Duration(seconds: 5),
        partialResults: false,
      );
    } catch (e) {
      debugPrint('Listen error: $e');
      if (mounted) {
        setState(() {
          _isListening = false;
          _statusMessage = 'Error - tap mic to try again';
        });
      }
    }
  }

  Future<void> _stopListening() async {
    try {
      await _speech?.stop();
    } catch (e) {
      debugPrint('Stop error: $e');
    }
    if (mounted) {
      setState(() {
        _isListening = false;
        if (!_speechHasResult) {
          _statusMessage = 'Tap mic to speak';
        }
      });
    }
  }

  Future<void> _handleUserInput(String input) async {
    if (input.isEmpty || _isProcessing) return;
    
    await _stopListening();
    
    setState(() {
      _isProcessing = true;
      _statusMessage = 'Looking at what you\'re showing me...';
      _aiResponse = '';
    });
    
    try {
      // Check if camera is initialized - if so, capture the current frame
      Uint8List? imageBytes;
      if (_isCameraInitialized && _cameraController != null) {
        try {
          final XFile image = await _cameraController!.takePicture();
          imageBytes = await image.readAsBytes();
          _statusMessage = 'Analyzing what I see...';
        } catch (e) {
          debugPrint('Could not capture image: $e');
        }
      }
      
      String text;
      
      if (imageBytes != null) {
        // User is showing something to the camera - analyze it!
        final prompt = '''You are "Alert.AI", an AI that can see through the camera. 
        
The user asked: "$input"

Look carefully at the image and answer their question about what they are showing you. 
Be specific and descriptive about what you see in the image.
If you're not sure, say so honestly.''';

        final imagePart = DataPart('image/jpeg', imageBytes);
        final textPart = TextPart(prompt);
        
        final content = [Content.multi([textPart, imagePart])];
        final response = await _model!.generateContent(content);
        
        text = response.text ?? 'I\'m looking at the image but couldn\'t find an answer.';
      } else {
        // No camera - just text conversation
        final systemPrompt = '''You are "Alert.AI", a friendly AI safety assistant. 
The user is asking: "$input"
Provide a helpful response about campus safety or answer their question.
Be specific and helpful.''';

        final content = [Content.text(systemPrompt)];
        final response = await _model!.generateContent(content);
        
        text = response.text ?? 'Sorry, I could not understand.';
      }
      
      if (mounted) {
        setState(() {
          _aiResponse = text;
          _statusMessage = 'AI responded - tap mic for more';
        });
        
        if (_ttsEnabled && _tts != null) {
          await _speak(text);
        }
      }
      
    } catch (e) {
      debugPrint('AI error: $e');
      if (mounted) {
        setState(() {
          _statusMessage = 'Error: ${e.toString()}';
          _aiResponse = 'Sorry, I encountered an error. Please try again.';
        });
      }
    } finally {
      if (mounted) {
        setState(() => _isProcessing = false);
      }
    }
  }

  Future<void> _speak(String text) async {
    if (!_ttsEnabled || _tts == null) return;
    
    try {
      await _tts!.stop();
      await _tts!.speak(text);
    } catch (e) {
      debugPrint('TTS error: $e');
    }
  }

  Future<void> _stopSpeaking() async {
    try {
      await _tts?.stop();
    } catch (e) {
      debugPrint('Stop speaking error: $e');
    }
    if (mounted) setState(() => _isSpeaking = false);
  }

  @override
  void dispose() {
    _cameraController?.dispose();
    _speech?.cancel();
    _tts?.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('Alert.AI - Live Assistant'),
        backgroundColor: Colors.deepPurple,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: Icon(_ttsEnabled ? Icons.volume_up : Icons.volume_off),
            onPressed: () {
              setState(() {
                _ttsEnabled = !_ttsEnabled;
                if (!_ttsEnabled) _stopSpeaking();
              });
            },
          ),
        ],
      ),
      body: Column(
        children: [
          _buildCameraPreview(),
          _buildStatusBar(),
          Expanded(child: _buildResponseArea()),
          _buildControls(),
        ],
      ),
    );
  }

  Widget _buildCameraPreview() {
    return Container(
      height: 260,
      margin: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.grey.shade900,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.deepPurple, width: 3),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(13),
        child: _isCameraInitialized && _cameraController != null
            ? Stack(
                fit: StackFit.expand,
                children: [
                  Center(
                    child: AspectRatio(
                      aspectRatio: _cameraController!.value.aspectRatio,
                      child: Transform.scale(
                        scaleX: -1,
                        child: CameraPreview(_cameraController!),
                      ),
                    ),
                  ),
                  Positioned(
                    top: 8,
                    left: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.black54,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.visibility, color: Colors.green, size: 14),
                          const SizedBox(width: 4),
                          Text('AI sees you', style: TextStyle(color: Colors.white, fontSize: 11)),
                        ],
                      ),
                    ),
                  ),
                ],
              )
            : Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.videocam, size: 40, color: Colors.grey.shade600),
                    const SizedBox(height: 8),
                    Text(_isInitialized ? 'Starting camera...' : 'Initializing AI...', 
                        style: TextStyle(color: Colors.grey.shade500)),
                  ],
                ),
              ),
      ),
    );
  }

  Widget _buildStatusBar() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _isListening ? Colors.blue.shade100 : Colors.deepPurple.shade100,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(_isListening ? Icons.mic : Icons.info_outline, 
              color: _isListening ? Colors.blue : Colors.deepPurple, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(_statusMessage, 
                style: TextStyle(color: _isListening ? Colors.blue.shade800 : Colors.deepPurple.shade800, fontSize: 13)),
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
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.deepPurple,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(_isSpeaking ? Icons.volume_up : Icons.psychology, 
                    color: Colors.white, size: 20),
              ),
              const SizedBox(width: 12),
              Text(
                _isSpeaking ? 'Alert.AI is speaking...' : 'Alert.AI Says:',
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.deepPurple),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Expanded(
            child: _aiResponse.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.record_voice_over, size: 48, color: Colors.grey.shade400),
                        const SizedBox(height: 8),
                        Text('Tap the mic and speak\nAI will respond out loud',
                            textAlign: TextAlign.center, style: TextStyle(color: Colors.grey.shade600)),
                      ],
                    ),
                  )
                : SingleChildScrollView(
                    child: Text(_aiResponse, style: const TextStyle(fontSize: 16, height: 1.5)),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildControls() {
    return Container(
      padding: const EdgeInsets.all(16),
      color: Colors.white,
      child: SafeArea(
        child: Column(
          children: [
            GestureDetector(
              onTap: _isInitialized && !_isProcessing
                  ? _toggleListening
                  : null,
              child: Container(
                width: 70,
                height: 70,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _isListening ? Colors.red : (_isProcessing ? Colors.grey : Colors.deepPurple),
                  boxShadow: [
                    BoxShadow(
                      color: (_isListening ? Colors.red : Colors.deepPurple).withOpacity(0.4),
                      blurRadius: 15,
                      spreadRadius: 2,
                    ),
                  ],
                ),
                child: Icon(
                  _isListening ? Icons.stop : Icons.mic,
                  color: Colors.white,
                  size: 32,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _isListening ? 'Tap to stop' : 'Tap to speak',
              style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                IconButton(
                  onPressed: _isSpeaking ? _stopSpeaking : null,
                  icon: Icon(Icons.stop, color: _isSpeaking ? Colors.orange : Colors.grey),
                  tooltip: 'Stop AI',
                ),
                if (_aiResponse.isNotEmpty && !_isSpeaking)
                  IconButton(
                    onPressed: () => _speak(_aiResponse),
                    icon: const Icon(Icons.volume_up, color: Colors.deepPurple),
                    tooltip: 'Repeat',
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
