import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'admin_ai_service.dart';

class AdminChatPage extends StatefulWidget {
  const AdminChatPage({Key? key}) : super(key: key);

  @override
  State<AdminChatPage> createState() => _AdminChatPageState();
}

class _AdminChatPageState extends State<AdminChatPage> {
  final TextEditingController _ctrl = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final List<Map<String, dynamic>> _messages = [];
  bool _sending = false;
  bool _initialized = false;
  bool _loadingData = false;
  String? _errorMessage;
  GenerativeModel? _model;
  AdminAIService? _adminService;

  @override
  void initState() {
    super.initState();
    _initializeAI();
  }

  @override
  void dispose() {
    _ctrl.dispose();
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

  Future<void> _initializeAI() async {
    try {
      if (!dotenv.isInitialized) await dotenv.load(fileName: '.env');

      final apiKey = dotenv.env['GEMINI_API_KEY'];
      if (apiKey == null || apiKey.isEmpty) {
        setState(() {
          _errorMessage = 'GEMINI_API_KEY not set in .env.';
          _messages.add({
            'from': 'bot',
            'text': 'Error: AI service not configured. Please set GEMINI_API_KEY in .env.',
            'timestamp': DateTime.now(),
          });
          _initialized = true;
        });
        return;
      }

      // Initialize Admin AI Service
      _adminService = await AdminAIService.getInstance();

      // Initialize Gemini model directly
      _model = GenerativeModel(
        model: 'gemini-2.0-flash',
        apiKey: apiKey,
      );

      setState(() {
        _loadingData = true;
      });

      // Welcome message - add after setting loading
      if (mounted) {
        String welcomeText = 'Hello! I am your AI Admin Assistant for Campus Safety. ';
        welcomeText += 'I can help you with:\n';
        welcomeText += '• Daily and weekly report summaries\n';
        welcomeText += '• Statistics and trend analysis\n';
        welcomeText += '• Incident type breakdown\n';
        welcomeText += '• Performance metrics\n\n';
        welcomeText += 'Try asking: "Generate daily summary" or "Show me weekly trends"';
        
        _messages.add({
          'from': 'bot',
          'text': welcomeText,
          'timestamp': DateTime.now(),
        });
        
        setState(() {
          _initialized = true;
          _loadingData = false;
        });
        
        _scrollToBottom();
      }
    } catch (e) {
      setState(() {
        _errorMessage = e.toString();
        _initialized = true;
        _loadingData = false;
        _messages.add({
          'from': 'bot',
          'text': 'Error initializing admin chat: ${e.toString()}',
          'timestamp': DateTime.now(),
        });
      });
    }
  }

  Future<void> _send() async {
    final text = _ctrl.text.trim();
    if (text.isEmpty || !_initialized || _adminService == null) return;

    setState(() {
      _messages.add({
        'from': 'user',
        'text': text,
        'timestamp': DateTime.now(),
      });
      _sending = true;
      _ctrl.clear();
    });

    _scrollToBottom();

    try {
      // Check for specific commands
      final lowerText = text.toLowerCase();
      String reply;
      
      if (lowerText.contains('daily summary') || lowerText.contains('generate daily') || lowerText.contains('today\'s report')) {
        reply = await _adminService!.generateDailySummary();
      } else if (lowerText.contains('weekly') || lowerText.contains('trend') || lowerText.contains('last week')) {
        reply = await _adminService!.generateWeeklyTrends();
      } else {
        // Regular question - use the admin service
        reply = await _adminService!.sendMessage(text);
      }
      
      setState(() {
        _messages.add({
          'from': 'bot',
          'text': reply,
          'timestamp': DateTime.now(),
        });
      });
    } catch (e) {
      setState(() {
        _messages.add({
          'from': 'bot',
          'text': 'Error: ${e.toString()}',
          'timestamp': DateTime.now(),
        });
      });
    } finally {
      setState(() {
        _sending = false;
      });
      _scrollToBottom();
    }
  }

  String _formatTime(DateTime time) {
    return '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('AI Admin Assistant'),
        backgroundColor: Colors.deepPurple,
        actions: [
          if (_loadingData)
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
          if (_errorMessage != null)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(8),
              color: Colors.red.shade100,
              child: Text(_errorMessage!, textAlign: TextAlign.center),
            ),
          Expanded(
            child: _messages.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.analytics,
                          size: 64,
                          color: Colors.deepPurple.shade200,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Ask me about admin reports and analytics!',
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
                    itemCount: _messages.length + (_sending ? 1 : 0),
                    itemBuilder: (context, index) {
                      // Show typing indicator at the end
                      if (_sending && index == _messages.length) {
                        return _buildTypingIndicator();
                      }
                      
                      final msg = _messages[index];
                      final isUser = msg['from'] == 'user';
                      return _buildMessageBubble(msg, isUser);
                    },
                  ),
          ),
          SafeArea(
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                boxShadow: [
                  BoxShadow(
                    color: Colors.grey.shade200,
                    blurRadius: 4,
                    offset: const Offset(0, -2),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 8.0),
                      child: TextField(
                        controller: _ctrl,
                        enabled: _initialized && !_sending,
                        textInputAction: TextInputAction.send,
                        onSubmitted: (_) => _send(),
                        maxLines: 3,
                        minLines: 1,
                        decoration: InputDecoration(
                          hintText: _initialized ? 'Ask the admin assistant...' : 'Loading AI...',
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
                  ),
                  Padding(
                    padding: const EdgeInsets.only(right: 8.0),
                    child: Container(
                      decoration: BoxDecoration(
                        color: (_initialized && !_sending) ? Colors.deepPurple : Colors.grey.shade300,
                        shape: BoxShape.circle,
                      ),
                      child: IconButton(
                        icon: Icon(
                          _sending ? Icons.hourglass_empty : Icons.send,
                          color: Colors.white,
                        ),
                        onPressed: (_initialized && !_sending) ? _send : null,
                      ),
                    ),
                  )
                ],
              ),
            ),
          )
        ],
      ),
    );
  }

  Widget _buildMessageBubble(Map<String, dynamic> msg, bool isUser) {
    final timestamp = msg['timestamp'] as DateTime?;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!isUser) ...[
            CircleAvatar(
              radius: 16,
              backgroundColor: Colors.deepPurple.shade100,
              child: const Icon(Icons.analytics, size: 18, color: Colors.deepPurple),
            ),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: Container(
              padding: const EdgeInsets.all(14),
              constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.72),
              decoration: BoxDecoration(
                color: isUser ? Colors.deepPurple : Colors.grey.shade100,
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(18),
                  topRight: const Radius.circular(18),
                  bottomLeft: Radius.circular(isUser ? 18 : 4),
                  bottomRight: Radius.circular(isUser ? 4 : 18),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
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
                      fontSize: 15,
                      height: 1.4,
                    ),
                  ),
                  if (timestamp != null) ...[
                    const SizedBox(height: 6),
                    Text(
                      _formatTime(timestamp),
                      style: TextStyle(
                        color: isUser ? Colors.white70 : Colors.grey.shade500,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          if (isUser) ...[
            const SizedBox(width: 8),
            CircleAvatar(
              radius: 16,
              backgroundColor: Colors.deepPurple.shade400,
              child: const Icon(Icons.person, size: 18, color: Colors.white),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildTypingIndicator() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          CircleAvatar(
            radius: 16,
            backgroundColor: Colors.deepPurple.shade100,
            child: const Icon(Icons.analytics, size: 18, color: Colors.deepPurple),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(18),
                topRight: Radius.circular(18),
                bottomLeft: Radius.circular(4),
                bottomRight: Radius.circular(18),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildDot(0),
                const SizedBox(width: 4),
                _buildDot(1),
                const SizedBox(width: 4),
                _buildDot(2),
                const SizedBox(width: 8),
                Text(
                  'AI is thinking...',
                  style: TextStyle(
                    color: Colors.grey.shade600,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDot(int index) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.3, end: 1.0),
      duration: Duration(milliseconds: 600 + (index * 200)),
      builder: (context, value, child) {
        return Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: Colors.deepPurple.withOpacity(value),
            shape: BoxShape.circle,
          ),
        );
      },
    );
  }
}
