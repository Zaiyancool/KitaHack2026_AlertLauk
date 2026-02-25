import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'admin_ai_service.dart';

class AdminDashboard extends StatefulWidget {
  const AdminDashboard({super.key});

  @override
  State<AdminDashboard> createState() => _AdminDashboardState();
}

class _AdminDashboardState extends State<AdminDashboard> {
  final reportsRef = FirebaseFirestore.instance.collection('reports');
  AdminAIService? _adminService;
  bool _isLoading = true;
  Map<String, dynamic>? _dashboardData;
  String? _priorityAlerts;
  String? _recommendedActions;
  bool _loadingPriorityAlerts = false;
  bool _loadingRecommendations = false;

  @override
  void initState() {
    super.initState();
    _initializeData();
  }

  Future<void> _initializeData() async {
    try {
      _adminService = await AdminAIService.getInstance();
      await _loadDashboardData();
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error initializing: $e')),
        );
      }
    }
  }

  Future<void> _loadDashboardData() async {
    if (_adminService == null) return;
    
    try {
      final summary = await _adminService!.getDashboardSummary();
      if (mounted && summary['success'] == true) {
        setState(() {
          _dashboardData = summary;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading data: $e')),
        );
      }
    }
  }

  Future<void> _loadPriorityAlerts() async {
    if (_adminService == null || _loadingPriorityAlerts) return;
    
    setState(() {
      _loadingPriorityAlerts = true;
    });
    
    try {
      final alerts = await _adminService!.generatePriorityAlerts();
      if (mounted) {
        setState(() {
          _priorityAlerts = alerts;
          _loadingPriorityAlerts = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loadingPriorityAlerts = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error generating alerts: $e')),
        );
      }
    }
  }

  Future<void> _loadRecommendedActions() async {
    if (_adminService == null || _loadingRecommendations) return;
    
    setState(() {
      _loadingRecommendations = true;
    });
    
    try {
      final actions = await _adminService!.generateRecommendedActions();
      if (mounted) {
        setState(() {
          _recommendedActions = actions;
          _loadingRecommendations = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loadingRecommendations = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error generating actions: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('AI Analytics Dashboard'),
        backgroundColor: Colors.deepPurple,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              setState(() {
                _isLoading = true;
              });
              _loadDashboardData().then((_) {
                setState(() {
                  _isLoading = false;
                });
              });
            },
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadDashboardData,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Header
                    const Text(
                      'Campus Safety Overview',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Real-time statistics and AI insights',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey.shade600,
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Stats Cards
                    _buildStatsGrid(),
                    const SizedBox(height: 24),

                    // Quick Actions with AI
                    _buildAISection(),
                    const SizedBox(height: 24),

                    // Incident Types Breakdown
                    _buildIncidentTypes(),
                    const SizedBox(height: 24),

                    // Recent Activity
                    _buildRecentActivity(),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildStatsGrid() {
    if (_dashboardData == null) {
      return const Center(child: Text('No data available'));
    }

    final data = _dashboardData!;
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisSpacing: 12,
      mainAxisSpacing: 12,
      childAspectRatio: 1.5,
      children: [
        _buildStatCard(
          'Total Reports',
          '${data['totalReports'] ?? 0}',
          Icons.assessment,
          Colors.blue,
        ),
        _buildStatCard(
          'Pending',
          '${data['pendingReports'] ?? 0}',
          Icons.pending_actions,
          Colors.orange,
          subtitle: '${data['pendingRate'] ?? 0}% of total',
        ),
        _buildStatCard(
          'Solved',
          '${data['solvedReports'] ?? 0}',
          Icons.check_circle,
          Colors.green,
          subtitle: '${data['resolutionRate'] ?? 0}% resolved',
        ),
        _buildStatCard(
          'SOS Alerts',
          '${data['sosReports'] ?? 0}',
          Icons.warning,
          Colors.red,
        ),
        _buildStatCard(
          'Today',
          '${data['reportsLast24Hours'] ?? 0}',
          Icons.today,
          Colors.indigo,
        ),
        _buildStatCard(
          'This Week',
          '${data['reportsLast7Days'] ?? 0}',
          Icons.date_range,
          Colors.teal,
        ),
      ],
    );
  }

  Widget _buildStatCard(String title, String value, IconData icon, Color color, {String? subtitle}) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Icon(icon, color: color, size: 28),
                if (int.tryParse(value) != null && int.parse(value) > 0)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: color.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      value,
                      style: TextStyle(
                        color: color,
                        fontWeight: FontWeight.bold,
                        fontSize: 18,
                      ),
                    ),
                  ),
              ],
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey.shade600,
                  ),
                ),
                if (subtitle != null)
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.grey.shade500,
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAISection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'AI Insights',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: ElevatedButton.icon(
                onPressed: _loadingPriorityAlerts ? null : _loadPriorityAlerts,
                icon: _loadingPriorityAlerts
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.priority_high),
                label: Text(_loadingPriorityAlerts ? 'Loading...' : 'Priority Alerts'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red.shade400,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: ElevatedButton.icon(
                onPressed: _loadingRecommendations ? null : _loadRecommendedActions,
                icon: _loadingRecommendations
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.lightbulb),
                label: Text(_loadingRecommendations ? 'Loading...' : 'Get Recommendations'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.deepPurple,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        if (_priorityAlerts != null) _buildAIResponseCard('Priority Alerts', _priorityAlerts!),
        if (_recommendedActions != null) _buildAIResponseCard('Recommended Actions', _recommendedActions!),
      ],
    );
  }

  Widget _buildAIResponseCard(String title, String content) {
    return Card(
      elevation: 1,
      color: Colors.blue.shade50,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.auto_awesome, color: Colors.deepPurple.shade700, size: 20),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.deepPurple.shade700,
                  ),
                ),
              ],
            ),
            const Divider(),
            Text(
              content,
              style: const TextStyle(fontSize: 14, height: 1.5),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildIncidentTypes() {
    if (_dashboardData == null || _dashboardData!['topIncidentTypes'] == null) {
      return const SizedBox.shrink();
    }

    final types = _dashboardData!['topIncidentTypes'] as List;
    if (types.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Incident Types Breakdown',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 12),
        Card(
          elevation: 1,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: types.map((type) {
                final typeName = type['type'] ?? 'Unknown';
                final count = type['count'] ?? 0;
                final total = _dashboardData!['totalReports'] ?? 1;
                final percentage = (count / total * 100).toStringAsFixed(1);
                
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            typeName,
                            style: const TextStyle(fontWeight: FontWeight.w500),
                          ),
                          Text(
                            '$count ($percentage%)',
                            style: TextStyle(
                              color: Colors.grey.shade600,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      LinearProgressIndicator(
                        value: count / total,
                        backgroundColor: Colors.grey.shade200,
                        valueColor: AlwaysStoppedAnimation<Color>(
                          _getColorForType(typeName),
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
          ),
        ),
      ],
    );
  }

  Color _getColorForType(String type) {
    switch (type.toString().toLowerCase()) {
      case 'sos':
        return Colors.red;
      case 'theft':
        return Colors.orange;
      case 'harassment':
        return Colors.purple;
      case 'vandalism':
        return Colors.blue;
      default:
        return Colors.green;
    }
  }

  Widget _buildRecentActivity() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Quick Stats',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 12),
        Card(
          elevation: 1,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                _buildQuickStatRow(
                  'Average Resolution Time',
                  '${_dashboardData?['avgResolutionMinutes'] ?? 0} minutes',
                  Icons.timer,
                ),
                const Divider(),
                _buildQuickStatRow(
                  'Reports This Week',
                  '${_dashboardData?['reportsLast7Days'] ?? 0}',
                  Icons.calendar_today,
                ),
                const Divider(),
                _buildQuickStatRow(
                  'Pending Rate',
                  '${_dashboardData?['pendingRate'] ?? 0}%',
                  Icons.trending_up,
                ),
                const Divider(),
                _buildQuickStatRow(
                  'Resolution Rate',
                  '${_dashboardData?['resolutionRate'] ?? 0}%',
                  Icons.trending_down,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildQuickStatRow(String label, String value, IconData icon) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Icon(icon, size: 20, color: Colors.deepPurple),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(fontSize: 14),
            ),
          ),
          Text(
            value,
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }
}
