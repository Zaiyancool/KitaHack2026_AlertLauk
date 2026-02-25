import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

class AdminAIService {
  late final GenerativeModel _model;
  static AdminAIService? _instance;

  AdminAIService._();

  static Future<AdminAIService> getInstance() async {
    if (_instance == null) {
      _instance = AdminAIService._();
      await _instance!._initialize();
    }
    return _instance!;
  }

  Future<void> _initialize() async {
    await dotenv.load(fileName: '.env');
    
    final apiKey = dotenv.env['GEMINI_API_KEY'];
    
    if (apiKey == null || apiKey.isEmpty) {
      throw Exception('GEMINI_API_KEY not found in .env file');
    }

    _model = GenerativeModel(
      model: 'gemini-2.5-flash',
      apiKey: apiKey,
    );
  }

  /// Helper to safely get field from document
  dynamic _safeGetField(DocumentSnapshot doc, String field, {dynamic defaultValue}) {
    try {
      return doc.get(field);
    } catch (e) {
      return defaultValue;
    }
  }

  /// Clean response from special characters
  String _cleanResponse(String response) {
    // Remove markdown symbols like **, *, ###, etc.
    return response
        .replaceAll(RegExp(r'#{1,6}\s*'), '')
        .replaceAll(RegExp(r'\*{1,2}'), '')
        .replaceAll(RegExp(r'_'), '')
        .replaceAll(RegExp(r'`'), '')
        .trim();
  }

  /// Get comprehensive admin data for AI analysis
  Future<Map<String, dynamic>> getAdminDataContext() async {
    try {
      final reportsRef = FirebaseFirestore.instance.collection('reports');
      
      // Get all reports
      final allReportsSnapshot = await reportsRef.get();
      final allReports = allReportsSnapshot.docs;
      
      // Get pending reports
      final pendingSnapshot = await reportsRef.where('Status', isEqualTo: 'Pending').get();
      final pendingReports = pendingSnapshot.docs;
      
      // Get solved reports
      final solvedSnapshot = await reportsRef.where('Status', isEqualTo: 'Solved').get();
      final solvedReports = solvedSnapshot.docs;
      
      // Get SOS reports
      final sosSnapshot = await reportsRef.where('Type', isEqualTo: 'SOS').get();
      final sosReports = sosSnapshot.docs;
      
      // Get reports from last 7 days
      final sevenDaysAgo = DateTime.now().subtract(const Duration(days: 7));
      final weekSnapshot = await reportsRef.where('Time', isGreaterThan: Timestamp.fromDate(sevenDaysAgo)).get();
      
      // Get reports from last 24 hours
      final yesterday = DateTime.now().subtract(const Duration(days: 1));
      final daySnapshot = await reportsRef.where('Time', isGreaterThan: Timestamp.fromDate(yesterday)).get();
      
      // Analyze incident types
      Map<String, int> incidentTypes = {};
      for (var doc in allReports) {
        final type = _safeGetField(doc, 'Type', defaultValue: 'Unknown') ?? 'Unknown';
        incidentTypes[type] = (incidentTypes[type] ?? 0) + 1;
      }
      
      // Calculate average resolution time (for solved reports)
      int totalResolutionMinutes = 0;
      int solvedWithTime = 0;
      for (var doc in solvedReports) {
        try {
          final createdAt = _safeGetField(doc, 'Time');
          final updatedAt = _safeGetField(doc, 'UpdatedAt');
          if (createdAt != null && updatedAt != null) {
            final created = createdAt.toDate();
            final updated = updatedAt.toDate();
            final int diff = updated.difference(created).inMinutes;
            totalResolutionMinutes += diff;
            solvedWithTime++;
          }
        } catch (e) {
          continue;
        }
      }
      int avgResolutionMinutes = 0;
      if (solvedWithTime > 0) {
        avgResolutionMinutes = (totalResolutionMinutes ~/ solvedWithTime);
      }
      
      return {
        'totalReports': allReports.length,
        'pendingReports': pendingReports.length,
        'solvedReports': solvedReports.length,
        'sosReports': sosReports.length,
        'reportsLast7Days': weekSnapshot.docs.length,
        'reportsLast24Hours': daySnapshot.docs.length,
        'incidentTypes': incidentTypes,
        'avgResolutionMinutes': avgResolutionMinutes,
        'recentReports': allReports.take(10).map((doc) => {
          'id': doc.id,
          'type': _safeGetField(doc, 'Type', defaultValue: 'Unknown'),
          'status': _safeGetField(doc, 'Status', defaultValue: 'Unknown'),
          'details': _safeGetField(doc, 'Details', defaultValue: ''),
          'time': _safeGetField(doc, 'Time')?.toDate().toString() ?? 'Unknown',
          'location': _safeGetField(doc, 'Location', defaultValue: 'Unknown'),
        }).toList(),
        'success': true,
      };
    } catch (e) {
      return {
        'success': false,
        'error': e.toString(),
      };
    }
  }

