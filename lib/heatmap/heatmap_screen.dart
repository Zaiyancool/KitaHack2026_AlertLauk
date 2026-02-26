import 'dart:convert';
import 'dart:async';
import 'dart:ui' as ui;
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
  bool _isJourneyStarted = false;
  BitmapDescriptor? _personIcon;

  Map? _fastestRoute;
  Map? _safestRoute;
  List<LatLng> _fastestPoints = [];
  List<LatLng> _safestPoints = [];
  bool _isShowingSafest = true;
  String _walkingDistance = "";
  String _walkingDuration = "";

  String get googleMapsApiKey => dotenv.env['GOOGLE_MAPS_API_KEY'] ?? "";

  @override
  void initState() {
    super.initState();
    _createMarkerImage();
    _startLocationTracking();
  }

  Future<void> _createMarkerImage() async {
    final ui.PictureRecorder pictureRecorder = ui.PictureRecorder();
    final Canvas canvas = Canvas(pictureRecorder);
    final double size = 60.0; 

    final Paint paint = Paint()..color = Colors.blue.shade700;
    canvas.drawCircle(Offset(size / 2, size / 2), size / 2, paint);
    final Paint borderPaint = Paint()..color = Colors.white..style = PaintingStyle.stroke..strokeWidth = 3.0;
    canvas.drawCircle(Offset(size / 2, size / 2), size / 2, borderPaint);

    TextPainter textPainter = TextPainter(textDirection: TextDirection.ltr);
    textPainter.text = TextSpan(
      text: String.fromCharCode(Icons.person_pin.codePoint),
      style: TextStyle(fontSize: size * 0.7, fontFamily: Icons.person_pin.fontFamily, color: Colors.white),
    );
    textPainter.layout();
    textPainter.paint(canvas, Offset((size - textPainter.width) / 2, (size - textPainter.height) / 2));

    final image = await pictureRecorder.endRecording().toImage(size.toInt(), size.toInt());
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    if (mounted) setState(() => _personIcon = BitmapDescriptor.fromBytes(data!.buffer.asUint8List()));
  }

  Future<void> _startLocationTracking() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return;
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) permission = await Geolocator.requestPermission();

    _positionStreamSubscription = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, distanceFilter: 1),
    ).listen((Position position) {
      if (mounted) {
        setState(() => _currentPosition = position);
        if (_isJourneyStarted && _mapController != null) {
          _mapController!.animateCamera(CameraUpdate.newLatLng(LatLng(position.latitude, position.longitude)));
        }
      }
    });
  }

  // --- MODIFIED: High-Precision Safety Logic ---
  bool _isPathSafe(List<LatLng> points) {
    if (_circles.isEmpty) return true;

    for (var circle in _circles) {
      for (int i = 0; i < points.length - 1; i++) {
        LatLng start = points[i];
        LatLng end = points[i + 1];

        // We check 10 points between every corner to ensure we don't skip over a circle
        for (int j = 0; j <= 10; j++) {
          double lat = start.latitude + (end.latitude - start.latitude) * (j / 10);
          double lng = start.longitude + (end.longitude - start.longitude) * (j / 10);
          
          double dist = Geolocator.distanceBetween(
            lat, lng, 
            circle.center.latitude, circle.center.longitude
          );

          if (dist < circle.radius) return false;
        }
      }
    }
    return true;
  }

  Future<void> _getDirections(String destinationText) async {
    if (_currentPosition == null || googleMapsApiKey.isEmpty) return;
    try {
      final geocodeUrl = Uri.parse('https://maps.googleapis.com/maps/api/geocode/json?address=${Uri.encodeComponent(destinationText)}&key=$googleMapsApiKey');
      final geoResponse = await http.get(geocodeUrl);
      final geoData = json.decode(geoResponse.body);
      if (geoData['status'] != 'OK') return;

      LatLng destLatLng = LatLng(geoData['results'][0]['geometry']['location']['lat'], geoData['results'][0]['geometry']['location']['lng']);
      final directionsUrl = Uri.parse('https://maps.googleapis.com/maps/api/directions/json?origin=${_currentPosition!.latitude},${_currentPosition!.longitude}&destination=${destLatLng.latitude},${destLatLng.longitude}&mode=walking&alternatives=true&key=$googleMapsApiKey');
      
      final dirResponse = await http.get(directionsUrl);
      final dirData = json.decode(dirResponse.body);

      if (dirData['status'] == 'OK') {
        List routes = dirData['routes'];
        PolylinePoints polylinePoints = PolylinePoints();

        _fastestRoute = routes[0];
        _fastestPoints = polylinePoints.decodePolyline(_fastestRoute!['overview_polyline']['points']).map((p) => LatLng(p.latitude, p.longitude)).toList();
        
        _safestRoute = null;
        for (var route in routes) {
          List<LatLng> currentPath = polylinePoints.decodePolyline(route['overview_polyline']['points']).map((p) => LatLng(p.latitude, p.longitude)).toList();
          if (_isPathSafe(currentPath)) {
            _safestRoute = route;
            _safestPoints = currentPath;
            break; 
          }
        }
        _selectRoute(_safestRoute != null);
        _mapController?.animateCamera(CameraUpdate.newLatLngZoom(destLatLng, 15));
      }
    } catch (e) { debugPrint("Routing Error: $e"); }
  }

  void _selectRoute(bool useSafest) {
    setState(() {
      _isShowingSafest = useSafest;
      Map activeRoute = useSafest ? (_safestRoute ?? _fastestRoute)! : _fastestRoute!;
      List<LatLng> activePoints = useSafest ? (_safestPoints.isNotEmpty ? _safestPoints : _fastestPoints) : _fastestPoints;
      
      _walkingDistance = activeRoute['legs'][0]['distance']['text'];
      _walkingDuration = activeRoute['legs'][0]['duration']['text'];

      // COLOR LOGIC: Explicitly recalculate based on current path
      bool currentPathIsSafe = _isPathSafe(activePoints);
      Color routeColor = currentPathIsSafe ? Colors.green.withOpacity(0.8) : Colors.red.withOpacity(0.8);
      
      _polylines.clear();
      _polylines.add(Polyline(polylineId: const PolylineId("route"), color: routeColor, points: activePoints, width: 6));
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(
            child: _currentPosition == null
                ? const Center(child: CircularProgressIndicator())
                : LayoutBuilder(builder: (context, constraints) {
                    return StreamBuilder<QuerySnapshot>(
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
                              radius: 15, // Keep this radius consistent with logic
                              fillColor: Colors.red.withOpacity(0.2), 
                              strokeColor: Colors.red.withOpacity(0.4), 
                              strokeWidth: 2, 
                              consumeTapEvents: true, 
                              onTap: () => _showIncidentDetails(data['Type'] ?? "Alert", data['Description'] ?? "")
                            ));
                          }
                        }

                        // Build manual user marker
                        _markers.removeWhere((m) => m.markerId.value == "user_loc");
                        _markers.add(Marker(
                          markerId: const MarkerId("user_loc"),
                          position: LatLng(_currentPosition!.latitude, _currentPosition!.longitude),
                          icon: _personIcon ?? BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueCyan),
                          anchor: const Offset(0.5, 0.5),
                        ));

                        return GoogleMap(
                          initialCameraPosition: CameraPosition(target: LatLng(_currentPosition!.latitude, _currentPosition!.longitude), zoom: 16),
                          polylines: _polylines,
                          circles: _circles,
                          markers: _markers,
                          myLocationEnabled: false, 
                          myLocationButtonEnabled: false, 
                          onMapCreated: (controller) => _mapController = controller,
                          padding: const EdgeInsets.only(bottom: 120),
                        );
                      },
                    );
                  }),
          ),

          // (UI Widgets: Search, Tabs, Info Panel - keep your existing ones)
          if (!_isJourneyStarted)
            Positioned(top: MediaQuery.of(context).padding.top + 10, left: 15, right: 15, child: Column(children: [ClipRRect(borderRadius: BorderRadius.circular(30), child: BackdropFilter(filter: ui.ImageFilter.blur(sigmaX: 10, sigmaY: 10), child: Container(color: Colors.white.withOpacity(0.7), child: TextField(controller: _destinationController, onChanged: (v) => _getAutocomplete(v), decoration: const InputDecoration(hintText: "Safety Search USM...", prefixIcon: Icon(Icons.search, color: Colors.blue), border: InputBorder.none, contentPadding: EdgeInsets.symmetric(vertical: 12)))))), if (_placePredictions.isNotEmpty) Container(margin: const EdgeInsets.only(top: 5), decoration: BoxDecoration(color: Colors.white.withOpacity(0.9), borderRadius: BorderRadius.circular(20)), child: ListView.builder(padding: EdgeInsets.zero, shrinkWrap: true, itemCount: _placePredictions.length, itemBuilder: (context, index) { return ListTile(title: Text(_placePredictions[index]['description']), onTap: () { String place = _placePredictions[index]['description']; _destinationController.text = place; setState(() => _placePredictions = []); _getDirections(place); }); }))])),

          if (_fastestRoute != null && !_isJourneyStarted)
            Positioned(top: MediaQuery.of(context).padding.top + 75, left: 20, right: 20, child: Row(children: [Expanded(child: _routeTab("Fastest", false)), const SizedBox(width: 10), Expanded(child: _routeTab("Safest", true))])),

          if (_polylines.isNotEmpty)
            Positioned(bottom: 25, left: 20, right: 20, child: ClipRRect(borderRadius: BorderRadius.circular(20), child: BackdropFilter(filter: ui.ImageFilter.blur(sigmaX: 12, sigmaY: 12), child: Container(padding: const EdgeInsets.all(20), decoration: BoxDecoration(color: Colors.white.withOpacity(0.7), borderRadius: BorderRadius.circular(20)), child: Column(mainAxisSize: MainAxisSize.min, children: [if (!_isJourneyStarted) ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: Colors.green, shape: const StadiumBorder(), minimumSize: const Size(double.infinity, 45)), onPressed: () { setState(() => _isJourneyStarted = true); _recenterCamera(); }, child: const Text("START WALK", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold))), if (_isJourneyStarted) Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [const Text("Walking Active", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.green)), IconButton(onPressed: () => setState(() => _isJourneyStarted = false), icon: const Icon(Icons.close))]), const Divider(), Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [_infoDisplay(_walkingDuration), _infoDisplay(_walkingDistance)])]))))),

          Positioned(right: 15, bottom: _polylines.isNotEmpty ? 190 : 30, child: FloatingActionButton.small(backgroundColor: Colors.white.withOpacity(0.8), onPressed: _recenterCamera, child: const Icon(Icons.my_location, color: Colors.blue, size: 18))),
        ],
      ),
    );
  }

  // --- Helpers ---
  void _recenterCamera() {
    if (_currentPosition != null && _mapController != null) {
      _mapController!.animateCamera(CameraUpdate.newLatLngZoom(LatLng(_currentPosition!.latitude, _currentPosition!.longitude), 18));
    }
  }

  Widget _routeTab(String label, bool isSafeBtn) {
    bool active = _isShowingSafest == isSafeBtn;
    bool isAvailable = isSafeBtn ? _safestRoute != null : true;
    
    // TAB COLOR LOGIC: Use the high-precision check
    bool thisRouteSafe = isSafeBtn ? true : _isPathSafe(_fastestPoints);
    Color activeColor = thisRouteSafe ? Colors.green : Colors.red;

    return GestureDetector(onTap: isAvailable ? () => _selectRoute(isSafeBtn) : null, child: Opacity(opacity: isAvailable ? 1.0 : 0.4, child: Container(padding: const EdgeInsets.symmetric(vertical: 10), decoration: BoxDecoration(color: active ? activeColor : Colors.white.withOpacity(0.8), borderRadius: BorderRadius.circular(20)), child: Center(child: Text(label, style: TextStyle(color: active ? Colors.white : activeColor, fontWeight: FontWeight.bold))))));
  }

  Widget _infoDisplay(String text) {
    return Expanded(child: Text(text, textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis));
  }

  Future<void> _getAutocomplete(String input) async {
    setState(() { _placePredictions = []; _fastestRoute = null; _safestRoute = null; _polylines.clear(); _isJourneyStarted = false; });
    if (input.isEmpty) return;
    final url = Uri.parse('https://maps.googleapis.com/maps/api/place/autocomplete/json?input=$input&key=$googleMapsApiKey');
    try {
      final response = await http.get(url);
      final data = json.decode(response.body);
      if (data['status'] == 'OK') setState(() => _placePredictions = data['predictions']);
    } catch (e) { debugPrint("Autocomplete error: $e"); }
  }

  void _showIncidentDetails(String type, String desc) {
    showModalBottomSheet(context: context, backgroundColor: Colors.transparent, builder: (context) => Container(padding: const EdgeInsets.all(24), decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(25))), child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [Text(type, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.red)), const SizedBox(height: 10), Text(desc.isEmpty ? "No description provided." : desc, style: const TextStyle(fontSize: 16)), const SizedBox(height: 20), SizedBox(width: double.infinity, child: ElevatedButton(onPressed: () => Navigator.pop(context), child: const Text("Close")))])));
  }
}