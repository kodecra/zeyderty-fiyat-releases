import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'settings_helper.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
   final _komisyonController = TextEditingController(text: '21.5');
   final _stopajController = TextEditingController(text: '1.0');
   final _hizmetController = TextEditingController(text: '13.19');
   final _kargoController = TextEditingController(text: '77.54');
   final _kdvController = TextEditingController(text: '10');

   bool _loading = false;
   late final SettingsNotifier _settingsNotifier;

   @override
   void initState() {
     super.initState();
     _settingsNotifier = SettingsNotifier();
     _loadSettings();
   }

   Future<void> _loadSettings() async {
     final prefs = await SharedPreferences.getInstance();
     setState(() {
       _komisyonController.text = prefs.getString('komisyon') ?? '21.5';
       _stopajController.text = prefs.getString('stopaj') ?? '1.0';
       _hizmetController.text = prefs.getString('hizmet') ?? '13.19';
       _kargoController.text = prefs.getString('kargo') ?? '77.54';
       _kdvController.text = prefs.getString('kdv') ?? '10';
     });
   }

   Future<void> _saveSettings() async {
     final komisyon = double.tryParse(_komisyonController.text) ?? 21.5;
     final stopaj = double.tryParse(_stopajController.text) ?? 1.0;
     final hizmet = double.tryParse(_hizmetController.text) ?? 13.19;
     final kargo = double.tryParse(_kargoController.text) ?? 77.54;
     final kdv = double.tryParse(_kdvController.text) ?? 10;

     // SettingsNotifier üzerinden güncelle ve tüm sekmelere bildir
     await _settingsNotifier.updateSettings(
       komisyon: komisyon,
       stopaj: stopaj,
       hizmet: hizmet,
       kargo: kargo,
       kdv: kdv,
     );

     if (mounted) {
       ScaffoldMessenger.of(context).showSnackBar(
         const SnackBar(
           content: Text('Ayarlar kaydedildi ve tüm sekmeler güncellendi'),
           backgroundColor: Colors.green,
           duration: Duration(seconds: 2),
         ),
       );
     }
   }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Ayarlar'),
        actions: [
          IconButton(
            icon: const Icon(Icons.save),
            onPressed: _saveSettings,
            tooltip: 'Kaydet',
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            // Global Ayarlar
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Global Ayarlar',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),
                    _buildInputField('Komisyon Oranı (%)', _komisyonController),
                    const SizedBox(height: 10),
                    _buildInputField('Stopaj Oranı (%)', _stopajController),
                    const SizedBox(height: 10),
                    _buildInputField('Hizmet Bedeli (₺)', _hizmetController),
                    const SizedBox(height: 10),
                    _buildInputField('Kargo Ücreti (₺)', _kargoController),
                    const SizedBox(height: 10),
                    _buildInputField('KDV Oranı (%)', _kdvController),
                    const SizedBox(height: 12),
                    const Text(
                      'Bilgi',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      '• Ürünlere uzun basarak maliyet fiyatı ekleyebilirsiniz\n'
                      '• Hedef kar oranını Önerilen Fiyat sekmesinde ayarlayabilirsiniz\n'
                      '• Ayarlar kaydedildiğinde tüm sekmeler otomatik güncellenilir',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInputField(String label, TextEditingController controller) {
    return TextField(
      controller: controller,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      style: const TextStyle(
        fontSize: 14,
      ),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(
          fontSize: 14,
        ),
        border: const OutlineInputBorder(),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 8,
        ),
      ),
    );
  }

  @override
  void dispose() {
    _komisyonController.dispose();
    _stopajController.dispose();
    _hizmetController.dispose();
    _kargoController.dispose();
    _kdvController.dispose();
    super.dispose();
  }
}
