import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:camera/camera.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:flutter_tts/flutter_tts.dart';
import 'package:permission_handler/permission_handler.dart';

/// AI Live Assistant Screen - Like WhatsApp Video Call
/// - Camera is OFF by default
/// - User manually turns on camera (Start Video button)
/// - Live video streaming with real-time AI analysis
/// - User can ask questions via voice or text while viewing surroundings
class AILiveAssistantScreen extends StatefulWidget {
  const AILiveAssistantScreen({super.key});

  @override
  State<AILiveAssistantScreen> createState() => _AILiveAssistantScreenState();
}

class _AILiveAssistantScreenState extends State<AILiveAssistantScreen>
    with TickerProviderStateMixin {
  
  // Camera - OFF by default
  CameraController? _cameraController;
  List<CameraDescription>? _cameras;
  bool _isCameraInitialized = false;
  bool _isCameraStarting = false;
  bool _isCameraOn = false; // FALSE = camera is OFF by default
  String? _cameraError;

  // AI Service
  GenerativeModel? _model;
  bool _isInitialized = false;
  String? _errorMessage;

  // Live Analysis - Only runs when camera is ON
  bool _isAnalyzing = false;
  bool _isStreaming = false;
  String _currentAnalysis = '';
  Timer? _analysisTimer;
  Uint8List? _lastFrameBytes;

  // Chat/Response
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final List<Map<String, dynamic>> _messages = [];
  String _currentStreamingResponse = '';

  // Voice Input
  stt.SpeechToText? _speech;
  bool _isListening = false;
  bool _speechInitialized = false;

  // Thinking Animation
  late AnimationController _thinkingController;
  late Animation<double> _thinkingAnimation;

  @override
  void initState() {
    super.initState();
    _initializeAI();
    _initSpeech();
    _setupThinkingAnimation();
    // Camera is NOT initialized by default - user must turn it on manually
  }

  void _setupThinkingAnimation() {
    _thinkingController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat();
    
    _thinkingAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _thinkingController, curve: Curves.easeInOut),
    );
  }

  Future<void> _initializeAI() async {
    try {
      await dotenv.load(fileName: '.env');
      final apiKey = dotenv.env['GEMINI_API_KEY'];
      
      if (apiKey == null || apiKey.isEmpty) {
        setState(() {
          _errorMessage = 'GEMINI_API_KEY not configured';
        });
        return;
      }

      _model = GenerativeModel(
        model: 'gemini-2.5-flash',
        apiKey: apiKey,
        generationConfig: GenerationConfig(
          temperature: 0.7,
          maxOutputTokens: 1024,
        ),
      );

      setState(() {
        _isInitialized = true;
      });

      // Welcome message
      _addBotMessage(
        'Hello! I am your AI Safety Assistant.\n\n'
        '📹 Turn on your CAMERA to start a live video call with me.\n'
        '🎤 Use Voice to talk to me.\n'
        '💬 Or type your question.\n\n'
        'I will analyze your surroundings in real-time and give you safety advice!',
      );
    } catch (e) {
      setState(() {
        _errorMessage = 'Failed to initialize AI: $e';
      });
    }
  }

  /// Turn ON camera - Like starting a video call
  Future<void> _startCamera() async {
    if (_isCameraOn) return; // Already on
    
    setState(() {
      _isCameraStarting = true;
      _cameraError = null;
    });

    try {
      // Request camera permission
      var status = await Permission.camera.request();
      if (!status.isGranted) {
        setState(() {
          _cameraError = 'Camera permission denied. Please enable in settings.';
          _isCameraStarting = false;
        });
        return;
      }

      // Get available cameras
      _cameras = await availableCameras();
      if (_cameras == null || _cameras!.isEmpty) {
        setState(() {
          _cameraError = 'No camera found on this device.';
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
      
      // Start image stream for live analysis
      await _cameraController!.startImageStream((CameraImage image) {
        _processFrame(image);
      });

      setState(() {
        _isCameraInitialized = true;
        _isCameraOn = true; // CAMERA IS NOW ON
        _isCameraStarting = false;
      });
    } catch (e) {
      setState(() {
        _cameraError = 'Error: $e';
        _isCameraStarting = false;
        _isCameraOn = false;
      });
    }
  }

  /// Turn OFF camera - Like ending a video call
  Future<void> _stopCamera() async {
    if (!_isCameraOn) return;
    
    try {
      _analysisTimer?.cancel();
      await _cameraController?.stopImageStream();
      await _cameraController?.dispose();
      _cameraController = null;
      
      setState(() {
        _isCameraInitialized = false;
        _isCameraOn = false;
        _currentAnalysis = ''; // Clear analysis when camera stops
      });
    } catch (e) {
      debugPrint('Error stopping camera: $e');
    }
  }

  /// Process camera frames for live analysis
  void _processFrame(CameraImage image) {
    if (_isAnalyzing || !_isInitialized || !_isCameraOn) return;
    
    _lastFrameBytes = image.planes.first.bytes;
    
    // Start analysis timer - analyze every 3 seconds
    if (_analysisTimer == null || !_analysisTimer!.isActive) {
      _analysisTimer = Timer.periodic(const Duration(seconds: 3), (Timer t) async {
        if (_lastFrameBytes != null && !_isAnalyzing && mounted && _isCameraOn) {
          await _analyzeLiveFrame(_lastFrameBytes!);
        }
      });
    }
  }

  /// Analyze live frame
  Future<void> _analyzeLiveFrame(Uint8List frameBytes) async {
    if (_model == null || _isAnalyzing || !mounted || !_isCameraOn) return;

    setState(() {
      _isAnalyzing = true;
      _currentAnalysis = 'Analyzing...';
    });

    try {
      final imagePart = DataPart('image/jpeg', frameBytes);
      final textPart = TextPart(
        'You are "Alert.AI". If everything looks safe, say so in 1 sentence. If there is danger, explain what you see and what to do in 2-3 sentences. Always finish your thought. No markdown.',
      );
      
      final content = [Content.multi([textPart, imagePart])];
      
      final response = await _model!.generateContent(content);
      final analysis = response.text ?? '';
      
      if (analysis.isNotEmpty && mounted && _isCameraOn) {
        setState(() {
          _currentAnalysis = analysis;
        });
      }
    } catch (e) {
      debugPrint('Live analysis error: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isAnalyzing = false;
        });
      }
    }
  }

  Future<void> _initSpeech() async {
    _speech = stt.SpeechToText();
    
    try {
      var status = await Permission.microphone.request();
      if (!status.isGranted) return;
      
      final available = await _speech!.initialize(
        onError: (error) {
          setState(() {
            _isListening = false;
          });
        },
        onStatus: (status) {
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

  @override
  void dispose() {
    _analysisTimer?.cancel();
    _thinkingController.dispose();
    _cameraController?.dispose();
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
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

  /// Send message with streaming response
  Future<void> _sendMessage([String? voiceText]) async {
    final text = voiceText ?? _messageController.text.trim();
    if (text.isEmpty || !_isInitialized || _model == null) return;

    _messageController.clear();
    _addUserMessage(text);

    setState(() {
      _isStreaming = true;
      _currentStreamingResponse = '';
      _messages.add({
        'from': 'bot',
        'text': '',
        'timestamp': DateTime.now(),
        'isStreaming': true,
      });
    });

    try {
      final content = Content.text(
        'You are "Alert.AI", a campus safety assistant. Talk naturally like a real person.\nFor casual questions, reply in 1-2 sentences. For urgent/dangerous situations, give essential safety steps in 3-5 sentences. Always complete your thought. No bullet points or markdown.\n\nUser: $text',
      );
      final response = await _model!.generateContentStream([content]);
      
      String fullResponse = '';
      await for (final chunk in response) {
        final text = chunk.text ?? '';
        if (text.isNotEmpty) {
          fullResponse += text;
          setState(() {
            _currentStreamingResponse = fullResponse;
            if (_messages.isNotEmpty) {
              _messages[_messages.length - 1]['text'] = fullResponse;
            }
          });
        }
      }
    } catch (e) {
      setState(() {
        _currentStreamingResponse = 'Error: ${e.toString()}';
        if (_messages.isNotEmpty) {
          _messages[_messages.length - 1]['text'] = _currentStreamingResponse;
        }
      });
    } finally {
      setState(() {
        _isStreaming = false;
      });
      _scrollToBottom();
    }
  }

  Future<void> _startListening() async {
    if (!_speechInitialized || _speech == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Voice recognition not available')),
      );
      return;
    }

    setState(() {
      _isListening = true;
    });

    await _speech!.listen(
      onResult: (result) {
        if (result.finalResult) {
          final words = result.recognizedWords;
          if (words.isNotEmpty) {
            _sendMessage(words);
          }
          setState(() {
            _isListening = false;
          });
        }
      },
      listenFor: const Duration(seconds: 30),
      pauseFor: const Duration(seconds: 5),
      localeId: 'en_MY',
    );
  }

  void _stopListening() {
    _speech?.stop();
    setState(() {
      _isListening = false;
    });
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
          if (_isAnalyzing || _isStreaming)
            const Padding(
              padding: EdgeInsets.all(16.0),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
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
          
          // LIVE Camera Preview - Shows only when camera is ON
          _buildCameraSection(),
          
          // Live Analysis Card - Shows only when camera is ON
          if (_isCameraOn && _currentAnalysis.isNotEmpty)
            _buildAnalysisCard(),
          
          // Action Buttons
          _buildActionButtons(),
          
          // Chat messages
          Expanded(
            child: _buildChatSection(),
          ),
          
          // Input section
          _buildInputSection(),
        ],
      ),
    );
  }

  Widget _buildCameraSection() {
    return Container(
      height: 250,
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
                      CameraPreview(_cameraController!),
                      // LIVE indicator
                      Positioned(
                        top: 8,
                        left: 8,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.red,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.videocam, color: Colors.white, size: 14),
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
                          'Tap "Start Video" to turn on',
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

  Widget _buildAnalysisCard() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.green.shade900,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.green, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.psychology, color: Colors.green, size: 20),
              const SizedBox(width: 8),
              const Text(
                'AI Analysis:',
                style: TextStyle(
                  color: Colors.green,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const Spacer(),
              if (_isAnalyzing)
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.green,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            _currentAnalysis,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButtons() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          // START/STOP Video button - The main feature
          _buildActionButton(
            icon: _isCameraOn ? Icons.videocam_off : Icons.videocam,
            label: _isCameraOn ? 'End Video' : 'Start Video',
            color: _isCameraOn ? Colors.red : Colors.green,
            onPressed: _isCameraStarting ? null : (_isCameraOn ? _stopCamera : _startCamera),
          ),
          
          // Voice button
          _buildActionButton(
            icon: _isListening ? Icons.mic : Icons.mic_none,
            label: _isListening ? 'Listening...' : 'Voice',
            color: _isListening ? Colors.red : Colors.blue,
            onPressed: _isListening ? _stopListening : _startListening,
          ),
        ],
      ),
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required Color color,
    VoidCallback? onPressed,
  }) {
    return Column(
      children: [
        ElevatedButton(
          onPressed: onPressed,
          style: ElevatedButton.styleFrom(
            backgroundColor: color,
            shape: const CircleBorder(),
            padding: const EdgeInsets.all(16),
          ),
          child: Icon(icon, color: Colors.white, size: 28),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: const TextStyle(
            color: Colors.white70,
            fontSize: 12,
          ),
        ),
      ],
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
                final isStreaming = msg['isStreaming'] == true;
                
                return _buildMessageBubble(msg, isUser, isStreaming);
              },
            ),
    );
  }

  Widget _buildMessageBubble(Map<String, dynamic> msg, bool isUser, bool isStreaming) {
    final timestamp = msg['timestamp'] as DateTime?;
    
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!isUser) ...[
            CircleAvatar(
              radius: 14,
              backgroundColor: Colors.deepPurple.shade100,
              child: Icon(
                Icons.support_agent,
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
                  Row(
                    children: [
                      if (isStreaming)
                        AnimatedBuilder(
                          animation: _thinkingAnimation,
                          builder: (context, child) {
                            return Opacity(
                              opacity: _thinkingAnimation.value,
                              child: const Padding(
                                padding: EdgeInsets.only(right: 8),
                                child: SizedBox(
                                  width: 12,
                                  height: 12,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.deepPurple,
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      Expanded(
                        child: Text(
                          msg['text'] ?? '',
                          style: TextStyle(
                            color: isUser ? Colors.white : Colors.black87,
                            fontSize: 14,
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (timestamp != null && !isStreaming) ...[
                    const SizedBox(height: 4),
                    Text(
                      _formatTime(timestamp),
                      style: TextStyle(
                        color: isUser ? Colors.white60 : Colors.grey.shade500,
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
            Expanded(
              child: TextField(
                controller: _messageController,
                enabled: _isInitialized && !_isStreaming,
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
                    borderSide: const BorderSide(color: Colors.deepPurple, width: 2),
                  ),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  filled: true,
                  fillColor: Colors.grey.shade50,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Container(
              decoration: BoxDecoration(
                color: (_isInitialized && !_isStreaming) 
                    ? Colors.deepPurple 
                    : Colors.grey.shade300,
                shape: BoxShape.circle,
              ),
              child: IconButton(
                icon: Icon(
                  _isStreaming ? Icons.hourglass_empty : Icons.send,
                  color: Colors.white,
                ),
                onPressed: (_isInitialized && !_isStreaming) 
                    ? () => _sendMessage() 
                    : null,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatTime(DateTime time) {
    return '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
  }
}
