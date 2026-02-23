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
        final type = doc['Type'] ?? 'Unknown';
        incidentTypes[type] = (incidentTypes[type] ?? 0) + 1;
      }
      
      // Calculate average resolution time (for solved reports)
      int totalResolutionMinutes = 0;
      int solvedWithTime = 0;
      for (var doc in solvedReports) {
        try {
          final createdAt = doc['Time'];
          final updatedAt = doc['UpdatedAt'];
          if (createdAt != null && updatedAt != null) {
            final created = createdAt.toDate();
            final updated = updatedAt.toDate();
            final int diff = updated.difference(created).inMinutes;
            totalResolutionMinutes += diff;
            solvedWithTime++;
          }
        } catch (e) {
          // Skip if fields don't exist or can't be converted
          continue;
        }
      }
      // Calculate average resolution time - handle num vs int properly
      int avgResolutionMinutes = 0;
      if (solvedWithTime > 0) {
        avgResolutionMinutes = (totalResolutionMinutes ~/ solvedWithTime);
      }
      
      // Get location data for heatmap
      List<Map<String, dynamic>> locations = [];
      for (var doc in allReports) {
        final geoPoint = doc['GeoPoint'] as GeoPoint?;
        if (geoPoint != null) {
          locations.add({
            'lat': geoPoint.latitude,
            'lng': geoPoint.longitude,
            'type': doc['Type'],
            'status': doc['Status'],
            'imageLabels': doc['ImageLabels'] ?? [],
          });
        }
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
        'locations': locations,
        'recentReports': allReports.take(10).map((doc) => {
          'id': doc.id,
          'type': doc['Type'],
          'status': doc['Status'],
          'details': doc['Details'],
          'time': doc['Time']?.toDate().toString() ?? 'Unknown',
          'location': doc['Location'] ?? 'Unknown',
          'imageLabels': doc['ImageLabels'] ?? [],
          'imageURL': doc['ImageURL'] ?? null,
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

  /// Build context string for AI
  Future<String> buildAdminContext() async {
    final data = await getAdminDataContext();
    
    if (!data['success']) {
      return 'Error loading admin data: ${data['error']}';
    }
    
    // Format incident types
    final incidentTypesStr = (data['incidentTypes'] as Map<String, int>)
        .entries
        .map((e) => '${e.key}: ${e.value}')
        .join(', ');
    
    // Calculate key metrics for concise display
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

ACTIONS: 1.View/Edit Report 2.View Comments 3.Mark Resolved 4.Open Map

RESPONSE STYLE:
- Keep responses SHORT and IMPACTFUL (max 3-4 sentences for summaries)
- Lead with the most important number/action
- Use minimal formatting - plain text only
- No markdown symbols (* # -)
- For greetings: 1-line welcome + 1-line quick stats summary

You are an AI Admin Assistant for campus safety. Be concise, actionable, and data-driven.
''';
    
    return context;
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
      
      // Check if this is a greeting
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
      return response.text ?? 'Sorry, I could not generate a response.';
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
Generate a detailed DAILY SUMMARY REPORT for the admin based on this data:

Total Reports Today: ${data['reportsLast24Hours']}
Total Reports This Week: ${data['reportsLast7Days']}
Pending: ${data['pendingReports']}
Solved: ${data['solvedReports']}
SOS Alerts: ${data['sosReports']}
Average Resolution Time: ${data['avgResolutionMinutes']} minutes

Incident Types: ${(data['incidentTypes'] as Map<String, int>).entries.map((e) => '${e.key}: ${e.value}').join(', ')}

Recent Reports:
${_formatRecentReports(data['recentReports'] as List)}

Please provide:
1. Executive Summary (2-3 sentences)
2. Key Statistics
3. Priority Alerts (if any SOS or pending)
4. Recommendations for today
''';

      final content = Content.text(prompt);
      final response = await _model.generateContent([content]);
      return response.text ?? 'Sorry, I could not generate a response.';
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
Generate a WEEKLY TREND ANALYSIS report:

Total Reports This Week: ${data['reportsLast7Days']}
Total Reports: ${data['totalReports']}
Pending: ${data['pendingReports']}
Solved: ${data['solvedReports']}
SOS Alerts: ${data['sosReports']}
Average Resolution Time: ${data['avgResolutionMinutes']} minutes

Incident Types Distribution:
${(data['incidentTypes'] as Map<String, int>).entries.map((e) => '${e.key}: ${e.value}').join(', ')}

Please provide:
1. Week Overview
2. Trend Analysis (compared to previous)
3. Most Common Incidents
4. Performance Metrics
5. Recommendations for next week
''';

      final content = Content.text(prompt);
      final response = await _model.generateContent([content]);
      return response.text ?? 'Sorry, I could not generate a response.';
    } catch (e) {
      return 'Error: ${e.toString()}';
    }
  }
}