  String _formatRecentReports(List reports) {
    if (reports.isEmpty) return 'No recent reports';
    
    final buffer = StringBuffer();
    for (int i = 0; i < reports.length; i++) {
      final r = reports[i];
      buffer.write('${i + 1}. ${r['type']} (${r['status']}) - ${r['time']} - ${r['location']}');
      if (i < reports.length - 1) buffer.write('\n');
    }
    return buffer.toString();
  }

  /// Send message to AI and get response
  Future<String> sendMessage(String message) async {
    try {
      final context = await buildAdminContext();
      
      final isGreeting = message.toLowerCase().contains('hello') || 
                         message.toLowerCase().contains('hi') || 
                         message.toLowerCase().contains('hey') ||
                         message.toLowerCase() == 'start' ||
                         message.toLowerCase() == 'help';
      
      final prompt = '''
$context

Admin Question: $message

${isGreeting ? 'This is a greeting. Reply with: 1) Brief welcome (1 sentence) 2) One-line current stats summary (e.g., "31 reports: 24 pending, 7 solved, 17 SOS alerts"). Keep it under 3 sentences total.' : 'Provide a CONCISE response. Key rules: Max 3-4 sentences. Lead with the most important number or action. No markdown formatting. Plain text only.'}
''';

      final content = Content.text(prompt);
      final response = await _model.generateContent([content]);
      return _cleanResponse(response.text ?? 'Sorry, I could not generate a response.');
    } catch (e) {
      return 'Error: ${e.toString()}';
    }
  }

  /// Build context string for AI
  Future<String> buildAdminContext() async {
    final data = await getAdminDataContext();
    
    if (!data['success']) {
      return 'Error loading admin data: ${data['error']}';
    }
    
    final incidentTypesStr = (data['incidentTypes'] as Map<String, int>)
        .entries
        .map((e) => '${e.key}: ${e.value}')
        .join(', ');
    
    final pendingRate = data['totalReports'] > 0 
        ? ((data['pendingReports'] / data['totalReports']) * 100).toStringAsFixed(0)
        : '0';
    
    final context = '''
ADMIN DASHBOARD SNAPSHOT:

TOTAL: ${data['totalReports']} reports | PENDING: ${data['pendingReports']} ($pendingRate%) | SOLVED: ${data['solvedReports']}
SOS ALERTS: ${data['sosReports']} | LAST 24H: ${data['reportsLast24Hours']} | AVG RESOLUTION: ${data['avgResolutionMinutes']} min

INCIDENT TYPES: $incidentTypesStr

RECENT (Last 10):
${_formatRecentReports(data['recentReports'] as List)}

You are an AI Admin Assistant for campus safety. Be concise, actionable, and data-driven.
''';
    
    return context;
  }

