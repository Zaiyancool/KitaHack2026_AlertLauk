import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'chat_data_service.dart';

class ChatPage extends StatefulWidget {
  const ChatPage({Key? key}) : super(key: key);

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  final TextEditingController _ctrl = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final List<Map<String, dynamic>> _messages = [];
  bool _sending = false;
  bool _initialized = false;
  bool _loadingData = false;
  String? _errorMessage;
  GenerativeModel? _model;
  String _systemContext = '';

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

      // Initialize Gemini model directly
      _model = GenerativeModel(
        model: 'gemini-2.5-flash',
        apiKey: apiKey,
      );

      // Load system data
      setState(() {
        _loadingData = true;
      });
      
      _systemContext = await ChatDataService.getSystemContext();
      
      setState(() {
        _initialized = true;
        _loadingData = false;
      });

      // Welcome message with data info - add after loading completes
      if (mounted) {
        final summary = await ChatDataService.getReportSummary();
        String welcomeText = 'Hello! I am your AI Safety Assistant. ';
        
        if (summary['success']) {
          welcomeText += 'Current system status: ${summary['totalReports']} total reports, ${summary['sosCount']} SOS alerts, ${summary['pendingCount']} pending. ';
        }
        
        welcomeText += 'Ask me about campus safety, reports, SOS alerts, or statistics.';
        
        _messages.add({
          'from': 'bot',
          'text': welcomeText,
          'timestamp': DateTime.now(),
        });
        
        _scrollToBottom();
      }
    } catch (e) {
      setState(() {
        _errorMessage = e.toString();
        _initialized = true; // Still allow basic chat
        _loadingData = false;
        _messages.add({
          'from': 'bot',
          'text': 'Error initializing chat: ${e.toString()}. You can still ask basic questions.',
          'timestamp': DateTime.now(),
        });
      });
    }
  }

  Future<void> _send() async {
    final text = _ctrl.text.trim();
    if (text.isEmpty || !_initialized || _model == null) return;

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
      // Build the prompt with system context
      final userQuestion = text.toLowerCase();
      
      // Check if user is asking for statistics or data
      final needsRefresh = userQuestion.contains('how many') || 
                          userQuestion.contains('total') || 
                          userQuestion.contains('count') ||
                          userQuestion.contains('stats') ||
                          userQuestion.contains('statistics') ||
                          userQuestion.contains('report') ||
                          userQuestion.contains('sos');
      
      String context = _systemContext;
      if (needsRefresh || _systemContext.isEmpty) {
        // Refresh data for accurate numbers
        context = await ChatDataService.getSystemContext();
      }
      
      final prompt = '''
You are an AI Safety Assistant for a campus safety application. 

$context

User Question: $text

Please provide a helpful response based on the system data above. If the user asks about statistics, provide the exact numbers from the data. If they ask about actions they can take, guide them accordingly. Be concise and helpful.
''';

      final content = Content.text(prompt);
      final response = await _model!.generateContent([content]);
      final reply = response.text ?? 'Sorry, I could not generate a response.';
      
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
        title: const Text('AI Safety Assistant'),
        backgroundColor: Colors.blue,
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
                          Icons.support_agent,
                          size: 64,
                          color: Colors.blue.shade200,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Ask me anything about campus safety!',
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
                          hintText: _initialized ? 'Ask the safety assistant...' : 'Loading AI...',
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
                            borderSide: const BorderSide(color: Colors.blue, width: 2),
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
                        color: (_initialized && !_sending) ? Colors.blue : Colors.grey.shade300,
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
              backgroundColor: Colors.blue.shade100,
              child: const Icon(Icons.support_agent, size: 18, color: Colors.blue),
            ),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: Container(
              padding: const EdgeInsets.all(14),
              constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.72),
              decoration: BoxDecoration(
                color: isUser ? Colors.blue : Colors.grey.shade100,
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
              backgroundColor: Colors.blue.shade400,
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
            backgroundColor: Colors.blue.shade100,
            child: const Icon(Icons.support_agent, size: 18, color: Colors.blue),
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
            color: Colors.blue.withOpacity(value),
            shape: BoxShape.circle,
          ),
        );
      },
    );
  }
}
