import 'package:cloud_firestore/cloud_firestore.dart';

class ChatDataService {
  /// Get summary statistics for reports
  static Future<Map<String, dynamic>> getReportSummary() async {
    try {
      final reportsRef = FirebaseFirestore.instance.collection('reports');
      
      // Get total reports
      final totalSnapshot = await reportsRef.get();
      final totalReports = totalSnapshot.docs.length;
      
      // Get SOS count
      final sosSnapshot = await reportsRef.where('Type', isEqualTo: 'SOS').get();
      final sosCount = sosSnapshot.docs.length;
      
      // Get pending reports
      final pendingSnapshot = await reportsRef.where('Status', isEqualTo: 'Pending').get();
      final pendingCount = pendingSnapshot.docs.length;
      
      // Get solved reports
      final solvedSnapshot = await reportsRef.where('Status', isEqualTo: 'Solved').get();
      final solvedCount = solvedSnapshot.docs.length;
      
      // Get recent reports (last 5)
      final recentSnapshot = await reportsRef.orderBy('Time', descending: true).limit(5).get();
      final recentReports = recentSnapshot.docs.map((doc) {
        final data = doc.data();
        return {
          'type': data['Type'] ?? 'Unknown',
          'status': data['Status'] ?? 'Unknown',
          'details': data['Details'] ?? '',
          'time': data['Time'] != null ? _formatDateTime(data['Time'].toDate()) : 'Unknown',
        };
      }).toList();

      return {
        'totalReports': totalReports,
        'sosCount': sosCount,
        'pendingCount': pendingCount,
        'solvedCount': solvedCount,
        'recentReports': recentReports,
        'success': true,
      };
    } catch (e) {
      return {
        'success': false,
        'error': e.toString(),
      };
    }
  }

  /// Get user statistics
  static Future<Map<String, dynamic>> getUserStats(String? userId) async {
    if (userId == null) {
      return {'success': false, 'error': 'User not logged in'};
    }
    
    try {
      final reportsRef = FirebaseFirestore.instance.collection('reports');
      
      // Get user's total reports
      final userReportsSnapshot = await reportsRef.where('UserID', isEqualTo: userId).get();
      final userReportCount = userReportsSnapshot.docs.length;
      
      // Get user's SOS count
      final userSosSnapshot = await reportsRef
          .where('UserID', isEqualTo: userId)
          .where('Type', isEqualTo: 'SOS')
          .get();
      final userSosCount = userSosSnapshot.docs.length;

      return {
        'userReportCount': userReportCount,
        'userSosCount': userSosCount,
        'success': true,
      };
    } catch (e) {
      return {
        'success': false,
        'error': e.toString(),
      };
    }
  }

  /// Get all available data as a context string for the AI
  static Future<String> getSystemContext() async {
    final summary = await getReportSummary();
    
    if (!summary['success']) {
      return 'Error loading system data: ${summary['error']}';
    }

    final context = '''
SYSTEM DATA:
- Total Reports: ${summary['totalReports']}
- Total SOS Alerts: ${summary['sosCount']}
- Pending Reports: ${summary['pendingCount']}
- Solved Reports: ${summary['solvedCount']}

Recent Reports:
${_formatRecentReports(summary['recentReports'] as List)}

AVAILABLE ACTIONS:
1. View all reports - Show the complete list of reports
2. View SOS alerts - Show all SOS emergency alerts
3. View pending reports - Show reports awaiting action
4. View solved reports - Show resolved incidents
5. Create new report - Submit a new incident report
6. Trigger SOS - Send an emergency SOS alert

IMPORTANT FORMATTING INSTRUCTIONS:
- Do NOT use markdown formatting (no *, #, -, or other special characters for formatting)
- Do NOT use bullet points with special characters
- Use plain text only
- Use numbered lists (1., 2., 3.) if you need to list multiple items
- Separate sections with clear line breaks

Please answer user questions based on the above data. If asked about statistics, provide the exact numbers. If asked about actions, guide the user to the appropriate feature using plain text.
''';
    return context;
  }

  static String _formatRecentReports(List reports) {
    if (reports.isEmpty) return 'No recent reports';
    
    final buffer = StringBuffer();
    for (int i = 0; i < reports.length; i++) {
      final r = reports[i];
      buffer.write('${i + 1}. ${r['type']} (${r['status']}) - ${r['time']}');
      if (i < reports.length - 1) buffer.write('\n');
    }
    return buffer.toString();
  }

  static String _formatDateTime(DateTime dt) {
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }
}
