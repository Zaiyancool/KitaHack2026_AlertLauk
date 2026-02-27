import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:camera/camera.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:flutter_tts/flutter_tts.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:google_generative_ai/google_generative_ai.dart';

/// AI Live Assistant - Working Implementation
/// 
/// Uses:
/// - google_generative_ai package (like working gemini_service.dart)
/// - speech_to_text for voice input (from pubspec.yaml)
/// - flutter_tts for voice output (from pubspec.yaml)
/// - Properly loads API key from .env file
class AILiveAssistantRealtime extends StatefulWidget {
  const AILiveAssistantRealtime({super.key});

  @override
  State<AILiveAssistantRealtime> createState() =>
      _AILiveAssistantRealtimeState();
}

class _AILiveAssistantRealtimeState extends State<AILiveAssistantRealtime>
    with TickerProviderStateMixin {
  // ─────────────────────────────────────────────
  // Gemini AI Model
  // ─────────────────────────────────────────────
  GenerativeModel? _model;
  bool _isInitialized = false;
  String? _errorMessage;
  
  // For streaming responses
  bool _isStreaming = false;

  // ─────────────────────────────────────────────
  // Speech to Text (Voice Input)
  // ─────────────────────────────────────────────
  stt.SpeechToText? _speechToText;
  bool _speechEnabled = false;
  bool _isListening = false;
  String _lastWords = '';

  // ─────────────────────────────────────────────
  // Text to Speech (Voice Output)
  // ─────────────────────────────────────────────
  FlutterTts? _flutterTts;
  bool _isSpeaking = false;
  bool _ttsEnabled = true;

  // ─────────────────────────────────────────────
  // Camera
  // ─────────────────────────────────────────────
  CameraController? _cameraController;
  List<CameraDescription>? _cameras;
  bool _isCameraInitialized = false;
  bool _isCameraStarting = false;
  bool _isCameraOn = false;
  String? _cameraError;
  Timer? _cameraFrameTimer;
  
  // For camera analysis
  String _cameraAnalysis = '';
  bool _isAnalyzing = false;
  
  // Real-time analysis mode
  bool _liveAnalysisMode = false;
  String _lastAnalyzedFrame = '';

  // ─────────────────────────────────────────────
  // Chat UI
  // ─────────────────────────────────────────────
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final List<Map<String, dynamic>> _messages = [];

  // ─────────────────────────────────────────────
  // Animations
  // ─────────────────────────────────────────────
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  // ═══════════════════════════════════════════════
  //  LIFECYCLE
  // ═══════════════════════════════════════════════

  @override
  void initState() {
    super.initState();
    _setupAnimations();
    _initializeServices();
  }

  @override
  void dispose() {
    _cameraFrameTimer?.cancel();
    _pulseController.dispose();
    _cameraController?.dispose();
    _messageController.dispose();
    _scrollController.dispose();
    _stopListening();
    _stopSpeaking();
    _speechToText?.cancel();
    _flutterTts?.stop();
    super.dispose();
  }

  // ═══════════════════════════════════════════════
  //  ANIMATIONS
  // ═══════════════════════════════════════════════

  void _setupAnimations() {
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.3).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  // ═══════════════════════════════════════════════
  //  INITIALIZATION
  // ═══════════════════════════════════════════════

  Future<void> _initializeServices() async {
    try {
      // Load API key from .env
      await dotenv.load(fileName: '.env');
      final apiKey = dotenv.env['GEMINI_API_KEY'];
      
      if (apiKey == null || apiKey.isEmpty) {
        setState(() {
          _errorMessage = 'GEMINI_API_KEY not found in .env file';
        });
        return;
      }
      
      // Initialize Gemini model (like the working gemini_service.dart)
      _model = GenerativeModel(
        model: 'gemini-2.5-flash',
        apiKey: apiKey,
        generationConfig: GenerationConfig(
          temperature: 0.7,
          maxOutputTokens: 1024,
        ),
      );
      
      // Initialize Speech to Text
      _speechToText = stt.SpeechToText();
      final speechAvailable = await _speechToText!.initialize(
        onError: (error) {
          debugPrint('Speech error: $error');
          setState(() => _isListening = false);
        },
        onStatus: (status) {
          debugPrint('Speech status: $status');
          if (status == 'done' || status == 'notListening') {
            setState(() => _isListening = false);
          }
        },
      );
      _speechEnabled = speechAvailable;
      
      // Initialize Text to Speech
      _flutterTts = FlutterTts();
      await _flutterTts!.setLanguage('en-US');
      await _flutterTts!.setSpeechRate(0.5);
      await _flutterTts!.setVolume(1.0);
      await _flutterTts!.setPitch(1.0);
      
      _flutterTts!.setStartHandler(() {
        if (mounted) setState(() => _isSpeaking = true);
      });
      
      _flutterTts!.setCompletionHandler(() {
        if (mounted) setState(() => _isSpeaking = false);
      });
      
      _flutterTts!.setErrorHandler((error) {
        debugPrint('TTS error: $error');
        if (mounted) setState(() => _isSpeaking = false);
      });

      setState(() => _isInitialized = true);

      _addBotMessage(
        'Hello! I am Alert.AI, your AI Safety Assistant.\n\n'
        '🎤 Tap MIC to speak with me.\n'
        '📹 Turn on CAMERA for visual analysis.\n'
        '💬 Or type your question below.\n\n'
        'I will respond with voice!',
      );
    } catch (e) {
      debugPrint('Initialization error: $e');
      setState(() {
        _errorMessage = 'Failed to initialize: $e';
      });
    }
  }

  // ═══════════════════════════════════════════════
  //  VOICE INPUT (Speech to Text)
  // ═══════════════════════════════════════════════

  Future<void> _startListening() async {
    if (!_speechEnabled) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Speech recognition not available')),
      );
      return;
    }

    // Request microphone permission
    var status = await Permission.microphone.request();
    if (!status.isGranted) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Microphone permission denied')),
        );
      }
      return;
    }

    _lastWords = '';
    setState(() => _isListening = true);

    await _speechToText!.listen(
      onResult: (result) {
        setState(() {
          _lastWords = result.recognizedWords;
        });
        
        // When speech is done (final result)
        if (result.finalResult) {
          _stopListening();
          if (_lastWords.isNotEmpty) {
            _sendMessage(_lastWords);
          }
        }
      },
      listenFor: const Duration(seconds: 30),
      pauseFor: const Duration(seconds: 5),
      localeId: 'en_US', // Can be changed to 'ms_MY' for Malay
      partialResults: true,
      cancelOnError: true,
    );
  }

  Future<void> _stopListening() async {
    await _speechToText?.stop();
    if (mounted) {
      setState(() => _isListening = false);
    }
  }

  void _toggleListening() {
    if (_isListening) {
      _stopListening();
    } else {
      _startListening();
    }
  }

  // ═══════════════════════════════════════════════
  //  VOICE OUTPUT (Text to Speech)
  // ═══════════════════════════════════════════════

  Future<void> _speak(String text) async {
    if (!_ttsEnabled || _flutterTts == null) return;
    
    // Stop any current speech
    await _flutterTts!.stop();
    
    // Clean text for TTS (remove emojis and special chars that TTS can't handle)
    String cleanText = text
        .replaceAll(RegExp(r'[^\x00-\x7F]+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    
    if (cleanText.isNotEmpty) {
      await _flutterTts!.speak(cleanText);
    }
  }

  Future<void> _stopSpeaking() async {
    await _flutterTts?.stop();
    if (mounted) {
      setState(() => _isSpeaking = false);
    }
  }

  // ═══════════════════════════════════════════════
  //  CAMERA
  // ═══════════════════════════════════════════════

  Future<void> _startCamera() async {
    if (_isCameraOn) return;

    setState(() {
      _isCameraStarting = true;
      _cameraError = null;
    });

    try {
      var status = await Permission.camera.request();
      if (!status.isGranted) {
        setState(() {
          _cameraError = 'Camera permission denied.';
          _isCameraStarting = false;
        });
        return;
      }

      _cameras = await availableCameras();
      if (_cameras == null || _cameras!.isEmpty) {
        setState(() {
          _cameraError = 'No camera found.';
          _isCameraStarting = false;
        });
        return;
      }

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

      // Start REAL-TIME analysis every 2 seconds
      _cameraFrameTimer = Timer.periodic(
        const Duration(seconds: 2),
        (_) => _analyzeCameraFrame(),
      );

      setState(() {
        _isCameraInitialized = true;
        _isCameraOn = true;
        _isCameraStarting = false;
      });
      
      // Do initial analysis immediately
      _analyzeCameraFrame();
    } catch (e) {
      setState(() {
        _cameraError = 'Camera error: $e';
        _isCameraStarting = false;
        _isCameraOn = false;
      });
    }
  }

  Future<void> _analyzeCameraFrame() async {
    if (!_isCameraOn || _cameraController == null || !_isCameraInitialized) return;
    if (!_cameraController!.value.isInitialized) return;
    if (_model == null) return;

    try {
      if (mounted) setState(() => _isAnalyzing = true);

      final XFile imageFile = await _cameraController!.takePicture();
      final Uint8List jpegBytes = await imageFile.readAsBytes();

      // Send to Gemini for analysis
      final imagePart = DataPart('image/jpeg', jpegBytes);
      final textPart = TextPart(
        'You are "Alert.AI". If everything looks safe, say so in 1 sentence. If there is danger, explain what you see and what to do in 2-3 sentences. Always finish your thought. No markdown.',
      );

      final content = [
        Content.multi([textPart, imagePart])
      ];

      final response = await _model!.generateContent(content);
      final analysis = response.text ?? '';

      if (mounted && analysis.isNotEmpty) {
        setState(() => _cameraAnalysis = analysis);
      }

      if (mounted) setState(() => _isAnalyzing = false);
    } catch (e) {
      debugPrint('Frame analysis error: $e');
      if (mounted) setState(() => _isAnalyzing = false);
    }
  }

  Future<void> _stopCamera() async {
    if (!_isCameraOn) return;

    try {
      _cameraFrameTimer?.cancel();
      _cameraFrameTimer = null;
      await _cameraController?.dispose();
      _cameraController = null;

      setState(() {
        _isCameraInitialized = false;
        _isCameraOn = false;
        _cameraAnalysis = '';
      });
    } catch (e) {
      debugPrint('Error stopping camera: $e');
    }
  }

  // ═══════════════════════════════════════════════
  //  MESSAGE SENDING
  // ═══════════════════════════════════════════════

  Future<void> _sendMessage([String? voiceText]) async {
    final text = voiceText ?? _messageController.text.trim();
    if (text.isEmpty || !_isInitialized) return;

    if (voiceText == null) _messageController.clear();

    _addUserMessage(text);

    // Stop any ongoing speech when user sends message
    await _stopSpeaking();
    if (_isListening) await _stopListening();

    try {
      setState(() => _isStreaming = true);

      // Include camera analysis context if available
      String context = text;
      if (_cameraAnalysis.isNotEmpty) {
        context = '$text\n\n[Camera shows: $_cameraAnalysis]';
      }

      final content = Content.text(
        'You are "Alert.AI", a campus safety assistant. Talk naturally like a real person.\nFor casual questions, reply in 1-2 sentences. For urgent/dangerous situations, give essential safety steps in 3-5 sentences. Always complete your thought. No bullet points or markdown.\n\nUser: $context',
      );
      final response = await _model!.generateContent([content]);
      
      final aiResponse = response.text ?? 'Sorry, I could not generate a response.';
      
      // Add response to chat
      _addBotMessage(aiResponse);
      
      // Speak the response if TTS is enabled
      if (_ttsEnabled) {
        _speak(aiResponse);
      }
      
      setState(() => _isStreaming = false);
    } catch (e) {
      _addBotMessage('Error: $e');
      setState(() => _isStreaming = false);
    }
  }

  // ═══════════════════════════════════════════════
  //  CHAT HELPERS
  // ═══════════════════════════════════════════════

  void _addUserMessage(String text) {
    setState(() {
      _messages.add({
        'from': 'user',
        'text': text,
        'timestamp': DateTime.now(),
      });
    });
    _scrollToBottom();
  }

  void _addBotMessage(String text) {
    setState(() {
      _messages.add({
        'from': 'bot',
        'text': text,
        'timestamp': DateTime.now(),
      });
    });
    _scrollToBottom();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  String _formatTime(DateTime time) {
    return '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
  }

  // ═══════════════════════════════════════════════
  //  BUILD
  // ═══════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('Alert.AI - Live Assistant'),
        backgroundColor: Colors.deepPurple,
        foregroundColor: Colors.white,
        actions: [
          // TTS toggle
          IconButton(
            icon: Icon(_ttsEnabled ? Icons.volume_up : Icons.volume_off),
            onPressed: () {
              setState(() {
                _ttsEnabled = !_ttsEnabled;
                if (!_ttsEnabled) _stopSpeaking();
              });
            },
            tooltip: _ttsEnabled ? 'Mute AI voice' : 'Unmute AI voice',
          ),
          // Camera toggle
          IconButton(
            icon: Icon(
              _isCameraOn ? Icons.videocam : Icons.videocam_off,
              color: _isCameraOn ? Colors.green : Colors.white,
            ),
            onPressed: _isCameraOn ? _stopCamera : _startCamera,
            tooltip: _isCameraOn ? 'Stop Camera' : 'Start Camera',
          ),
          // Status indicator
          if (_isInitialized)
            Container(
              margin: const EdgeInsets.only(right: 16),
              child: Row(
                children: [
                  Container(
                    width: 10,
                    height: 10,
                    decoration: const BoxDecoration(
                      color: Colors.green,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 4),
                  const Text(
                    'READY',
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
          // Error message
          if (_errorMessage != null || _cameraError != null)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(8),
              color: Colors.red.shade800,
              child: Text(
                _errorMessage ?? _cameraError ?? '',
                style: const TextStyle(color: Colors.white),
                textAlign: TextAlign.center,
              ),
            ),

          // LIVE Camera Preview
          _buildCameraSection(),

          // Voice Status Indicator
          _buildVoiceStatusIndicator(),

          // Chat messages
          Expanded(child: _buildChatSection()),

          // Input section
          _buildInputSection(),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════
  //  UI WIDGETS
  // ═══════════════════════════════════════════════

  Widget _buildCameraSection() {
    return Container(
      height: 180,
      width: double.infinity,
      margin: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.grey.shade900,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: _isCameraOn ? Colors.green : Colors.grey.shade700,
          width: 2,
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: _isCameraStarting
            ? const Center(child: CircularProgressIndicator())
            : _isCameraOn && _isCameraInitialized && _cameraController != null
                ? Stack(
                    fit: StackFit.expand,
                    children: [
                      AspectRatio(
                        aspectRatio: _cameraController!.value.aspectRatio,
                        child: CameraPreview(_cameraController!),
                      ),
                      // LIVE indicator
                      Positioned(
                        top: 8,
                        left: 8,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.red,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.videocam,
                                  color: Colors.white, size: 14),
                              SizedBox(width: 4),
                              Text(
                                'LIVE',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      // Analyzing indicator
                      if (_isAnalyzing)
                        Positioned(
                          top: 8,
                          right: 8,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 4),
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
                      // Camera analysis text
                      if (_cameraAnalysis.isNotEmpty && !_isAnalyzing)
                        Positioned(
                          bottom: 8,
                          left: 8,
                          right: 8,
                          child: Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: Colors.black54,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              _cameraAnalysis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                    ],
                  )
                : Center(
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
                          'Camera is OFF',
                          style: TextStyle(
                            color: Colors.grey.shade500,
                            fontSize: 16,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Tap 📹 in the app bar to start',
                          style: TextStyle(
                            color: Colors.grey.shade600,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
      ),
    );
  }

  Widget _buildVoiceStatusIndicator() {
    if (!_isListening && !_isSpeaking && !_isStreaming) {
      return const SizedBox.shrink();
    }

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: _isListening
            ? Colors.blue.shade900
            : (_isSpeaking
                ? Colors.purple.shade900
                : Colors.grey.shade800),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          if (_isListening)
            AnimatedBuilder(
              animation: _pulseAnimation,
              builder: (context, child) {
                return Transform.scale(
                  scale: _pulseAnimation.value,
                  child: const Icon(Icons.mic, color: Colors.red, size: 20),
                );
              },
            )
          else if (_isSpeaking)
            AnimatedBuilder(
              animation: _pulseAnimation,
              builder: (context, child) {
                return Transform.scale(
                  scale: _pulseAnimation.value,
                  child: const Icon(Icons.volume_up,
                      color: Colors.green, size: 20),
                );
              },
            )
          else
            const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                  strokeWidth: 2, color: Colors.orange),
            ),

          const SizedBox(width: 8),

          Expanded(
            child: Text(
              _isListening
                  ? (_lastWords.isNotEmpty
                      ? 'Listening: "$_lastWords"'
                      : 'Listening...')
                  : (_isSpeaking
                      ? 'AI is speaking...'
                      : 'Processing...'),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChatSection() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: _messages.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.support_agent,
                    size: 48,
                    color: Colors.deepPurple.shade200,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Start a conversation!',
                    style: TextStyle(
                      color: Colors.grey.shade600,
                      fontSize: 16,
                    ),
                  ),
                ],
              ),
            )
          : ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.all(12),
              itemCount: _messages.length,
              itemBuilder: (context, index) {
                final msg = _messages[index];
                final isUser = msg['from'] == 'user';
                return _buildMessageBubble(msg, isUser);
              },
            ),
    );
  }

  Widget _buildMessageBubble(Map<String, dynamic> msg, bool isUser) {
    final timestamp = msg['timestamp'] as DateTime?;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment:
            isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!isUser) ...[
            CircleAvatar(
              radius: 14,
              backgroundColor: Colors.deepPurple.shade100,
              child: Icon(
                _isSpeaking ? Icons.volume_up : Icons.support_agent,
                size: 16,
                color: Colors.deepPurple.shade700,
              ),
            ),
            const SizedBox(width: 6),
          ],
          Flexible(
            child: Container(
              padding: const EdgeInsets.all(12),
              constraints: BoxConstraints(
                maxWidth: MediaQuery.of(context).size.width * 0.75,
              ),
              decoration: BoxDecoration(
                color: isUser ? Colors.deepPurple : Colors.white,
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(16),
                  topRight: const Radius.circular(16),
                  bottomLeft: Radius.circular(isUser ? 16 : 4),
                  bottomRight: Radius.circular(isUser ? 4 : 16),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    msg['text'] ?? '',
                    style: TextStyle(
                      color: isUser ? Colors.white : Colors.black87,
                      fontSize: 14,
                    ),
                  ),
                  if (timestamp != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      _formatTime(timestamp),
                      style: TextStyle(
                        color:
                            isUser ? Colors.white60 : Colors.grey.shade500,
                        fontSize: 10,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          if (isUser) ...[
            const SizedBox(width: 6),
            CircleAvatar(
              radius: 14,
              backgroundColor: Colors.deepPurple.shade400,
              child: const Icon(
                Icons.person,
                size: 16,
                color: Colors.white,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildInputSection() {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.grey.shade300,
            blurRadius: 4,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        child: Row(
          children: [
            // Voice / Mic button with pulse animation
            _buildVoiceButton(),

            const SizedBox(width: 8),

            // Text input
            Expanded(
              child: TextField(
                controller: _messageController,
                enabled: _isInitialized && !_isStreaming && !_isListening,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => _sendMessage(),
                decoration: InputDecoration(
                  hintText: 'Ask AI about your situation...',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide: BorderSide(color: Colors.grey.shade300),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide: BorderSide(color: Colors.grey.shade300),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide:
                        const BorderSide(color: Colors.deepPurple, width: 2),
                  ),
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  filled: true,
                  fillColor: Colors.grey.shade50,
                ),
              ),
            ),

            const SizedBox(width: 8),

            // Send button
            Container(
              decoration: BoxDecoration(
                color: (_isInitialized && !_isStreaming && !_isListening)
                    ? Colors.deepPurple
                    : Colors.grey.shade300,
                shape: BoxShape.circle,
              ),
              child: IconButton(
                icon: Icon(
                  _isStreaming ? Icons.hourglass_empty : Icons.send,
                  color: Colors.white,
                ),
                onPressed: (_isInitialized && !_isStreaming && !_isListening)
                    ? () => _sendMessage()
                    : null,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildVoiceButton() {
    return AnimatedBuilder(
      animation: _pulseAnimation,
      builder: (context, child) {
        return Transform.scale(
          scale: _isListening ? _pulseAnimation.value : 1.0,
          child: ElevatedButton(
            onPressed: _isInitialized ? _toggleListening : null,
            style: ElevatedButton.styleFrom(
              backgroundColor: _isListening ? Colors.red : Colors.blue,
              shape: const CircleBorder(),
              padding: const EdgeInsets.all(12),
            ),
            child: Icon(
              _isListening ? Icons.mic : Icons.mic_none,
              color: Colors.white,
              size: 24,
            ),
          ),
        );
      },
    );
  }
}
