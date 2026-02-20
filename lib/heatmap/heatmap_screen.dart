import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class HeatmapScreen extends StatefulWidget {
  @override
  _HeatmapScreenState createState() => _HeatmapScreenState();
}

class _HeatmapScreenState extends State<HeatmapScreen> {
  String? selectedReportId; // track which marker is active

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance.collection('reports').snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(child: Text("Error: ${snapshot.error}"));
          }
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final reports = snapshot.data!.docs;

          return FlutterMap(
            options: MapOptions(
              center: LatLng(2.927962 , 101.642178),
              zoom: 15.5,
            ),
            children: [
              TileLayer(
                urlTemplate: "https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png",
                subdomains: ['a', 'b', 'c'],
              ),
              MarkerLayer(
                markers: reports.map((doc) {
                  final data = doc.data() as Map<String, dynamic>;

                  // Only show markers for Pending reports
                  if (data['Status'] != 'Pending') return null;

                  final geoPoint = data['GeoPoint'] as GeoPoint?;
                  if (geoPoint == null) return null;

                  final point = LatLng(geoPoint.latitude, geoPoint.longitude);
                  final isSelected = selectedReportId == doc.id;
                  final time = data['Time'] as Timestamp?;

                  return Marker(
                    width: 30,
                    height: 30,
                    point: point,
                    builder: (ctx) => GestureDetector(
                      onTap: () async {
                        setState(() {
                          selectedReportId = doc.id;
                        });

                        await showDialog(
                          context: context,
                          builder: (_) => AlertDialog(
                            title: Text(data['Type'] ?? "No Type"),
                            content: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text("Details: ${data['Details'] ?? ''}"),
                                Text("Location: ${data['Location'] ?? ''}"),
                                Text("Time: ${time != null ? time.toDate() : 'Unknown'}"),
                              ],
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(context),
                                child: const Text("Close"),
                              ),
                            ],
                          ),
                        );

                        setState(() {
                          selectedReportId = null;
                        });
                      },
                      child: TweenAnimationBuilder<double>(
                        tween: Tween<double>(
                          begin: 1.0,
                          end: isSelected ? 1.5 : 1.0,
                        ),
                        duration: const Duration(milliseconds: 300),
                        builder: (context, scale, child) {
                          return Transform.scale(
                            scale: scale,
                            child: Container(
                              width: 20,
                              height: 20,
                              decoration: BoxDecoration(
                                color: Colors.red.withOpacity(0.7),
                                shape: BoxShape.circle,
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  );
                }).whereType<Marker>().toList(),
              ),
            ],
          );
        },
      ),
    );
  }
}