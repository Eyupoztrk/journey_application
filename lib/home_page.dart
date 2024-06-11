import 'dart:convert';
import 'dart:math';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:flutter/services.dart' show rootBundle;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:firebase_auth/firebase_auth.dart';

class HomePage extends StatefulWidget {
  @override
  _HomePageState createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  late GoogleMapController mapController;
  final Set<Marker> _markers = {};
  static const LatLng _initialPosition = LatLng(37.7749, 37.4194);
  LatLng _currentPosition = _initialPosition;
  String? _selectedMarkerId;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // Renk skalası
  final List<double> _urgencyHues = [
    BitmapDescriptor.hueYellow, // Düşük aciliyet
    BitmapDescriptor.hueYellow, // Orta düzey aciliyet
    BitmapDescriptor.hueOrange, // Orta-yüksek düzey aciliyet
    BitmapDescriptor.hueRed, // Yüksek aciliyet
    BitmapDescriptor.hueRed, // Çok yüksek aciliyet
  ];

  @override
  void initState() {
    super.initState();
    _determinePosition().then((position) {
      setState(() {
        _currentPosition = LatLng(position.latitude, position.longitude);
        _addCurrentLocationMarker();
        _loadMarkersFromFirestore();
      });
    });

    // Firestore'dan `Markers` koleksiyonunu dinle
    _firestore.collection('Markers').snapshots().listen((snapshot) {
      for (var change in snapshot.docChanges) {
        if (change.type == DocumentChangeType.added) {
          // Yeni bir belge eklendiğinde marker'ı haritaya ekle
          setState(() {
            _addMarkerFromDocument(change.doc);
          });
        } else if (change.type == DocumentChangeType.removed) {
          // Bir belge silindiğinde marker'ı haritadan kaldır
          setState(() {
            _markers.removeWhere((marker) => marker.markerId.value == change.doc.id);
          });
        } else if (change.type == DocumentChangeType.modified) {
          // Bir belge güncellendiğinde marker'ı güncelle
          setState(() {
            _markers.removeWhere((marker) => marker.markerId.value == change.doc.id);
            _addMarkerFromDocument(change.doc);
          });
        }
      }
    });
  }

  Future<void> _loadMarkersFromFirestore() async {
    try {
      QuerySnapshot snapshot = await _firestore.collection('Markers').get();
      final List<DocumentSnapshot> documents = snapshot.docs;

      setState(() {
        for (var document in documents) {
          _addMarkerFromDocument(document);
        }
      });
    } catch (e) {
      print('Firestore verileri alınamadı: $e');
    }
  }

  void _addMarkerFromDocument(DocumentSnapshot document) {
    Map<String, dynamic> markerData = document.data() as Map<String, dynamic>;
    int urgencyLevel = markerData['urgencyLevel'];
    double markerHue = _urgencyHues[min(urgencyLevel, _urgencyHues.length - 1)];

    _markers.add(
      Marker(
        markerId: MarkerId(document.id),
        position: LatLng(markerData['latitude'], markerData['longitude']),
        infoWindow: InfoWindow(
          title: markerData['title'],
          snippet: markerData['description'],
          onTap: () => _showRouteDetails(
            document.id, // Belge kimliğini _showRouteDetails'e geçin
            markerData['title'],
            markerData['description'],
            LatLng(markerData['latitude'], markerData['longitude']),
            markerData['number'],
            markerData['userId'],
            markerData['currentTime'],
          ),
        ),
        icon: BitmapDescriptor.defaultMarkerWithHue(markerHue),
      ),
    );
  }

  Future<Position> _determinePosition() async {
    bool serviceEnabled;
    LocationPermission permission;

    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      return Future.error('Konum servisleri devre dışı.');
    }

    permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        return Future.error('Konum izinleri reddedildi');
      }
    }

    if (permission == LocationPermission.deniedForever) {
      return Future.error('Konum izinleri kalıcı olarak reddedildi, izin ayarlarından değiştirin.');
    }

    return await Geolocator.getCurrentPosition();
  }

  Future<String> _getAddressFromLatLng(LatLng position) async {
    final url = Uri.parse(
        'https://maps.googleapis.com/maps/api/geocode/json?latlng=${position.latitude},${position.longitude}&key=AIzaSyAfHRmrXOSQ6Z-1ENLTrZRCK5NW02yJqfQ');
    final response = await http.get(url);
    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      if (data['results'].isNotEmpty) {
        return data['results'][0]['formatted_address'];
      }
    }
    return 'Adres bulunamadı';
  }

  Future<Map<String, dynamic>> _getDistanceAndDuration(LatLng origin, LatLng destination) async {
    final url = Uri.parse(
        'https://maps.googleapis.com/maps/api/distancematrix/json?units=metric&origins=${origin.latitude},${origin.longitude}&destinations=${destination.latitude},${destination.longitude}&key=AIzaSyAfHRmrXOSQ6Z-1ENLTrZRCK5NW02yJqfQ');
    final response = await http.get(url);
    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      if (data['rows'].isNotEmpty) {
        final elements = data['rows'][0]['elements'][0];
        return {
          'distance': elements['distance']['text'],
          'duration': elements['duration']['text']
        };
      }
    }
    return {'distance': 'Bilinmiyor', 'duration': 'Bilinmiyor'};
  }

  void _onMapCreated(GoogleMapController controller) {
    mapController = controller;
  }

  void _addCurrentLocationMarker() async {
    mapController.animateCamera(
      CameraUpdate.newLatLngZoom(_currentPosition, 14.0),
    );
  }

  void _showRouteDetails(String markerId, String title, String description, LatLng destination, String phoneNumber, String userId, String currentTime) async {
    _selectedMarkerId = markerId;
    String address = await _getAddressFromLatLng(destination);
    Map<String, dynamic> distanceAndDuration = await _getDistanceAndDuration(_currentPosition, destination);

    final User? user = FirebaseAuth.instance.currentUser;
    if (userId == user?.uid) {
      showModalBottomSheet(
        context: context,
        builder: (context) => Container(
          padding: EdgeInsets.all(16.0),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                Text(
                  description,
                  style: TextStyle(fontSize: 16),
                ),
                SizedBox(height: 10),
                Text(
                  'Adres:',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                Text(
                  address,
                  style: TextStyle(fontSize: 16),
                ),
                SizedBox(height: 10),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    ElevatedButton(
                      onPressed: () async {
                        await FirebaseFirestore.instance
                            .collection("Markers")
                            .doc(markerId)
                            .delete()
                            .then((_) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text("Yolculuk başarıyla silindi")),
                          );
                          setState(() {
                            _markers.removeWhere((marker) => marker.markerId.value == markerId);
                          });

                          Navigator.pop(context);
                        });
                      },
                      child: Text('Yolculuğu sil'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
    } else {
      showModalBottomSheet(
        context: context,
        builder: (context) => Container(
          padding: EdgeInsets.all(16.0),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                Text(
                  description,
                  style: TextStyle(fontSize: 16),
                ),
                SizedBox(height: 10),
                Text(
                  'Adres:',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                Text(
                  address,
                  style: TextStyle(fontSize: 16),
                ),
                SizedBox(height: 10),
                Text(
                  'Mesafe:',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                Text(
                  distanceAndDuration['distance'],
                  style: TextStyle(fontSize: 16),
                ),
                SizedBox(height: 10),
                Text(
                  'Tahmini Süre:',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                Text(
                  distanceAndDuration['duration'],
                  style: TextStyle(fontSize: 16),
                ),
                SizedBox(height: 10),
                Text(
                  'Oluşturulma Tarihi:',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                Text(
                  currentTime,
                  style: TextStyle(fontSize: 16),
                ),
                SizedBox(height: 10),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    ElevatedButton(
                      onPressed: () {
                        _launchNavigation(destination);
                        Navigator.pop(context);
                      },
                      child: Text('Yolculuğu Kabul Et'),
                    ),
                    ElevatedButton(
                      onPressed: () async {
                        String url = 'tel:$phoneNumber';
                        if (await canLaunch(url)) {
                          await launch(url);
                        } else {
                          throw 'Could not launch $url';
                        }
                      },
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16.0),
                        child: Row(
                          children: [
                            Icon(Icons.phone),
                            SizedBox(width: 8),
                            Text('Ara', style: TextStyle(fontSize: 16)),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
    }
  }

  void _launchNavigation(LatLng destination) async {
    final url = 'https://www.google.com/maps/dir/?api=1&destination=${destination.latitude},${destination.longitude}';
    if (await canLaunch(url)) {
      await launch(url);
    } else {
      throw 'Konum bulunamadı';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Journeyy App', style: TextStyle(color: Colors.white)),
        backgroundColor: Colors.blue,
      ),
      body: Stack(
        children: [
          GoogleMap(
            onMapCreated: _onMapCreated,
            initialCameraPosition: const CameraPosition(
              target: _initialPosition,
              zoom: 12,
            ),
            markers: _markers,
            myLocationButtonEnabled: true,
            myLocationEnabled: true,
          ),
          Positioned(
            top: 16.0,
            left: 16.0,
            child: Container(
              padding: EdgeInsets.all(8.0),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.85),
                borderRadius: BorderRadius.circular(8.0),
              ),
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.circle, color: Colors.yellowAccent, size: 12),
                      SizedBox(width: 4),
                      Text('Düşük', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.blueGrey)),
                    ],
                  ),
                  SizedBox(height: 4),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.circle, color: Colors.yellow, size: 12),
                      SizedBox(width: 4),
                      Text('Orta', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.blueGrey)),
                    ],
                  ),
                  SizedBox(height: 4),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.circle, color: Colors.orange, size: 12),
                      SizedBox(width: 4),
                      Text('Orta-Yüksek', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.blueGrey)),
                    ],
                  ),
                  SizedBox(height: 4),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.circle, color: Colors.red, size: 12),
                      SizedBox(width: 4),
                      Text('Yüksek', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.blueGrey)),
                    ],
                  ),
                  SizedBox(height: 4),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.circle, color: Colors.redAccent, size: 12),
                      SizedBox(width: 4),
                      Text('Çok Yüksek', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.blueGrey)),
                    ],
                  ),
                ],
              ),
            ),
          ),
          Align(
            alignment: Alignment.bottomLeft,
            child: Padding(
              padding: EdgeInsets.all(16.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  FloatingActionButton(
                    heroTag: 'addRouteButton',
                    onPressed: () {
                      _loadMarkersFromFirestore();
                      _addCurrentLocationMarker();
                      Navigator.pushNamed(context, '/createRoute');
                    },
                    backgroundColor: Colors.white.withOpacity(0.85),
                    child: Icon(Icons.add_location_alt_outlined),
                  ),
                  SizedBox(height: 16),
                  FloatingActionButton(
                    heroTag: 'profileButton',
                    onPressed: () {
                      Navigator.pushNamed(context, '/profile');
                    },
                    backgroundColor: Colors.white.withOpacity(0.85),
                    child: Icon(Icons.account_circle),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
