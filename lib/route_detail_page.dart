import 'package:flutter/material.dart';

class RouteDetailPage extends StatelessWidget {
  final String routeId;

  RouteDetailPage({required this.routeId});

  @override
  Widget build(BuildContext context) {
    // Örnek güzergah verisi
    final routeData = {
      '1': {
        'title': 'Örnek Güzergah 1',
        'description': 'San Francisco - Aciliyet: 3',
        'details': 'Bu güzergah San Francisco şehir merkezinden geçmektedir.',
      },
      '2': {
        'title': 'Örnek Güzergah 2',
        'description': 'Oakland - Aciliyet: 5',
        'details': 'Bu güzergah Oakland\'dan San Francisco\'ya gitmektedir.',
      },
    };

    final route = routeData[routeId];

    return Scaffold(
      appBar: AppBar(title: Text(route?['title'] ?? 'Yolculuk Detayları')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.start,
          children: [
            Text(
              route?['description'] ?? '',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 20),
            Text(route?['details'] ?? ''),
            SizedBox(height: 20),
            ElevatedButton(
              onPressed: () {
                _acceptRoute(context);
              },
              child: Text('Yolculuğu Kabul Et'),
            ),
          ],
        ),
      ),
    );
  }

  void _acceptRoute(BuildContext context) {
    // Yolculuk kabul edildiğinde yapılacak işlemler
    Navigator.pop(context); // Geri dön
  }
}