  /// Get quick dashboard summary for real-time display
  Future<Map<String, dynamic>> getDashboardSummary() async {
    try {
      final data = await getAdminDataContext();
      
      if (!data['success']) {
        return data;
      }
      
      final pendingRate = data['totalReports'] > 0 
          ? ((data['pendingReports'] / data['totalReports']) * 100).toStringAsFixed(0)
          : '0';
      
      final resolutionRate = data['totalReports'] > 0 
          ? ((data['solvedReports'] / data['totalReports']) * 100).toStringAsFixed(0)
          : '0';
      
      final incidentTypes = data['incidentTypes'] as Map<String, int>;
      final sortedTypes = incidentTypes.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      final topTypes = sortedTypes.take(3).toList();
      
      return {
        'success': true,
        'totalReports': data['totalReports'],
        'pendingReports': data['pendingReports'],
        'solvedReports': data['solvedReports'],
        'sosReports': data['sosReports'],
        'reportsLast24Hours': data['reportsLast24Hours'],
        'reportsLast7Days': data['reportsLast7Days'],
        'avgResolutionMinutes': data['avgResolutionMinutes'],
        'pendingRate': pendingRate,
        'resolutionRate': resolutionRate,
        'topIncidentTypes': topTypes.map((e) => {'type': e.key, 'count': e.value}).toList(),
      };
    } catch (e) {
      return {
        'success': false,
        'error': e.toString(),
      };
    }
  }

  /// Generate priority alerts based on current data
  Future<String> generatePriorityAlerts() async {
    try {
      final data = await getAdminDataContext();
      
      if (!data['success']) {
        return 'Error generating alerts: ${data['error']}';
      }
      
      final reportsRef = FirebaseFirestore.instance.collection('reports');
      final pendingSosSnapshot = await reportsRef
          .where('Status', isEqualTo: 'Pending')
          .where('Type', isEqualTo: 'SOS')
          .get();
      
      final pendingSosCount = pendingSosSnapshot.docs.length;
      
      final allPendingSnapshot = await reportsRef
          .where('Status', isEqualTo: 'Pending')
          .get();
      
      final yesterday = DateTime.now().subtract(const Duration(hours: 24));
      int oldPendingCount = 0;
      for (var doc in allPendingSnapshot.docs) {
        final time = _safeGetField(doc, 'Time');
        if (time != null && time is Timestamp) {
          if (time.toDate().isBefore(yesterday)) {
            oldPendingCount++;
          }
        }
      }
      
      final prompt = '''
Generate priority ALERTS for the admin based on this data.

IMPORTANT: Output in plain text only. NO markdown, NO asterisks (#, *, ##, etc), NO special characters. Just clean plain text.

CRITICAL:
- Pending SOS Alerts: $pendingSosCount
- Pending Reports Older Than 24 Hours: $oldPendingCount

OVERVIEW:
- Total Pending: ${data['pendingReports']}
- Total SOS: ${data['sosReports']}
- Reports Last 24 Hours: ${data['reportsLast24Hours']}
- Average Resolution Time: ${data['avgResolutionMinutes']} minutes

Please provide concise alerts with:
1. Priority Level (CRITICAL/HIGH/MEDIUM/NORMAL)
2. Immediate Action Required (brief)
3. Brief reason

Use plain text only. No markdown symbols.
''';

      final content = Content.text(prompt);
      final response = await _model.generateContent([content]);
      return _cleanResponse(response.text ?? 'No alerts at this time.');
    } catch (e) {
      return 'Error: ${e.toString()}';
    }
  }

