import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'home_page.dart';

class CreateRoutePage extends StatefulWidget {
  @override
  _CreateRoutePageState createState() => _CreateRoutePageState();
}

class _CreateRoutePageState extends State<CreateRoutePage> {

  final HomePage homePage = HomePage();
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _urgencyController = TextEditingController();
  final _numberController = TextEditingController(); // Numara alanı için controller
  late final currentTime = getFormattedCurrentDate(); // Numara alanı için controller
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _urgencyController.dispose();
    _numberController.dispose(); // Numara alanı controller'ını da dispose ediyoruz
    super.dispose();
  }
  String getFormattedCurrentDate() {
    DateTime now = DateTime.now();
    DateFormat formatter = DateFormat('dd/MM/yyyy HH:mm:ss'); // İstediğiniz format
    String formattedDate = formatter.format(now);
    return formattedDate;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Güzergah Oluştur',style: TextStyle(color: Colors.white),),
        backgroundColor: Colors.blue, // Özelleştirilmiş AppBar rengi
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: EdgeInsets.all(16.0),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildTextField(
                  controller: _titleController,
                  label: 'Başlık',
                  validator: (value) => value!.isEmpty ? 'Lütfen başlık girin' : null,
                ),
                SizedBox(height: 16),
                _buildTextField(
                  controller: _descriptionController,
                  label: 'Açıklama',
                  maxLines: 3,
                ),
                SizedBox(height: 16),
                _buildTextField(
                  controller: _urgencyController,
                  label: 'Aciliyet (1-5)',
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  validator: (value) {
                    if (value!.isEmpty) return 'Lütfen aciliyet girin';
                    final urgency = int.tryParse(value);
                    return urgency != null && urgency >= 1 && urgency <= 5 ? null : 'Geçersiz aciliyet';
                  },
                ),
                SizedBox(height: 16),
                _buildTextField(
                  controller: _numberController,
                  label: 'Numara', // Numara alanı etiketi
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  validator: (value) => value!.isEmpty ? 'Lütfen numara girin' : null,
                ),
                SizedBox(height: 24),
                ElevatedButton(
                  onPressed: () {
                    if (_formKey.currentState!.validate()) {
                      _getCurrentLocationAndCreateRoute();
                    }
                  },
                  child: Text('Konumunu Kullan ve Oluştur', style: TextStyle(color: Colors.white)),
                  style: ElevatedButton.styleFrom(
                    primary: Colors.blue, // Özelleştirilmiş buton rengi
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    TextInputType keyboardType = TextInputType.text,
    List<TextInputFormatter>? inputFormatters,
    String? Function(String?)? validator,
    int maxLines = 1,
  }) {
    return TextFormField(
      controller: controller,
      decoration: InputDecoration(
        labelText: label,
        border: OutlineInputBorder(),
        fillColor: Colors.grey[200], // TextField arkaplan rengi
        filled: true,
      ),
      keyboardType: keyboardType,
      inputFormatters: inputFormatters,
      validator: validator,
      maxLines: maxLines,
    );
  }




  void _getCurrentLocationAndCreateRoute() async {
    try {
      // Kullanıcının konumunu al
      Position position = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);

      // Yeni bir marker oluştur
      final title = _titleController.text;
      final description = _descriptionController.text;
      final urgency = _urgencyController.text.trim();
      final number = _numberController.text.trim(); // Numara alanını al

      if (urgency.isEmpty || !urgency.contains(RegExp(r'^[1-5]$'))) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Geçersiz aciliyet değeri')),
        );
        return; // Fonksiyondan çık
      }

      if (number.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Lütfen geçerli bir numara girin')),
        );
        return; // Fonksiyondan çık
      }

      final urgencyValue = int.parse(urgency);

      // Firebase Authentication'dan currentUser'ı al
      final User? user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Kullanıcı oturum açmamış')),
        );
        return; // Fonksiyondan çık
      }
      final userId = user.uid; // Kullanıcının UID'sini al

      final newMarker = {
        'description': description,
        'latitude': position.latitude,
        'longitude': position.longitude,
        'title': title,
        'urgencyLevel': urgencyValue,
        'number': number, // Numara alanını da ekliyoruz
        'userId': userId,
        'currentTime': currentTime,// Kullanıcının UID'sini ekliyoruz
      };

      // Firestore'a yeni marker'ı ekle
      await _firestore.collection('Markers').add(newMarker);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Güzergah oluşturuldu.')),
      );

      Navigator.pop(context);
    } catch (e) {
      print('Konum alınamadı: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Konum alınamadı. Lütfen konum servislerini etkinleştirin.')),
      );
    }
  }

}
