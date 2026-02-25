import 'dart:convert';
import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_polyline_points/flutter_polyline_points.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;

class HeatmapScreen extends StatefulWidget {
  @override
  _HeatmapScreenState createState() => _HeatmapScreenState();
}

class _HeatmapScreenState extends State<HeatmapScreen> {
  GoogleMapController? _mapController;
  Set<Marker> _markers = {};
  Set<Polyline> _polylines = {};
  Set<Circle> _circles = {}; 
  Position? _currentPosition;
  final TextEditingController _destinationController = TextEditingController();
  
  StreamSubscription<Position>? _positionStreamSubscription;
  List<dynamic> _placePredictions = [];
  bool _isRouteSafe = true;
  bool _isJourneyStarted = false;
  String _walkingDistance = "";
  String _walkingDuration = "";

  String get googleMapsApiKey => dotenv.env['GOOGLE_MAPS_API_KEY'] ?? "";

  @override
  void initState() {
    super.initState();
    _startLocationTracking();
  }

  // --- 1. REAL-TIME TRACKING LOGIC ---
  Future<void> _startLocationTracking() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return;

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) return;
    }

    // This stream updates whenever you move
    _positionStreamSubscription = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 2, // Updates every 2 meters
      ),
    ).listen((Position position) {
      if (mounted) {
        setState(() => _currentPosition = position);
        
        // If 'Start Walk' is active, the camera follows you automatically
        if (_isJourneyStarted && _mapController != null) {
          _mapController!.animateCamera(
            CameraUpdate.newLatLng(LatLng(position.latitude, position.longitude)),
          );
        }
      }
    });
  }

  // --- 2. AUTOCOMPLETE METHOD (RESTORED) ---
  Future<void> _getAutocomplete(String input) async {
    if (input.isEmpty) {
      setState(() => _placePredictions = []);
      return;
    }
    final url = Uri.parse(
        'https://maps.googleapis.com/maps/api/place/autocomplete/json?input=$input&key=$googleMapsApiKey');
    try {
      final response = await http.get(url);
      final data = json.decode(response.body);
      if (data['status'] == 'OK') {
        setState(() => _placePredictions = data['predictions']);
      } else {
        setState(() => _placePredictions = []);
      }
    } catch (e) {
      debugPrint("Autocomplete error: $e");
    }
  }

  void _recenterCamera() {
    if (_currentPosition != null && _mapController != null) {
      _mapController!.animateCamera(
        CameraUpdate.newLatLngZoom(
          LatLng(_currentPosition!.latitude, _currentPosition!.longitude), 18),
      );
    }
  }

  // --- 3. DIRECTIONS LOGIC ---
  Future<void> _getDirections(String destinationText) async {
    if (_currentPosition == null || googleMapsApiKey.isEmpty) return;
    try {
      final geocodeUrl = Uri.parse('https://maps.googleapis.com/maps/api/geocode/json?address=${Uri.encodeComponent(destinationText)}&key=$googleMapsApiKey');
      final geoResponse = await http.get(geocodeUrl);
      final geoData = json.decode(geoResponse.body);
      if (geoData['status'] != 'OK') return;

      final destData = geoData['results'][0]['geometry']['location'];
      LatLng destinationLatLng = LatLng(destData['lat'], destData['lng']);

      final directionsUrl = Uri.parse('https://maps.googleapis.com/maps/api/directions/json?origin=${_currentPosition!.latitude},${_currentPosition!.longitude}&destination=${destinationLatLng.latitude},${destinationLatLng.longitude}&mode=walking&key=$googleMapsApiKey');
      final dirResponse = await http.get(directionsUrl);
      final dirData = json.decode(dirResponse.body);

      if (dirData['status'] == 'OK') {
        final route = dirData['routes'][0]['legs'][0];
        _walkingDistance = route['distance']['text'];
        _walkingDuration = route['duration']['text'];

        PolylinePoints polylinePoints = PolylinePoints();
        List<PointLatLng> resultPoints = polylinePoints.decodePolyline(dirData['routes'][0]['overview_polyline']['points']);
        List<LatLng> polylineCoordinates = resultPoints.map((p) => LatLng(p.latitude, p.longitude)).toList();

        bool safe = true;
        for (var circle in _circles) {
          for (var point in polylineCoordinates) {
            double dist = Geolocator.distanceBetween(point.latitude, point.longitude, circle.center.latitude, circle.center.longitude);
            if (dist < circle.radius) { safe = false; break; }
          }
        }

        setState(() {
          _isRouteSafe = safe;
          _polylines.clear();
          _polylines.add(Polyline(
            polylineId: const PolylineId("route"),
            color: safe ? Colors.blue.withOpacity(0.6) : Colors.red.withOpacity(0.6),
            points: polylineCoordinates,
            width: 5,
          ));
          _markers.clear();
          _markers.add(Marker(
            markerId: const MarkerId("destination"),
            position: destinationLatLng,
            icon: BitmapDescriptor.defaultMarkerWithHue(safe ? BitmapDescriptor.hueAzure : BitmapDescriptor.hueRed),
          ));
        });
        _mapController?.animateCamera(CameraUpdate.newLatLngZoom(destinationLatLng, 15.5));
      }
    } catch (e) { debugPrint("Routing Error: $e"); }
  }

  @override
  void dispose() {
    _positionStreamSubscription?.cancel(); // STOPS GPS TRACKING
    _destinationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // FULL SCREEN MAP
          Positioned.fill(
            child: _currentPosition == null
                ? const Center(child: CircularProgressIndicator())
                : StreamBuilder<QuerySnapshot>(
                    stream: FirebaseFirestore.instance.collection('reports').snapshots(),
                    builder: (context, snapshot) {
                      _circles.clear();
                      if (snapshot.hasData) {
                        for (var doc in snapshot.data!.docs) {
                          final data = doc.data() as Map<String, dynamic>;
                          if (data['Status'] != 'Pending') continue;
                          _circles.add(Circle(
                            circleId: CircleId(doc.id),
                            center: LatLng(data['GeoPoint'].latitude, data['GeoPoint'].longitude),
                            radius: 80,
                            fillColor: Colors.red.withOpacity(0.2),
                            strokeColor: Colors.red.withOpacity(0.4),
                            strokeWidth: 1,
                          ));
                        }
                      }
                      return GoogleMap(
                        initialCameraPosition: CameraPosition(target: LatLng(_currentPosition!.latitude, _currentPosition!.longitude), zoom: 15),
                        markers: _markers,
                        polylines: _polylines,
                        circles: _circles,
                        myLocationEnabled: true, // THIS SHOWS THE BLUE DOT
                        myLocationButtonEnabled: false, 
                        onMapCreated: (controller) => _mapController = controller,
                        padding: const EdgeInsets.only(bottom: 80),
                      );
                    },
                  ),
          ),

          // TRANSLUCENT SEARCH BAR
          if (!_isJourneyStarted)
            Positioned(
              top: MediaQuery.of(context).padding.top + 10,
              left: 15, right: 15,
              child: Column(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(25),
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                      child: Container(
                        color: Colors.white.withOpacity(0.7),
                        child: TextField(
                          controller: _destinationController,
                          onChanged: (value) => _getAutocomplete(value),
                          decoration: const InputDecoration(
                            hintText: "Search USM Location...",
                            prefixIcon: Icon(Icons.search_rounded),
                            border: InputBorder.none,
                            contentPadding: EdgeInsets.symmetric(vertical: 12),
                          ),
                        ),
                      ),
                    ),
                  ),
                  if (_placePredictions.isNotEmpty)
                    Container(
                      margin: const EdgeInsets.only(top: 5),
                      decoration: BoxDecoration(color: Colors.white.withOpacity(0.9), borderRadius: BorderRadius.circular(15)),
                      child: ListView.builder(
                        padding: EdgeInsets.zero, shrinkWrap: true,
                        itemCount: _placePredictions.length,
                        itemBuilder: (context, index) {
                          return ListTile(
                            title: Text(_placePredictions[index]['description']),
                            onTap: () {
                              String place = _placePredictions[index]['description'];
                              _destinationController.text = place;
                              setState(() => _placePredictions = []);
                              _getDirections(place);
                            },
                          );
                        },
                      ),
                    ),
                ],
              ),
            ),

          // START JOURNEY BUTTON
          if (_polylines.isNotEmpty && !_isJourneyStarted)
            Positioned(
              bottom: 135, left: 80, right: 80,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.green.withOpacity(0.85), shape: const StadiumBorder()),
                onPressed: () {
                  setState(() => _isJourneyStarted = true);
                  _recenterCamera();
                },
                child: const Text("START WALK", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              ),
            ),

          // INFO CARD
          if (_polylines.isNotEmpty)
            Positioned(
              bottom: 25, left: 20, right: 20,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                  child: Container(
                    padding: const EdgeInsets.all(15),
                    decoration: BoxDecoration(
                      color: _isRouteSafe ? Colors.white.withOpacity(0.7) : Colors.red.shade100.withOpacity(0.75),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          children: [
                            Icon(_isRouteSafe ? Icons.verified : Icons.error_outline, color: _isRouteSafe ? Colors.green : Colors.red),
                            const SizedBox(width: 8),
                            Text(_isRouteSafe ? "Clear Path" : "Danger Ahead", style: const TextStyle(fontWeight: FontWeight.bold)),
                            const Spacer(),
                            if (_isJourneyStarted)
                              GestureDetector(
                                onTap: () => setState(() => _isJourneyStarted = false),
                                child: const Icon(Icons.close, size: 18, color: Colors.grey),
                              )
                          ],
                        ),
                        const Divider(),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceAround,
                          children: [
                            Text(_walkingDuration, style: const TextStyle(fontWeight: FontWeight.bold)),
                            Text(_walkingDistance, style: const TextStyle(fontWeight: FontWeight.bold)),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),

          // RECENTER BUTTON
          Positioned(
            right: 15,
            bottom: _polylines.isNotEmpty ? 190 : 30,
            child: FloatingActionButton.small(
              backgroundColor: Colors.white.withOpacity(0.8),
              onPressed: _recenterCamera,
              child: const Icon(Icons.my_location, color: Colors.blue, size: 18),
            ),
          ),
        ],
      ),
    );
  }
}