  /// Generate AI-powered recommended actions
  Future<String> generateRecommendedActions() async {
    try {
      final data = await getAdminDataContext();
      
      if (!data['success']) {
        return 'Error generating recommendations: ${data['error']}';
      }
      
      // Get pending reports without ordering to avoid index requirement
      final reportsRef = FirebaseFirestore.instance.collection('reports');
      final allReportsSnapshot = await reportsRef
          .where('Status', isEqualTo: 'Pending')
          .limit(20)
          .get();
      
      // Sort manually by time (newest first)
      final pendingDocs = allReportsSnapshot.docs.toList()
        ..sort((a, b) {
          final timeA = _safeGetField(a, 'Time');
          final timeB = _safeGetField(b, 'Time');
          if (timeA == null || timeB == null) return 0;
          return timeB.compareTo(timeA);
        });
      
      final recentPending = pendingDocs.take(5).toList();
      
      // Format pending reports safely
      final pendingReportsStr = recentPending.isNotEmpty 
          ? recentPending.map((r) => '- ${_safeGetField(r, 'Type', defaultValue: 'Unknown')}: ${_safeGetField(r, 'Details', defaultValue: '')}').join('\n')
          : 'No pending reports';
      
      final prompt = '''
Analyze the following data and provide 3-5 SPECIFIC actionable recommendations for the admin.

IMPORTANT: Output in plain text only. NO markdown, NO asterisks (#, *, **), NO special characters. Just clean plain text.

CURRENT STATS:
- Total Reports: ${data['totalReports']}
- Pending: ${data['pendingReports']}
- Solved: ${data['solvedReports']}
- SOS Alerts: ${data['sosReports']}
- Reports Last 24 Hours: ${data['reportsLast24Hours']}
- Reports Last 7 Days: ${data['reportsLast7Days']}
- Average Resolution Time: ${data['avgResolutionMinutes']} minutes

INCIDENT TYPES: ${(data['incidentTypes'] as Map<String, int>).entries.map((e) => '${e.key}: ${e.value}').join(', ')}

PENDING REPORTS (Recent):
$pendingReportsStr

Provide recommendations that are specific, actionable, and prioritized. Keep each recommendation brief (1-2 sentences).

Format as a simple numbered list with plain text only. No markdown.
''';

      final content = Content.text(prompt);
      final response = await _model.generateContent([content]);
      return _cleanResponse(response.text ?? 'No recommendations at this time.');
    } catch (e) {
      return 'Error: ${e.toString()}';
    }
  }

  /// Generate daily summary report
  Future<String> generateDailySummary() async {
    try {
      final data = await getAdminDataContext();
      
      if (!data['success']) {
        return 'Error generating summary: ${data['error']}';
      }
      
      final prompt = '''
Generate a detailed DAILY SUMMARY REPORT for the admin.

IMPORTANT: Output in plain text only. NO markdown, NO special characters.

Total Reports Today: ${data['reportsLast24Hours']}
Total Reports This Week: ${data['reportsLast7Days']}
Pending: ${data['pendingReports']}
Solved: ${data['solvedReports']}
SOS Alerts: ${data['sosReports']}
Average Resolution Time: ${data['avgResolutionMinutes']} minutes

Incident Types: ${(data['incidentTypes'] as Map<String, int>).entries.map((e) => '${e.key}: ${e.value}').join(', ')}

Please provide:
1. Executive Summary (2-3 sentences)
2. Key Statistics
3. Priority Alerts
4. Recommendations for today

Use plain text only.
''';

      final content = Content.text(prompt);
      final response = await _model.generateContent([content]);
      return _cleanResponse(response.text ?? 'Sorry, I could not generate a response.');
    } catch (e) {
      return 'Error: ${e.toString()}';
    }
  }

  /// Generate weekly trend analysis
  Future<String> generateWeeklyTrends() async {
    try {
      final data = await getAdminDataContext();
      
      if (!data['success']) {
        return 'Error generating trends: ${data['error']}';
      }
      
      final prompt = '''
Generate a WEEKLY TREND ANALYSIS report.

IMPORTANT: Output in plain text only. NO markdown, NO special characters.

Total Reports This Week: ${data['reportsLast7Days']}
Total Reports: ${data['totalReports']}
Pending: ${data['pendingReports']}
Solved: ${data['solvedReports']}
SOS Alerts: ${data['sosReports']}
Average Resolution Time: ${data['avgResolutionMinutes']} minutes

Incident Types: ${(data['incidentTypes'] as Map<String, int>).entries.map((e) => '${e.key}: ${e.value}').join(', ')}

Please provide:
1. Week Overview
2. Trend Analysis
3. Most Common Incidents
4. Performance Metrics
5. Recommendations for next week

Use plain text only.
''';

      final content = Content.text(prompt);
      final response = await _model.generateContent([content]);
      return _cleanResponse(response.text ?? 'Sorry, I could not generate a response.');
    } catch (e) {
      return 'Error: ${e.toString()}';
    }
  }
}
